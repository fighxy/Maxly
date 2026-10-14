package app.maxly.platform

import app.maxly.data.diagnostics.DiagnosticEvent
import app.maxly.domain.IncomingMessageNotice
import app.maxly.presentation.notifications.MessageNotificationRules
import java.awt.EventQueue
import java.awt.Toolkit

/**
 * Уведомления о новых сообщениях, пока окно свёрнуто, спрятано в трей или не в фокусе: системное
 * уведомление через общий значок [tray] (Windows — всплывающее уведомление, macOS — Центр
 * уведомлений). Что показывать — [MessageNotificationRules], как на телефонах. Нажатие на
 * уведомление открывает окно и чат. Звук — системный сигнал, если не включено «Без звука» ([muted]).
 *
 * Где трея нет (часть оболочек Linux), уведомлений нет, остальное работает.
 */
class DesktopNotifier(private val tray: DesktopTray, private val muted: () -> Boolean) {
    @Volatile private var appActive = true

    fun setAppActive(active: Boolean) {
        appActive = active
    }

    fun incoming(notice: IncomingMessageNotice, enabled: Boolean) {
        val content = MessageNotificationRules.content(notice, appActive, enabled) ?: return
        val title = content.subtitle?.let { "${content.title} — $it" } ?: content.title
        EventQueue.invokeLater {
            if (!tray.notify(title, content.body, notice.chatId)) {
                DiagnosticEvent.event("notification.post", mapOf("kind" to "message", "result" to "unsupported"))
                return@invokeLater
            }
            if (!muted()) runCatching { Toolkit.getDefaultToolkit().beep() }
            DiagnosticEvent.event("notification.post", mapOf("kind" to "message", "result" to "ok"))
        }
    }
}
