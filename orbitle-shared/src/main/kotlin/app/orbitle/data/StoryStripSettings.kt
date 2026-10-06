package app.orbitle.data

/** Скрыта ли полоса историй. Хранится на устройстве, общее для аккаунтов. */
class StoryStripSettings(private val store: PreferenceStore) {
    fun isCollapsed(): Boolean = store.get(KEY) == "1"

    fun setCollapsed(collapsed: Boolean) {
        store.put(KEY, if (collapsed) "1" else "0")
    }

    companion object {
        const val KEY = "stories.stripCollapsed"
    }
}
