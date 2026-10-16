package app.maxly.domain

/** Когда гифки в чате играют сами. */
enum class GifAutoplay { ALWAYS, WIFI_ONLY, NEVER }

/** Настройки гифок: автовоспроизведение и поиск через gifka.me (по умолчанию выключен). */
data class GifPreferences(
    val autoplay: GifAutoplay = GifAutoplay.ALWAYS,
    val gifkaSearch: Boolean = false,
)

/** Вид медиа gifka.me. Сейчас в приложении только гифки; стикеры добавятся отдельной вкладкой. */
enum class GifkaType(val raw: String) { GIF("gif"), STICKER("sticker") }

/** Результат gifka.me: превью для сетки (MP4/WebP/постер) и ссылка на загрузку GIF в API. */
data class GifkaMedia(
    val id: String,
    val type: GifkaType,
    val title: String,
    val width: Int,
    val height: Int,
    val mp4Url: String?,
    val webpUrl: String?,
    val posterUrl: String?,
    val gifDownloadUrl: String?,
)

data class GifkaPage(val items: List<GifkaMedia>, val total: Int?)
