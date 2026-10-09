package app.maxly.domain

/** Как приватный режим прячет переписку. */
enum class PrivateModeStyle(val title: String) {
    /** Вместо текста общая подпись — основной вид. */
    PLACEHOLDER("Заглушки"),
    /** Настоящий текст, но размытый: выдаёт длину и форму. */
    BLUR("Размытие"),
}

/** Настройка приватного режима на устройстве: в протокол не уходит. */
data class PrivateModePreferences(
    val enabled: Boolean = false,
    val style: PrivateModeStyle = PrivateModeStyle.PLACEHOLDER,
    /** Плавающая кнопка с глазом над списком чатов. */
    val quickToggle: Boolean = true,
)

/** Что видно на конкретном экране. Настройки и профиль всегда [VISIBLE]. */
enum class PrivateModeDisplay { VISIBLE, PLACEHOLDER, BLUR }
