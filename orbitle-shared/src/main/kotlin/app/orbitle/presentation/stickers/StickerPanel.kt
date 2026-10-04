package app.orbitle.presentation.stickers

import app.orbitle.data.RecentStickerStore
import app.orbitle.data.StickerRepository
import app.orbitle.domain.AnimatedEmoji
import app.orbitle.domain.Sticker
import app.orbitle.domain.StickerCatalog
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Категория обычных эмодзи Unicode. */
data class EmojiCategory(val id: String, val title: String, val emoji: List<String>)

/** Раздел панели стикеров: недавние или набор. */
data class StickerSection(val id: String, val title: String, val iconUrl: String?, val stickerIds: List<String>)

data class StickerPanelState(
    val mode: Mode = Mode.EMOJI,
    val emoji: List<EmojiCategory> = emptyList(),
    /** Анимодзи сервера: раздел «Анимированные» сразу после недавних. */
    val animated: List<AnimatedEmoji> = emptyList(),
    val sections: List<StickerSection> = emptyList(),
    val stickers: Map<String, Sticker> = emptyMap(),
    val isLoading: Boolean = false,
    val failure: String? = null,
) {
    enum class Mode { EMOJI, STICKERS }
}

/** Ячейка сетки эмодзи. `animated` задан у анимодзи сервера, в том числе в «Недавних». */
data class EmojiPick(val key: String, val glyph: String, val animated: AnimatedEmoji?)

/** Раздел сетки эмодзи. */
data class EmojiTab(val id: String, val title: String, val picks: List<EmojiPick>)

/**
 * Порядок панели: «Недавние», затем «Анимированные», затем категории Unicode.
 * Ключ `animoji:` в недавних показывается эмодзи каталога. Неизвестный id скрыт.
 */
fun emojiTabs(state: StickerPanelState): List<EmojiTab> {
    val animatedById = state.animated.associateBy { it.id }
    val tabs = ArrayList<EmojiTab>()
    val recent = state.emoji.firstOrNull { it.id == "recent" }
    if (recent != null) {
        val picks = recent.emoji.mapNotNull { token ->
            if (token.startsWith(StickerPanel.ANIMOJI_PREFIX)) {
                val item = animatedById[token.removePrefix(StickerPanel.ANIMOJI_PREFIX)] ?: return@mapNotNull null
                EmojiPick("recent:a${item.id}", item.emoji, item)
            } else {
                EmojiPick("recent:$token", token, null)
            }
        }
        if (picks.isNotEmpty()) tabs += EmojiTab("recent", recent.title, picks)
    }
    if (state.animated.isNotEmpty()) {
        tabs += EmojiTab(
            "animated",
            StickerPanel.ANIMATED_TITLE,
            state.animated.map { EmojiPick("animated:${it.id}", it.emoji, it) },
        )
    }
    state.emoji.filter { it.id != "recent" }.forEach { category ->
        tabs += EmojiTab(category.id, category.title, category.emoji.map { EmojiPick("${category.id}:$it", it, null) })
    }
    return tabs
}

/**
 * Панель эмодзи и стикеров под полем ввода. Эмодзи: «Недавние», если ими пользовались,
 * затем «Анимированные» (анимодзи сервера), затем категории Unicode.
 * Стикеры: недавние, затем наборы (свои первыми).
 * Каталог сервера грузится один раз при первом открытии, стикеры раздела — когда он виден.
 */
class StickerPanel(
    private val repository: StickerRepository?,
    private val recents: RecentStickerStore,
    private val scope: CoroutineScope,
    /** Эмодзи, которые шрифт устройства умеет рисовать. */
    private val supported: (String) -> Boolean = { true },
) {
    private val _state = MutableStateFlow(StickerPanelState())
    val state: StateFlow<StickerPanelState> = _state.asStateFlow()

    private var catalog = StickerCatalog()
    private var loaded = false
    private val requested = mutableSetOf<String>()
    private val categories by lazy {
        EmojiData.categories.map { it.copy(emoji = it.emoji.filter(supported)) }.filter { it.emoji.isNotEmpty() }
    }

    fun prepare() {
        rebuildEmoji()
        recents.recentStickers.forEach { sticker -> _state.update { it.copy(stickers = it.stickers + (sticker.id to sticker)) } }
        rebuildStickers()
        if (loaded || repository == null) return
        loaded = true
        _state.update { it.copy(isLoading = true, failure = null) }
        scope.launch {
            try {
                val fresh = repository.animatedEmoji()
                if (fresh.isNotEmpty()) _state.update { it.copy(animated = fresh) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Раздел анимодзи необязателен: обычные эмодзи остаются.
            }
            try {
                catalog = repository.catalog()
                rebuildStickers()
                _state.value.sections.firstOrNull()?.let { load(it) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                loaded = false
                _state.update { it.copy(failure = "Не удалось загрузить стикеры") }
            } finally {
                _state.update { it.copy(isLoading = false) }
            }
        }
    }

    fun setMode(mode: StickerPanelState.Mode) = _state.update { it.copy(mode = mode) }

    /** Раздел стал виден: догрузить его стикеры. */
    fun load(section: StickerSection) {
        val repository = repository ?: return
        val missing = section.stickerIds.filter { it !in _state.value.stickers && it !in requested }
        if (missing.isEmpty()) return
        requested += missing
        scope.launch {
            try {
                val stickers = repository.stickers(missing)
                _state.update { it.copy(stickers = it.stickers + stickers.associateBy { s -> s.id }) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                requested -= missing.toSet()
            }
        }
    }

    /** Эмодзи ушёл в поле: встаёт первым в «Недавних». */
    fun usedEmoji(emoji: String) {
        recents.recentEmoji = (listOf(emoji) + recents.recentEmoji.filter { it != emoji }).take(RECENT_EMOJI)
        rebuildEmoji()
    }

    /** Анимодзи ушёл в поле: в недавних хранится ключ `animoji:` и id, не сам символ. */
    fun usedAnimated(emoji: AnimatedEmoji) {
        val key = ANIMOJI_PREFIX + emoji.id
        recents.recentEmoji = (listOf(key) + recents.recentEmoji.filter { it != key }).take(RECENT_EMOJI)
        rebuildEmoji()
    }

    fun usedSticker(sticker: Sticker) {
        recents.recentStickers = (listOf(sticker) + recents.recentStickers.filter { it.id != sticker.id }).take(RECENT_STICKERS)
        rebuildStickers()
    }

    private fun rebuildEmoji() {
        val recent = recents.recentEmoji.take(RECENT_EMOJI_SHOWN)
        val sections = if (recent.isEmpty()) categories else listOf(EmojiCategory("recent", RECENT_TITLE, recent)) + categories
        _state.update { it.copy(emoji = sections) }
    }

    private fun rebuildStickers() {
        val local = recents.recentStickers.map { it.id }
        val recent = (local + catalog.recentIds).distinct().take(RECENT_STICKERS)
        val sections = buildList {
            if (recent.isNotEmpty()) add(StickerSection("recent", RECENT_TITLE, null, recent))
            catalog.sets.filter { it.stickerIds.isNotEmpty() }.forEach { add(StickerSection(it.id, it.name, it.iconUrl, it.stickerIds)) }
        }
        _state.update { it.copy(sections = sections) }
    }

    companion object {
        const val RECENT_TITLE = "Недавние"
        const val ANIMATED_TITLE = "Анимированные"
        const val ANIMOJI_PREFIX = "animoji:"
        const val RECENT_EMOJI = 40
        const val RECENT_EMOJI_SHOWN = 24
        const val RECENT_STICKERS = 20
    }
}
