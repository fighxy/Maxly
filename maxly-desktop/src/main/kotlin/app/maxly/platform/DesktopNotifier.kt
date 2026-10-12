package app.maxly.platform

import app.maxly.data.diagnostics.AppLog
import app.maxly.data.diagnostics.DiagnosticEvent
import app.maxly.domain.IncomingMessageNotice
import app.maxly.presentation.notifications.MessageNotificationRules
import java.awt.EventQueue
import java.awt.SystemTray
import java.awt.Toolkit
import java.awt.TrayIcon

/**
 * Уведомления о новых сообщениях, пока окно свёрнуто или не в фокусе: системное уведомление
 * через значок в трее (Windows — всплывающее уведомление, macOS — Центр уведомлений). Что
 * показывать — [MessageNotificationRules], как на телефонах. Нажатие на уведомление или значок
 * открывает чат последнего уведомления ([onOpen]).
 *
 * Где трея нет (часть оболочек Linux), уведомлений нет, остальное работает.
 */
class DesktopNotifier(private val onOpen: (chatId: String?) -> Unit) {
    @Volatile private var appActive = true
    @Volatile private var lastChat: String? = null
    private var icon: TrayIcon? = null
    private var unsupported = false

    fun setAppActive(active: Boolean) {
        appActive = active
    }

    fun incoming(notice: IncomingMessageNotice, enabled: Boolean) {
        val content = MessageNotificationRules.content(notice, appActive, enabled) ?: return
        val title = content.subtitle?.let { "${content.title} — $it" } ?: content.title
        EventQueue.invokeLater {
            val tray = trayIcon()
            if (tray == null) {
                DiagnosticEvent.event("notification.post", mapOf("kind" to "message", "result" to "unsupported"))
                return@invokeLater
            }
            lastChat = notice.chatId
            tray.displayMessage(title, content.body, TrayIcon.MessageType.NONE)
            DiagnosticEvent.event("notification.post", mapOf("kind" to "message", "result" to "ok"))
        }
    }

    /** Убрать значок из трея: при выходе из приложения. */
    fun dispose() {
        EventQueue.invokeLater {
            icon?.let { runCatching { SystemTray.getSystemTray().remove(it) } }
            icon = null
        }
    }

    private fun trayIcon(): TrayIcon? {
        icon?.let { return it }
        if (unsupported) return null
        if (!SystemTray.isSupported()) {
            unsupported = true
            AppLog.i("notifications", "Трея нет: уведомления о сообщениях не показываются")
            return null
        }
        return try {
            val image = Toolkit.getDefaultToolkit().getImage(DesktopNotifier::class.java.getResource("/images/app_icon.png"))
            TrayIcon(image, "Maxly").apply {
                isImageAutoSize = true
                // Нажатие на уведомление (Windows) и двойной щелчок по значку.
                addActionListener {
                    DiagnosticEvent.event("notification.action", mapOf("action" to "open", "kind" to "message"))
                    onOpen(lastChat)
                }
                SystemTray.getSystemTray().add(this)
            }.also { icon = it }
        } catch (e: Exception) {
            unsupported = true
            AppLog.w("notifications", "Значок в трее не добавлен", e)
            null
        }
    }
}
