package app.maxly.notifications

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import app.maxly.MainActivity
import app.maxly.R
import app.maxly.data.diagnostics.AppLog
import app.maxly.data.diagnostics.DiagnosticEvent
import app.maxly.domain.IncomingMessageNotice
import app.maxly.presentation.notifications.MessageNotificationRules

/**
 * Уведомления о новых сообщениях, пока приложение свёрнуто. Сервер Max шлёт пуши только своему
 * приложению, поэтому уведомление собирается на телефоне из сообщений, пришедших по соединению
 * ядра ([KeepAliveService] держит его). Что показывать — [MessageNotificationRules].
 *
 * Одно уведомление на чат: последние строки списком, заголовок — чат. Нажатие открывает чат.
 * Когда приложение снова на экране, уведомления убираются.
 */
class MessageNotifier(private val context: Context) {
    private val manager = NotificationManagerCompat.from(context)
    /** Последние строки каждого чата: уведомление чата показывает их списком. */
    private val lines = HashMap<String, ArrayDeque<String>>()
    private var appActive = true

    init {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.getSystemService(NotificationManager::class.java)?.createNotificationChannel(
                NotificationChannel(CHANNEL, "Сообщения", NotificationManager.IMPORTANCE_HIGH),
            )
        }
    }

    @Synchronized
    fun setAppActive(active: Boolean) {
        appActive = active
        if (!active) return
        lines.keys.forEach { manager.cancel(TAG, it.hashCode()) }
        lines.clear()
    }

    // Разрешение проверено через areNotificationsEnabled, отказ системы ловится ниже.
    @SuppressLint("MissingPermission")
    @Synchronized
    fun incoming(notice: IncomingMessageNotice, enabled: Boolean) {
        val content = MessageNotificationRules.content(notice, appActive, enabled) ?: return
        if (!manager.areNotificationsEnabled()) {
            DiagnosticEvent.event("notification.post", mapOf("kind" to "message", "result" to "disabled"))
            return
        }
        val line = content.subtitle?.let { "$it: ${content.body}" } ?: content.body
        val chatLines = lines.getOrPut(notice.chatId) { ArrayDeque() }
        chatLines.addLast(line)
        while (chatLines.size > LINES) chatLines.removeFirst()
        val style = NotificationCompat.InboxStyle().setBigContentTitle(content.title)
        chatLines.forEach(style::addLine)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(content.title)
            .setContentText(line)
            .setStyle(style)
            .setNumber(chatLines.size)
            .setWhen(notice.timeMs)
            .setShowWhen(true)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(open(notice.chatId))
            .build()
        try {
            manager.notify(TAG, notice.chatId.hashCode(), notification)
            DiagnosticEvent.event("notification.post", mapOf("kind" to "message", "result" to "ok"))
        } catch (e: SecurityException) {
            AppLog.w("notifications", "Уведомление не показано: ${e.message}")
            DiagnosticEvent.event("notification.post", mapOf("kind" to "message", "result" to "failed"))
        }
    }

    private fun open(chatId: String): PendingIntent = PendingIntent.getActivity(
        context, chatId.hashCode(),
        Intent(context, MainActivity::class.java)
            .setAction(ACTION_OPEN_CHAT)
            .putExtra(EXTRA_CHAT_ID, chatId)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    companion object {
        const val CHANNEL = "messages"
        const val ACTION_OPEN_CHAT = "app.maxly.message.OPEN_CHAT"
        const val EXTRA_CHAT_ID = "chatId"
        private const val TAG = "chat"
        private const val LINES = 6
    }
}
