package app.orbitle.domain

/**
 * Пароль для входа (двухэтапная проверка). Пустые почта и подсказка сюда не попадают:
 * их отбрасывает [of].
 */
data class TwoFactorStatus(
    val isEnabled: Boolean,
    /** Почта для восстановления. `null`, если не указана. */
    val email: String? = null,
    val hint: String? = null,
) {
    companion object {
        fun of(isEnabled: Boolean, email: String? = null, hint: String? = null) = TwoFactorStatus(
            isEnabled = isEnabled,
            email = email?.takeIf { it.isNotEmpty() },
            hint = hint?.takeIf { it.isNotEmpty() },
        )

        /**
         * `i•••n@ya.ru`: первая и последняя буква имени, домен целиком.
         * Короткое имя (одна или две буквы) — первая буква и точки. Без `@` строка как есть.
         */
        fun mask(email: String): String {
            val parts = email.split('@', limit = 2)
            val name = parts[0]
            if (parts.size != 2 || name.isEmpty()) return email
            val masked = if (name.length <= 2) "${name.first()}•••" else "${name.first()}•••${name.last()}"
            return "$masked@${parts[1]}"
        }
    }
}
