package app.maxly.notifications

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import app.maxly.MainActivity
import app.maxly.R
import app.maxly.data.diagnostics.AppLog

/**
 * Служба переднего плана, пока включены «Звонки и сообщения в фоне»: с ней Android не
 * усыпляет свёрнутое приложение, и соединение ядра остаётся — входящие звонки и сообщения
 * приходят, как при открытом приложении. Сама служба ничего не делает: работает процесс.
 *
 * В шторке — тихое постоянное уведомление (канал можно скрыть в настройках Android).
 * Запускается, пока приложение на экране (из фона Android запускать её не даёт), и живёт
 * до выхода из аккаунта или выключения настройки.
 */
class KeepAliveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            runCatching { ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE) }
            stopSelf()
            return START_NOT_STICKY
        }
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING else 0
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification(), type)
            AppLog.i("notifications", "Фоновая связь включена")
        } catch (e: Exception) {
            // Система не дала выйти на передний план (например, перезапуск службы из фона).
            AppLog.w("notifications", "Фоновая связь не включилась: ${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onDestroy() {
        // Систему могли попросить закрыть службу: следующий выход на экран запустит её снова.
        started = false
        super.onDestroy()
    }

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(
            this, 7,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Maxly на связи")
            .setContentText("Звонки и сообщения приходят, пока приложение свёрнуто")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(open)
            .build()
    }

    companion object {
        const val CHANNEL = "background"
        private const val NOTIFICATION_ID = 4201
        private const val ACTION_STOP = "app.maxly.keepalive.STOP"
        @Volatile private var started = false

        fun start(context: Context) {
            if (started) return
            createChannel(context)
            try {
                ContextCompat.startForegroundService(context, Intent(context, KeepAliveService::class.java))
                started = true
            } catch (e: Exception) {
                AppLog.w("notifications", "Фоновая связь: служба не запущена: ${e.message}")
            }
        }

        fun stop(context: Context) {
            if (!started) return
            started = false
            context.stopService(Intent(context, KeepAliveService::class.java))
        }

        private fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            context.getSystemService(NotificationManager::class.java)?.createNotificationChannel(
                NotificationChannel(CHANNEL, "Фоновая связь", NotificationManager.IMPORTANCE_MIN).apply {
                    setShowBadge(false)
                },
            )
        }
    }
}
