package app.orbitle.domain

import java.net.URI
import java.net.URLDecoder

/**
 * Запущенное мини-приложение MAX. [url] уже содержит данные запуска,
 * [queryId] сервер присылает не всегда.
 */
data class MiniApp(
    val botId: Long,
    val url: String,
    val queryId: String? = null,
) {
    val id: String get() = "$botId:$url"

    enum class Kind(val wire: String, val title: String) {
        SFERUM("sferum", "Сферум"),
        DIGITAL_ID("digitalId", "Цифровой ID"),
        ;

        companion object {
            fun fromWire(value: String?): Kind? = entries.firstOrNull { it.wire == value }
        }
    }

    companion object {
        private val WEB_SCHEMES = setOf("http", "https", "about", "data", "blob")

        /**
         * Адрес возврата внешнего шага (Госуслуги в Цифровом ID):
         * в запросе ровно `externalCallback=1`.
         */
        fun isExternalCallback(url: String): Boolean {
            val query = try {
                URI(url).rawQuery
            } catch (_: Exception) {
                null
            } ?: return false
            return query.split('&').any { part ->
                val name = decode(part.substringBefore('='))
                val value = decode(part.substringAfter('=', ""))
                name == "externalCallback" && value == "1"
            }
        }

        /** Схемы кроме http, https, about, data и blob открывает система, не страница. */
        fun opensExternally(url: String): Boolean {
            val scheme = url.substringBefore(':', missingDelimiterValue = "").lowercase()
            return scheme.isNotEmpty() && scheme !in WEB_SCHEMES
        }

        private fun decode(text: String): String = try {
            URLDecoder.decode(text, Charsets.UTF_8.name())
        } catch (_: Exception) {
            text
        }
    }
}
