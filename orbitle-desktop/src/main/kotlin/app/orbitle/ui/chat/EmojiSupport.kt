package app.orbitle.ui.chat

/** На компьютере эмодзи рисует системный шрифт (Segoe UI Emoji и аналоги). */
object EmojiSupport {
    fun canDraw(emoji: String): Boolean = emoji.isNotEmpty()
}
