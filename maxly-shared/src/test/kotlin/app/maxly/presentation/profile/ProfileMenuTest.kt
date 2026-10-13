package app.maxly.presentation.profile

import app.maxly.domain.ChatProfile
import app.maxly.presentation.chatlist.ChatListMenu
import app.maxly.presentation.profile.ProfileMenu.Entry
import app.maxly.presentation.profile.ProfileMenu.Tile
import org.junit.Assert.assertEquals
import org.junit.Test

class ProfileMenuTest {
    private val folders = listOf(ChatListMenu.FolderChoice("n", "Новые", false))

    private fun titles(profile: ChatProfile, listed: Boolean = true, hasStories: Boolean = false, blocked: Boolean? = null, groupCalls: Boolean = false): Pair<List<String>, List<String>> {
        val tiles = ProfileMenu.tiles(profile, listed, groupCalls = groupCalls)
        val entries = ProfileMenu.entries(profile, tiles, listed, folders, hasStories, blocked)
        return tiles.map { it.title } to entries.map { it.title }
    }

    @Test
    fun personLikeMax() {
        val (tiles, more) = titles(ChatProfile(ChatProfile.Kind.USER, "1"), hasStories = true, blocked = false)
        assertEquals(listOf("Чат", "Звонок", "Видео", "Звук", "Ещё"), tiles)
        assertEquals(
            listOf("Поделиться контактом", "Добавить в папку", "Найти", "Стереть переписку", "Скрыть истории автора", "Заблокировать", "Удалить чат"),
            more,
        )
    }

    @Test
    fun ownChannelLikeMax() {
        val (tiles, more) = titles(ChatProfile(ChatProfile.Kind.CHANNEL, "-1", isOwner = true, isAdmin = true))
        assertEquals(listOf("Звук", "Ещё"), tiles)
        assertEquals(listOf("Добавить в папку", "Найти", "Стереть переписку", "Отписаться от канала", "Удалить канал"), more)
    }

    @Test
    fun subscribedChannelCannotBeDeleted() {
        val (_, more) = titles(ChatProfile(ChatProfile.Kind.CHANNEL, "-1", link = "https://max.ru/c"))
        assertEquals(listOf("Поделиться ссылкой", "Добавить в папку", "Найти", "Стереть переписку", "Пожаловаться", "Отписаться от канала"), more)
    }

    @Test
    fun groupWithCalls() {
        val (tiles, more) = titles(ChatProfile(ChatProfile.Kind.GROUP, "-2", isOwner = true, isAdmin = true), groupCalls = true)
        assertEquals(listOf("Звонок", "Видео", "Звук", "Найти", "Ещё"), tiles)
        assertEquals(listOf("Добавить в папку", "Стереть переписку", "Участники и жалоба", "Покинуть группу", "Удалить группу"), more)
    }

    @Test
    fun notListedChannelOnlySubscribes() {
        val (tiles, more) = titles(ChatProfile(ChatProfile.Kind.CHANNEL, "-3", link = "https://max.ru/c"), listed = false)
        assertEquals(listOf("Подписаться", "Ещё"), tiles)
        assertEquals(listOf("Поделиться ссылкой", "Пожаловаться"), more)
    }

    @Test
    fun blockedBotUnblocks() {
        val profile = ChatProfile(ChatProfile.Kind.BOT, "5")
        val tiles = ProfileMenu.tiles(profile)
        assertEquals(listOf(Tile.CHAT, Tile.SOUND, Tile.MORE), tiles)
        val block = ProfileMenu.entries(profile, tiles, blocked = true).filterIsInstance<Entry.Block>().single()
        assertEquals("Разблокировать" to false, block.title to block.isDanger)
    }
}
