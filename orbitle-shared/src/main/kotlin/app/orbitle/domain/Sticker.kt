package app.orbitle.domain

/** Стикер каталога сервера. */
data class Sticker(
    val id: String,
    val url: String,
    val lottieUrl: String? = null,
    val setId: String? = null,
    val width: Int? = null,
    val height: Int? = null,
)

/** Набор стикеров: обложка и стикеры по порядку. */
data class StickerSet(val id: String, val name: String, val iconUrl: String?, val stickerIds: List<String>)

/** Каталог панели: недавние стикеры сервера и наборы (свои первыми). */
data class StickerCatalog(val recentIds: List<String> = emptyList(), val sets: List<StickerSet> = emptyList())
