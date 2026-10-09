package app.maxly.presentation.chatlist

import app.maxly.data.PreferenceStore

/** Недавние чаты из поиска. Это не переписка: выход стирает список вместе с остальными данными. */
interface RecentSearchStore {
    /** Сначала последний выбранный. */
    fun recent(): List<String>
    fun add(chatId: String)
    fun remove(chatId: String)
    fun clear()
}

/** Порядок и предел списка. Хранится строкой: один id на строку. */
object RecentSearchList {
    const val LIMIT = 20

    fun decode(raw: String?): List<String> =
        raw?.lineSequence()?.map { it.trim() }?.filter { it.isNotEmpty() }?.distinct()?.take(LIMIT)?.toList().orEmpty()

    fun encode(ids: List<String>): String = ids.take(LIMIT).joinToString("\n")

    fun add(current: List<String>, chatId: String): List<String> {
        val id = chatId.trim()
        if (id.isEmpty()) return current
        return (listOf(id) + current.filter { it != id }).take(LIMIT)
    }

    fun remove(current: List<String>, chatId: String): List<String> = current.filter { it != chatId }
}

/** Тот же файл настроек, что у черновиков. Ключ один: выход очищает его. */
class PreferenceRecentSearches(
    private val store: PreferenceStore,
    private val key: String = KEY,
) : RecentSearchStore {
    override fun recent(): List<String> = RecentSearchList.decode(store.get(key))

    override fun add(chatId: String) {
        store.put(key, RecentSearchList.encode(RecentSearchList.add(recent(), chatId)))
    }

    override fun remove(chatId: String) {
        store.put(key, RecentSearchList.encode(RecentSearchList.remove(recent(), chatId)))
    }

    override fun clear() {
        store.put(key, "")
    }

    companion object {
        const val KEY = "orbitle.recentSearches"
    }
}
