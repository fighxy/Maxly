package app.maxly.presentation.profile

import app.maxly.domain.ChatProfile
import app.maxly.presentation.chatlist.ChatListMenu

/**
 * Плитки под шапкой профиля и меню «Ещё» — как в Max.
 *
 * - Человек: «Чат», «Звонок», «Видео», «Звук», «Ещё» → «Поделиться контактом», «Добавить в
 *   папку ›», «Найти», «Стереть переписку», «Скрыть истории автора», «Заблокировать», «Удалить чат».
 * - Группа: «Звонок», «Видео» (если звонки в группах есть), «Звук», «Найти», «Ещё» →
 *   «Добавить в папку ›», «Стереть переписку», «Участники и жалоба», «Покинуть группу»,
 *   «Удалить группу» (владельцу) или «Удалить чат».
 * - Канал: «Звук», «Ещё» → «Добавить в папку ›», «Найти», «Стереть переписку», «Пожаловаться»
 *   (не админу), «Отписаться от канала», «Удалить канал» (владельцу).
 * - Группа или канал не из списка (открыты из поиска): «Вступить» / «Подписаться» и «Ещё».
 *
 * Красным — [Entry.isDanger].
 */
object ProfileMenu {
    enum class Tile(val title: String) {
        CHAT("Чат"),
        CALL("Звонок"),
        VIDEO("Видео"),
        SOUND("Звук"),
        SEARCH("Найти"),
        JOIN("Вступить"),
        SUBSCRIBE("Подписаться"),
        MORE("Ещё"),
    }

    sealed interface Entry {
        val title: String
        val isDanger: Boolean get() = false

        data object ShareContact : Entry {
            override val title get() = "Поделиться контактом"
        }
        data object ShareLink : Entry {
            override val title get() = "Поделиться ссылкой"
        }
        /** Подменю папок; в конце — «Создать папку». */
        data class Folders(val folders: List<ChatListMenu.FolderChoice>) : Entry {
            override val title get() = "Добавить в папку"
        }
        data object Search : Entry {
            override val title get() = "Найти"
        }
        data object Erase : Entry {
            override val title get() = "Стереть переписку"
        }
        data object HideStories : Entry {
            override val title get() = "Скрыть истории автора"
        }
        /** Участники, общие чаты и жалоба — один лист. */
        data class Tools(val channel: Boolean) : Entry {
            override val title get() = if (channel) "Пожаловаться" else "Участники и жалоба"
        }
        data class Block(val blocked: Boolean) : Entry {
            override val title get() = if (blocked) "Разблокировать" else "Заблокировать"
            override val isDanger get() = !blocked
        }
        data class Leave(val channel: Boolean) : Entry {
            override val title get() = if (channel) "Отписаться от канала" else "Покинуть группу"
            override val isDanger get() = true
        }
        data class Delete(val kind: ChatProfile.Kind, val owner: Boolean) : Entry {
            override val title get() = when {
                kind == ChatProfile.Kind.CHANNEL -> "Удалить канал"
                kind == ChatProfile.Kind.GROUP && owner -> "Удалить группу"
                else -> "Удалить чат"
            }
            override val isDanger get() = true
        }
    }

    /**
     * Плитки профиля [profile]. [listed] — чат в списке пользователя (иначе открыт из поиска),
     * [calls] — звонки собеседнику, [groupCalls] — звонки в группе, [canWrite] — «Чат» открывает
     * переписку.
     */
    fun tiles(
        profile: ChatProfile,
        listed: Boolean = true,
        calls: Boolean = true,
        groupCalls: Boolean = false,
        canWrite: Boolean = true,
    ): List<Tile> = buildList {
        when (profile.kind) {
            ChatProfile.Kind.USER -> {
                if (canWrite) add(Tile.CHAT)
                if (calls) addAll(listOf(Tile.CALL, Tile.VIDEO))
                add(Tile.SOUND)
            }
            ChatProfile.Kind.BOT -> {
                if (canWrite) add(Tile.CHAT)
                add(Tile.SOUND)
            }
            ChatProfile.Kind.SAVED -> {
                if (canWrite) add(Tile.CHAT)
                add(Tile.SEARCH)
            }
            ChatProfile.Kind.GROUP -> if (!listed) {
                add(Tile.JOIN)
            } else {
                if (groupCalls) addAll(listOf(Tile.CALL, Tile.VIDEO))
                addAll(listOf(Tile.SOUND, Tile.SEARCH))
            }
            ChatProfile.Kind.CHANNEL -> add(if (listed) Tile.SOUND else Tile.SUBSCRIBE)
        }
        add(Tile.MORE)
    }

    /**
     * Пункты «Ещё». [folders] — папки для подменю (`null` — менять их нечем), [hasStories] —
     * у владельца чата есть истории, [blocked] — собеседник в чёрном списке (`null` — неизвестно
     * или блокировать нельзя). «Найти» уходит в меню, если его нет среди [tiles].
     */
    fun entries(
        profile: ChatProfile,
        tiles: List<Tile>,
        listed: Boolean = true,
        folders: List<ChatListMenu.FolderChoice>? = null,
        hasStories: Boolean = false,
        blocked: Boolean? = null,
    ): List<Entry> = buildList {
        val kind = profile.kind
        val channel = kind == ChatProfile.Kind.CHANNEL
        if (!listed) {
            if (profile.link != null) add(Entry.ShareLink)
            add(Entry.Tools(channel))
            return@buildList
        }
        when (kind) {
            ChatProfile.Kind.USER -> add(Entry.ShareContact)
            ChatProfile.Kind.GROUP, ChatProfile.Kind.CHANNEL -> if (profile.link != null) add(Entry.ShareLink)
            else -> Unit
        }
        if (folders != null) add(Entry.Folders(folders))
        if (Tile.SEARCH !in tiles) add(Entry.Search)
        add(Entry.Erase)
        if (hasStories && kind != ChatProfile.Kind.SAVED) add(Entry.HideStories)
        when (kind) {
            ChatProfile.Kind.GROUP -> add(Entry.Tools(channel = false))
            ChatProfile.Kind.CHANNEL -> if (!profile.isAdmin) add(Entry.Tools(channel = true))
            else -> Unit
        }
        if (blocked != null && (kind == ChatProfile.Kind.USER || kind == ChatProfile.Kind.BOT)) add(Entry.Block(blocked))
        if (kind == ChatProfile.Kind.GROUP || channel) add(Entry.Leave(channel))
        if (!channel || profile.isOwner) add(Entry.Delete(kind, profile.isOwner))
    }
}
