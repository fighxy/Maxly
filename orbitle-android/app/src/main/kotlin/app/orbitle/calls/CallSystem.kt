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
                notifications.notify(INCOMING_ID, incoming(snapshot))
            }
            else -> {
                notifications.cancel(INCOMING_ID)
                CallForegroundService.start(context, snapshot.title, camera = snapshot.camera, screen = snapshot.screen)
            }
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
 */
class CallForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE).orEmpty().ifEmpty { "Звонок" }
        val camera = intent?.getBooleanExtra(EXTRA_CAMERA, false) == true
        val screen = intent?.getBooleanExtra(EXTRA_SCREEN, false) == true || screenAllowed
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
        val notification = NotificationCompat.Builder(this, AndroidCallSystem.CHANNEL_ONGOING)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText("Идёт звонок")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(0, "Завершить", hangUp)
            .build()
        var types = 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (CallPermissions.granted(Manifest.permission.RECORD_AUDIO)) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            if (camera && CallPermissions.granted(Manifest.permission.CAMERA)) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && screen) {
            types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
        }
        runCatching { ServiceCompat.startForeground(this, AndroidCallSystem.ONGOING_ID, notification, types) }
        if (screen) screenReady?.complete(Unit)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        screenAllowed = false
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_CAMERA = "camera"
        private const val EXTRA_SCREEN = "screen"

        /** Пользователь разрешил показ экрана: служба добавляет тип mediaProjection. */
        @Volatile
        private var screenAllowed = false
        private var running = false
        private var last: Triple<String, Boolean, Boolean>? = null

        fun start(context: Context, title: String, camera: Boolean, screen: Boolean) {
            val wanted = Triple(title, camera, screen)
            if (running && last == wanted) return
            last = wanted
            running = true
            val intent = Intent(context, CallForegroundService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_CAMERA, camera)
                .putExtra(EXTRA_SCREEN, screen)
            runCatching { ContextCompat.startForegroundService(context, intent) }
        }

        fun stop(context: Context) {
            if (!running) return
            running = false
            last = null
            screenAllowed = false
            context.stopService(Intent(context, CallForegroundService::class.java))
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
            kotlinx.coroutines.withTimeoutOrNull(2_000) { ready.await() }
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
