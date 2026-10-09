package app.maxly.presentation.chat

/**
 * Кнопка «вниз»: только когда самого нового сообщения (элемент 0 перевёрнутой ленты) не видно
 * совсем. У низа ленты её нет, поэтому последний пузырь она не закрывает.
 */
object ScrollDown {
    fun isVisible(visibleIndices: List<Int>, totalItems: Int): Boolean = totalItems > 0 && visibleIndices.isNotEmpty() && 0 !in visibleIndices
}
