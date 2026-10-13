package app.maxly.presentation.chatlist

import app.maxly.domain.ChatType

/**
 * Меню строки списка чатов — как в Max, один порядок на всех платформах:
 * «Добавить в папку ›», «Закрепить», «Отметить непрочитанным», «Отключить уведомления ›»
 * (на час, 4 часа, день, навсегда), «Стереть переписку», «Скрыть истории автора»,
 * «Заблокировать», «Удалить чат». Экран рисует [entries] по порядку, красным — [Entry.isDanger].
 */
object ChatListMenu {
    /** На сколько выключить уведомления. */
    enum class MuteFor(val title: String, private val durationMs: Long) {
        HOUR("На 1 час", 3_600_000L),
        FOUR_HOURS("На 4 часа", 4 * 3_600_000L),
        DAY("На 1 день", 86_400_000L),
        FOREVER("Навсегда", -1L),
        ;

        /** `dontDisturbUntil`: конец в мс от [nowMs] или `-1` насовсем. */
        fun until(nowMs: Long): Long = if (durationMs < 0) -1L else nowMs + durationMs

        val isDanger: Boolean get() = this == FOREVER
    }

    /** Папка в подменю «Добавить в папку»: [contains] — чат в ней уже есть (галочка, повтор — убрать). */
    data class FolderChoice(val id: String, val title: String, val contains: Boolean)

    sealed interface Entry {
        val title: String
        val isDanger: Boolean get() = false

        data class Folders(val folders: List<FolderChoice>) : Entry {
            override val title get() = "Добавить в папку"
        }
        data class Pin(val pinned: Boolean) : Entry {
            override val title get() = if (pinned) "Открепить" else "Закрепить"
        }
        /** Только на компьютере: закреплённые меняются местами. */
        data object ReorderPins : Entry {
            override val title get() = "Изменить порядок"
        }
        data class Read(val unread: Boolean) : Entry {
            override val title get() = if (unread) "Отметить прочитанным" else "Отметить непрочитанным"
        }
        /** Выключенные уведомления — один пункт «Включить», иначе подменю сроков. */
        data class Mute(val muted: Boolean) : Entry {
            override val title get() = if (muted) "Включить уведомления" else "Отключить уведомления"
            val choices: List<MuteFor> get() = if (muted) emptyList() else MuteFor.entries
        }
        data object Erase : Entry {
            override val title get() = "Стереть переписку"
        }
        data object HideStories : Entry {
            override val title get() = "Скрыть истории автора"
        }
        data object Block : Entry {
            override val title get() = "Заблокировать"
            override val isDanger get() = true
        }
        /** Что именно удаляется (у себя, у всех, выход из группы), спрашивает окно подтверждения. */
        data object Delete : Entry {
            override val title get() = "Удалить чат"
            override val isDanger get() = true
        }
    }

    /**
     * Пункты меню строки [item]. [folders] — папки пользователя (пусто — пункта нет),
     * [hasStories] — у автора чата есть истории в ленте, [savedMessages] — «Избранное»
     * (его не блокируют и не скрывают), [canReorderPins] — список «Все» без поиска (компьютер).
     */
    fun entries(
        item: ChatListItem,
        folders: List<FolderChoice>,
        hasStories: Boolean = false,
        savedMessages: Boolean = false,
        canReorderPins: Boolean = false,
        canMarkUnread: Boolean = true,
    ): List<Entry> = buildList {
        if (folders.isNotEmpty()) add(Entry.Folders(folders))
        add(Entry.Pin(item.isPinned))
        if (canReorderPins && item.isPinned) add(Entry.ReorderPins)
        if (item.isUnread || canMarkUnread) add(Entry.Read(item.isUnread))
        add(Entry.Mute(item.isMuted))
        add(Entry.Erase)
        if (hasStories && !savedMessages) add(Entry.HideStories)
        if (item.type == ChatType.PRIVATE && item.peerId != null && !savedMessages) add(Entry.Block)
        add(Entry.Delete)
    }

    /** Папки для подменю: чат в папке, если он добавлен в неё явно. */
    fun folderChoices(chatId: String, folders: List<app.maxly.domain.ServerFolder>): List<FolderChoice> =
        folders.filterNot { it.isAllChats }.map { FolderChoice(it.id, it.title, chatId in it.chatIds) }

    /** Состав папки после выбора [chatId] в подменю: был — убирается, не было — добавляется. */
    fun toggled(folder: app.maxly.domain.ServerFolder, chatId: String): List<String> =
        if (chatId in folder.chatIds) folder.chatIds - chatId else folder.chatIds + chatId
}
