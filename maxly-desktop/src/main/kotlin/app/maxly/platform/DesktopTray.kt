package app.maxly.platform

import app.maxly.data.diagnostics.AppLog
import java.awt.CheckboxMenuItem
import java.awt.Color
import java.awt.EventQueue
import java.awt.Image
import java.awt.MenuItem
import java.awt.PopupMenu
import java.awt.RenderingHints
import java.awt.SystemTray
import java.awt.TrayIcon
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import java.awt.image.BufferedImage
import javax.imageio.ImageIO

/**
 * Единственный значок Maxly в трее: показать или спрятать окно по щелчку, меню «Открыть Maxly»,
 * «Без звука», «Выход», число непрочитанных в подсказке и точка на значке. Через него же
 * [DesktopNotifier] показывает уведомления; нажатие на уведомление открывает окно и чат.
 *
 * Где трея нет (часть оболочек Linux), [supported] — `false`, закрытие окна выходит из приложения.
 * Все обработчики вызываются в потоке AWT.
 */
class DesktopTray(
    private val onToggle: () -> Unit,
    private val onOpen: (chatId: String?) -> Unit,
    private val onMuteChange: (Boolean) -> Unit,
    private val onExit: () -> Unit,
) {
    private var icon: TrayIcon? = null
    private var muteItem: CheckboxMenuItem? = null
    private var base: BufferedImage? = null
    private var unread = 0
    @Volatile private var lastChat: String? = null
    /** Время последнего уведомления: щелчок по нему на части систем приходит как щелчок по значку. */
    @Volatile private var lastNoticeAt = 0L
    /** Приходят ли щелчки мышью по значку: тогда переключает окно одинарный щелчок. */
    private var clickSeen = false

    /** Есть ли трей. Значок добавляется сразу. */
    val supported: Boolean = runCatching { SystemTray.isSupported() }.getOrDefault(false).also { ok ->
        if (!ok) AppLog.i("notifications", "Трея нет: уведомления о сообщениях не показываются, закрытие окна — выход")
    }

    init {
        if (supported) EventQueue.invokeLater { create() }
    }

    private fun create() {
        if (icon != null) return
        try {
            val image = DesktopTray::class.java.getResourceAsStream("/images/app_icon.png")?.use { ImageIO.read(it) }
                ?: BufferedImage(32, 32, BufferedImage.TYPE_INT_ARGB)
            base = image
            val size = SystemTray.getSystemTray().trayIconSize
            val mute = CheckboxMenuItem(TrayText.MUTE).apply { addItemListener { onMuteChange(state) } }
            muteItem = mute
            val menu = PopupMenu().apply {
                add(MenuItem(TrayText.OPEN).apply { addActionListener { onOpen(null) } })
                add(mute)
                addSeparator()
                add(MenuItem(TrayText.EXIT).apply { addActionListener { onExit() } })
            }
            icon = TrayIcon(render(image, size.width, size.height, unread > 0), TrayText.tooltip(unread), menu).apply {
                isImageAutoSize = true
                // Нажатие на всплывающее уведомление (Windows) и двойной щелчок по значку: после
                // недавнего уведомления открывается его чат, иначе окно уже переключил первый щелчок.
                addActionListener {
                    val chat = lastChat
                    if (chat != null && System.currentTimeMillis() - lastNoticeAt < NOTICE_CLICK_MS) {
                        lastChat = null
                        onOpen(chat)
                    } else if (!clickSeen) {
                        // Система, где щелчок мышью по значку не приходит (часть macOS и Linux).
                        onToggle()
                    }
                }
                addMouseListener(object : MouseAdapter() {
                    override fun mouseClicked(e: MouseEvent) {
                        clickSeen = true
                        // Первый щелчок левой кнопкой; второй щелчок двойного уже ничего не переключает.
                        if (e.button == MouseEvent.BUTTON1 && e.clickCount == 1) onToggle()
                    }
                })
            }
            SystemTray.getSystemTray().add(icon)
        } catch (e: Exception) {
            icon = null
            AppLog.w("notifications", "Значок в трее не добавлен", e)
        }
    }

    /** Отметка «Без звука» в меню. */
    fun setMuted(muted: Boolean) = EventQueue.invokeLater { muteItem?.state = muted }

    /** Непрочитанные: подсказка и точка на значке. */
    fun setUnread(count: Int) = EventQueue.invokeLater {
        val changedDot = (count > 0) != (unread > 0)
        unread = count
        val icon = icon ?: return@invokeLater
        icon.toolTip = TrayText.tooltip(count)
        if (changedDot) base?.let { icon.image = render(it, icon.size.width, icon.size.height, count > 0) }
    }

    /** Показать уведомление; `false`, если трея нет. Вызывать в потоке AWT. */
    fun notify(title: String, body: String, chatId: String?): Boolean {
        val icon = icon ?: return false
        lastChat = chatId
        lastNoticeAt = System.currentTimeMillis()
        icon.displayMessage(title, body, TrayIcon.MessageType.NONE)
        return true
    }

    /** Убрать значок: при выходе из приложения. */
    fun dispose() = EventQueue.invokeLater {
        icon?.let { runCatching { SystemTray.getSystemTray().remove(it) } }
        icon = null
    }

    companion object {
        private const val NOTICE_CLICK_MS = 15_000L

        /** Значок нужного размера, с красной точкой в правом верхнем углу, если [dot]. */
        fun render(source: Image, width: Int, height: Int, dot: Boolean): BufferedImage {
            val w = width.coerceAtLeast(16)
            val h = height.coerceAtLeast(16)
            val out = BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB)
            val g = out.createGraphics()
            try {
                g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
                g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR)
                g.drawImage(source, 0, 0, w, h, null)
                if (dot) {
                    val d = (minOf(w, h) * 0.42).toInt().coerceAtLeast(6)
                    g.color = Color.WHITE
                    g.fillOval(w - d - 1, 0, d + 1, d + 1)
                    g.color = Color(0xE5, 0x39, 0x35)
                    g.fillOval(w - d, 1, d - 1, d - 1)
                }
            } finally {
                g.dispose()
            }
            return out
        }
    }
}
