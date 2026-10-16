package app.maxly.presentation.chatlist

/**
 * Меню папки над списком чатов (долгое нажатие на вкладку, на компьютере — правая кнопка).
 * «Все»: «Настроить папки», «Прочитать все» (есть непрочитанные), «Изменить порядок». Своя папка: «Настроить папку»,
 * «Добавить чаты», «Прочитать все» (есть непрочитанные), «Выкл. уведомления» / «Вкл.
 * уведомления», «Удалить», «Изменить порядок». Порядок — только когда своих папок больше одной.
 */
object FolderTabMenu {
    sealed interface Entry {
        val title: String
        val isDanger: Boolean get() = false
        /** Перед пунктом разделитель: «Изменить порядок» отделён от остальных. */
        val separated: Boolean get() = false

        /** «Все»: экран папок целиком. */
        data object EditFolders : Entry {
            override val title get() = "Настроить папки"
        }
        /** Название и чаты этой папки. */
        data object EditFolder : Entry {
            override val title get() = "Настроить папку"
        }
        data object AddChats : Entry {
            override val title get() = "Добавить чаты"
        }
        data object ReadAll : Entry {
            override val title get() = "Прочитать все"
        }
        /** [muted] — у всех чатов папки звук уже выключен: пункт его включает. */
        data class Mute(val muted: Boolean) : Entry {
            override val title get() = if (muted) "Вкл. уведомления" else "Выкл. уведомления"
        }
        data object Delete : Entry {
            override val title get() = "Удалить"
            override val isDanger get() = true
        }
        data object Reorder : Entry {
            override val title get() = "Изменить порядок"
            override val separated get() = true
        }
    }

    /**
     * Пункты для вкладки. [editable] — папка с сервера и её можно менять (локальные вкладки-фильтры
     * нельзя). [folderCount] — сколько своих папок, кроме «Все».
     */
    fun entries(
        isAll: Boolean,
        editable: Boolean,
        hasUnread: Boolean,
        allMuted: Boolean,
        hasChats: Boolean,
        folderCount: Int,
    ): List<Entry> {
        val reorder = if (folderCount > 1) listOf(Entry.Reorder) else emptyList()
        if (isAll) {
            return buildList {
                if (editable) add(Entry.EditFolders)
                if (hasUnread) add(Entry.ReadAll)
                if (editable) addAll(reorder)
            }
        }
        return buildList {
            if (editable) {
                add(Entry.EditFolder)
                add(Entry.AddChats)
            }
            if (hasUnread) add(Entry.ReadAll)
            if (hasChats) add(Entry.Mute(allMuted))
            if (editable) {
                add(Entry.Delete)
                addAll(reorder)
            }
        }
    }
}
