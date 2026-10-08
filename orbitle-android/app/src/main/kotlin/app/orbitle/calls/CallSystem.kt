package app.orbitle.calls

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import app.orbitle.MainActivity
import app.orbitle.OrbitleApp
import app.orbitle.R
import app.orbitle.data.calls.CallLog
import app.orbitle.presentation.calls.ActiveCall
import app.orbitle.presentation.calls.CallCenter
import app.orbitle.presentation.calls.CallCenterState
import app.orbitle.presentation.calls.CallStatusText
import app.orbitle.ui.calls.CallSounds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * Звонок для системы Android: уведомление входящего (полноэкранное, с «Ответить» и
 * «Отклонить»), служба переднего плана, пока идёт разговор (микрофон, камера, показ экрана в
 * фоне), датчик приближения у уха.
 */
class AndroidCallSystem(private val context: Context, private val center: CallCenter, scope: CoroutineScope) {
    private val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private var proximity: PowerManager.WakeLock? = null

    init {
        createChannels()
        scope.launch {
            center.state.map(::snapshot).distinctUntilChanged().collect(::apply)
        }
    }

    /** Что из состояния звонка важно системе. */
    private data class Snapshot(
        val id: String?,
        val ringing: Boolean,
        val ended: Boolean,
        val title: String,
        val video: Boolean,
        val camera: Boolean,
        val screen: Boolean,
        val nearEar: Boolean,
    )

    private fun snapshot(state: CallCenterState): Snapshot {
        val call = state.call
        return Snapshot(
            id = call?.id,
            ringing = call?.isRinging == true,
            ended = call?.state?.isEnded == true,
            title = call?.peer?.name?.ifEmpty { "Звонок Max" } ?: "",
            video = call?.isVideo == true,
            camera = call?.state?.cameraOn == true,
            screen = call?.state?.screenSharing == true,
            nearEar = call != null && nearEar(call),
        )
    }

    /** Звонок без видео и без громкой связи: телефон у уха гасит экран. */
    private fun nearEar(call: ActiveCall): Boolean {
        if (call.state.isEnded || call.isRinging) return false
        return !call.state.cameraOn && !call.state.speakerOn && call.state.others.all { it.visibleTrack == null }
    }

    private fun apply(snapshot: Snapshot) {
        setProximity(snapshot.nearEar)
        when {
            snapshot.id == null || snapshot.ended -> {
                notifications.cancel(INCOMING_ID)
                CallForegroundService.stop(context)
            }
            snapshot.ringing -> {
                CallForegroundService.stop(context)
                showIncoming(snapshot)
            }
            else -> {
                notifications.cancel(INCOMING_ID)
                CallForegroundService.start(context, snapshot.title, camera = snapshot.camera, screen = snapshot.screen)
            }
        }
    }

    private fun showIncoming(snapshot: Snapshot) {
        if (!notifications.areNotificationsEnabled()) {
            CallLog.warning("Входящий: уведомления Orbitle выключены — звонок виден только в открытом приложении")
        }
        if (Build.VERSION.SDK_INT >= 34 && !notifications.canUseFullScreenIntent()) {
            CallLog.warning("Входящий: нет разрешения на полноэкранные уведомления")
        }
        try {
            notifications.notify(INCOMING_ID, incoming(snapshot))
            CallLog.info("Входящий: уведомление показано")
        } catch (e: Exception) {
            CallLog.error("Входящий: уведомление не показано", e)
        }
    }

    private fun incoming(snapshot: Snapshot): Notification {
        val open = activity(ACTION_OPEN, 1)
        return NotificationCompat.Builder(context, CHANNEL_INCOMING)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(snapshot.title)
            .setContentText(CallStatusText.incomingTitle(snapshot.video))
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(open)
            .setFullScreenIntent(open, true)
            .addAction(0, "Отклонить", broadcast(ACTION_DECLINE, 2))
            .addAction(0, "Ответить", activity(ACTION_ANSWER, 3))
            .build()
    }

    private fun activity(action: String, code: Int): PendingIntent = PendingIntent.getActivity(
        context, code,
        Intent(context, MainActivity::class.java).setAction(action).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun broadcast(action: String, code: Int): PendingIntent = PendingIntent.getBroadcast(
        context, code,
        Intent(context, CallActionReceiver::class.java).setAction(action),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    @Suppress("WakelockTimeout")
    private fun setProximity(on: Boolean) {
        if (on) {
            if (proximity?.isHeld == true) return
            if (!power.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) return
            proximity = power.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "orbitle:call").apply { acquire() }
        } else {
            proximity?.takeIf { it.isHeld }?.release()
            proximity = null
        }
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        // Звонок входящего играет само приложение: у канала звука нет, только важность.
        notifications.createNotificationChannel(
            NotificationChannel(CHANNEL_INCOMING, "Входящие звонки", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(null, null)
                enableVibration(false)
            },
        )
        notifications.createNotificationChannel(
            NotificationChannel(CHANNEL_ONGOING, "Идущий звонок", NotificationManager.IMPORTANCE_LOW),
        )
    }

    companion object {
        const val CHANNEL_INCOMING = "calls.incoming"
        const val CHANNEL_ONGOING = "calls.ongoing"
        const val INCOMING_ID = 4101
        const val ONGOING_ID = 4102
        const val ACTION_OPEN = "app.orbitle.call.OPEN"
        const val ACTION_ANSWER = "app.orbitle.call.ANSWER"
        const val ACTION_DECLINE = "app.orbitle.call.DECLINE"
        const val ACTION_HANG_UP = "app.orbitle.call.HANG_UP"
    }
}

/** «Отклонить» и «Завершить» из уведомления: без открытия приложения. */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val container = (context.applicationContext as OrbitleApp).container
        CallLog.info("Кнопка уведомления: ${intent.action?.substringAfterLast('.')}")
        container.scope.launch {
            when (intent.action) {
                AndroidCallSystem.ACTION_DECLINE -> container.callCenter.decline()
                AndroidCallSystem.ACTION_HANG_UP -> container.callCenter.hangUp()
            }
        }
    }
}

/**
 * Служба переднего плана, пока идёт разговор: без неё Android отнимет у свёрнутого приложения
 * микрофон и камеру. Тип — микрофон, плюс камера и показ экрана, когда они включены.
 *
 * Служба запускается обычным `startService` (приложение в этот момент на экране) и сама
 * выходит на передний план. Так звонок, который сорвался через миг после начала, можно
 * остановить в любой момент: служба, запущенная через `startForegroundService`, обязана успеть
 * вызвать `startForeground`, иначе система роняет приложение — и `stopService` до этого вызова
 * тоже роняет. `startForegroundService` остаётся запасным путём, если обычный запуск запрещён
 * (приложение в фоне); тогда остановка ждёт, пока служба вышла на передний план.
 */
class CallForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val viaForegroundStart = intent?.getBooleanExtra(EXTRA_FOREGROUND_START, false) == true
        if (viaForegroundStart) pendingForegroundStart = false
        if (!running && !viaForegroundStart) {
            CallLog.info("Служба звонка: звонок уже закончился, не запускаюсь")
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra(EXTRA_TITLE).orEmpty().ifEmpty { "Звонок" }
        val camera = intent?.getBooleanExtra(EXTRA_CAMERA, false) == true
        val screen = intent?.getBooleanExtra(EXTRA_SCREEN, false) == true || screenAllowed
        val foreground = enterForeground(notification(title), camera, screen)
        if (screen) screenReady?.complete(Unit)
        when {
            !running -> {
                // Звонок закончился, пока служба запускалась через startForegroundService.
                CallLog.info("Служба звонка: звонок уже закончился, останавливаюсь")
                stopSelfSafely(foreground)
            }
            !foreground && viaForegroundStart -> {
                CallLog.warning("Служба звонка не вышла на передний план после startForegroundService: система может закрыть приложение")
            }
            !foreground -> {
                CallLog.warning("Служба звонка не вышла на передний план: в фоне Android может отнять микрофон")
            }
        }
        return START_NOT_STICKY
    }

    private fun notification(title: String): Notification {
        val open = PendingIntent.getActivity(
            this, 5,
            Intent(this, MainActivity::class.java).setAction(AndroidCallSystem.ACTION_OPEN).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val hangUp = PendingIntent.getBroadcast(
            this, 6,
            Intent(this, CallActionReceiver::class.java).setAction(AndroidCallSystem.ACTION_HANG_UP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, AndroidCallSystem.CHANNEL_ONGOING)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText("Идёт звонок")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(0, "Завершить", hangUp)
            .build()
    }

    /**
     * Передний план с нужными типами; если система их не дала (нет разрешения, приложение не
     * на экране) — только микрофон, потом без типа (до Android 14 это разрешено).
     */
    private fun enterForeground(notification: Notification, camera: Boolean, screen: Boolean): Boolean {
        for (types in foregroundTypes(camera, screen)) {
            try {
                ServiceCompat.startForeground(this, AndroidCallSystem.ONGOING_ID, notification, types)
                CallLog.info("Служба звонка на переднем плане: ${typeNames(types)}")
                return true
            } catch (e: Exception) {
                CallLog.error("startForeground (${typeNames(types)}) не удался", e)
            }
        }
        return false
    }

    private fun stopSelfSafely(allowed: Boolean) {
        // Без startForeground остановка службы, запущенной startForegroundService, роняет процесс.
        if (!allowed) return
        runCatching { ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE) }
        stopSelf()
    }

    override fun onDestroy() {
        CallLog.info("Служба звонка остановлена")
        screenAllowed = false
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_CAMERA = "camera"
        private const val EXTRA_SCREEN = "screen"
        private const val EXTRA_FOREGROUND_START = "foregroundStart"

        /** Пользователь разрешил показ экрана: служба добавляет тип mediaProjection. */
        @Volatile
        private var screenAllowed = false

        /** Служба нужна (идёт звонок). Меняется только на главном потоке. */
        private var running = false

        /** Служба запущена через `startForegroundService` и ещё не дошла до `onStartCommand`. */
        private var pendingForegroundStart = false
        private var last: Triple<String, Boolean, Boolean>? = null

        /** Наборы типов по убыванию: сначала всё нужное, потом только микрофон, потом без типа. */
        internal fun foregroundTypes(camera: Boolean, screen: Boolean): List<Int> {
            var preferred = 0
            var microphone = 0
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                if (CallPermissions.granted(Manifest.permission.RECORD_AUDIO)) microphone = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                preferred = microphone
                if (camera && CallPermissions.granted(Manifest.permission.CAMERA)) preferred = preferred or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && screen) {
                preferred = preferred or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            }
            return listOf(preferred, microphone, 0).distinct()
        }

        private fun typeNames(types: Int): String {
            if (types == 0) return "без типа"
            val names = buildList {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    if (types and ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE != 0) add("микрофон")
                    if (types and ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA != 0) add("камера")
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && types and ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION != 0) add("экран")
            }
            return names.joinToString(" + ")
        }

        fun start(context: Context, title: String, camera: Boolean, screen: Boolean) {
            val wanted = Triple(title, camera, screen)
            if (running && last == wanted) return
            last = wanted
            running = true
            val intent = Intent(context, CallForegroundService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_CAMERA, camera)
                .putExtra(EXTRA_SCREEN, screen)
            try {
                context.startService(intent)
                CallLog.info("Служба звонка: запуск (камера: $camera, экран: $screen)")
            } catch (e: IllegalStateException) {
                // Приложение в фоне: обычный запуск запрещён, остаётся запуск переднего плана.
                CallLog.warning("Служба звонка: обычный запуск запрещён ($e), запускаю как службу переднего плана")
                try {
                    ContextCompat.startForegroundService(context, intent.putExtra(EXTRA_FOREGROUND_START, true))
                    pendingForegroundStart = true
                } catch (e: Exception) {
                    CallLog.error("Служба звонка не запустилась", e)
                    running = false
                    last = null
                }
            } catch (e: Exception) {
                CallLog.error("Служба звонка не запустилась", e)
                running = false
                last = null
            }
        }

        fun stop(context: Context) {
            if (!running) return
            running = false
            last = null
            screenAllowed = false
            if (pendingForegroundStart) {
                // Остановить сейчас — значит уронить приложение; служба остановится сама.
                CallLog.info("Служба звонка: остановится сама, когда выйдет на передний план")
                return
            }
            CallLog.info("Служба звонка: остановка")
            runCatching { context.stopService(Intent(context, CallForegroundService::class.java)) }
                .onFailure { CallLog.error("Служба звонка не остановилась", it) }
        }

        private var screenReady: kotlinx.coroutines.CompletableDeferred<Unit>? = null

        /**
         * Перед MediaProjection служба уже должна работать с типом mediaProjection (Android 14):
         * ждём, пока она его взяла, но не дольше 2 с.
         */
        suspend fun allowScreenCapture(context: Context) {
            screenAllowed = true
            val ready = kotlinx.coroutines.CompletableDeferred<Unit>()
            screenReady = ready
            val (title, camera, _) = last ?: Triple("Звонок", false, true)
            last = null
            running = false
            start(context, title, camera, screen = true)
            if (kotlinx.coroutines.withTimeoutOrNull(2_000) { ready.await() } == null) {
                CallLog.warning("Служба звонка не подтвердила показ экрана за 2 с")
            }
            screenReady = null
        }
    }
}

/** Гудки исходящего (тон линии 425 Гц) и звонок входящего (системная мелодия, вибрация). */
class AndroidCallSounds(private val context: Context) : CallSounds {
    private var tone: ToneGenerator? = null
    private var ringtone: Ringtone? = null
    private var vibrating = false
    private var playing: String? = null

    override fun ringback() {
        if (playing == "ringback") return
        stop()
        playing = "ringback"
        tone = runCatching { ToneGenerator(AudioManager.STREAM_VOICE_CALL, 80) }.getOrNull()
        tone?.startTone(ToneGenerator.TONE_SUP_RINGTONE)
    }

    override fun ringtone() {
        if (playing == "ringtone") return
        stop()
        playing = "ringtone"
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (audio.ringerMode == AudioManager.RINGER_MODE_NORMAL) {
            ringtone = runCatching {
                RingtoneManager.getRingtone(context, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))?.apply {
                    audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isLooping = true
                    play()
                }
            }.getOrNull()
        }
        if (audio.ringerMode != AudioManager.RINGER_MODE_SILENT) {
            vibrator()?.let {
                it.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 800, 1200), 0))
                vibrating = true
            }
        }
    }

    override fun stop() {
        playing = null
        tone?.let {
            runCatching { it.stopTone() }
            runCatching { it.release() }
        }
        tone = null
        ringtone?.let { runCatching { it.stop() } }
        ringtone = null
        if (vibrating) vibrator()?.cancel()
        vibrating = false
    }

    private fun vibrator(): Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }
}
