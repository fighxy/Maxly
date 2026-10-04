package app.orbitle.presentation.profile

import app.orbitle.MainDispatcherRule
import app.orbitle.data.ProfileRepository
import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.ChatProfile
import app.orbitle.domain.FileContent
import app.orbitle.domain.Message
import app.orbitle.domain.MessageContent
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.PhotoContent
import app.orbitle.domain.SharedMediaTab
import app.orbitle.domain.TextSpan
import app.orbitle.domain.VideoContent
import app.orbitle.domain.VoiceContent
import app.orbitle.presentation.chat.FakeMessages
import app.orbitle.presentation.common.PresenceText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

private class FakeProfiles : ProfileRepository {
    var cachedProfile: ChatProfile? = null
    var fresh: ChatProfile? = ChatProfile(ChatProfile.Kind.USER, "10", "Анна", phone = "79001234567", isOnline = true)
    var failure: Exception? = null
    val pages = mutableMapOf<SharedMediaTab, MutableList<List<Message>>>()
    val requests = mutableListOf<Pair<SharedMediaTab, String>>()

    override fun cached(chatId: String) = cachedProfile
    override suspend fun profile(chatId: String): ChatProfile {
        failure?.let { throw it }
        return fresh!!
    }
    override suspend fun sharedPage(chatId: String, tab: SharedMediaTab, beforeMessageId: String): List<Message> {
        requests += tab to beforeMessageId
        return pages[tab]?.removeFirstOrNull() ?: emptyList()
    }
}

class ProfileViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val repo = FakeMessages()
    private val profiles = FakeProfiles()
    private val now = 1_790_683_200_000L
    private fun vm(title: String? = "Анна", pauseMs: Long = 0) =
        ProfileViewModel("10", title, profiles, repo, now = { now }, presence = PresenceText(ZoneOffset.UTC), sharedPauseMs = pauseMs)

    private fun msg(id: String, at: Long, text: String = "", vararg attachments: ChatAttachment, spans: List<TextSpan> = emptyList()) =
        Message(id, "10", "2", text, at, content = MessageContent(attachments = attachments.toList(), formatting = spans), authorName = "Анна")

    @Test
    fun headerShowsCachedThenFreshProfile() {
        profiles.cachedProfile = ChatProfile(ChatProfile.Kind.USER, "10", "Анна С.")
        val model = vm()
        val state = model.state.value
        assertEquals("Анна", state.title)
        assertEquals("в сети", state.subtitle)
        assertTrue(state.subtitleAccent)
        assertFalse(state.isLoading)
        assertEquals(listOf("phone"), state.rows.map { it.id })
        assertEquals("+7 900 123-45-67", state.rows.single().value)
        assertEquals(InfoRow.Action.Call("tel:+79001234567"), state.rows.single().action)
    }

    @Test
    fun failureKeepsKnownCard() {
        profiles.failure = OrbitleError.NetworkUnavailable
        val model = vm()
        assertEquals("Анна", model.state.value.title)
        assertNull(model.state.value.error)
    }

    @Test
    fun failureWithoutAnythingShowsError() {
        profiles.failure = OrbitleError.NetworkUnavailable
        val model = vm(title = null)
        assertEquals(OrbitleError.NetworkUnavailable.userMessage, model.state.value.error)
        assertEquals("Пользователь", model.state.value.title)
    }

    @Test
    fun channelAndGroupSubtitles() {
        profiles.fresh = ChatProfile(ChatProfile.Kind.CHANNEL, "10", "Новости", participants = 12500, link = "https://max.ru/news", description = "О главном")
        val channel = vm().state.value
        assertEquals("12\u202F500 подписчиков", channel.subtitle)
        assertEquals(listOf("description", "link"), channel.rows.map { it.id })
        assertEquals("max.ru/news", channel.rows.last().value)
        assertEquals("ссылка", channel.rows.last().title)
        assertEquals("описание", channel.rows.first().title)
        profiles.fresh = ChatProfile(ChatProfile.Kind.GROUP, "10", "Дача", participants = 3)
        assertEquals("3 участника", vm().state.value.subtitle)
        profiles.fresh = ChatProfile(ChatProfile.Kind.SAVED, "10")
        assertEquals("Избранное", vm(title = null).state.value.title)
    }

    @Test
    fun sharedMediaComesFromWindowAndServerPages() {
        repo.list.value = listOf(
            msg("1", 1_000, "", ChatAttachment.Photo(PhotoContent("p1", "u1"))),
            msg("2", 2_000, "см. https://github.com/x и всё"),
        )
        profiles.pages[SharedMediaTab.MEDIA] = mutableListOf(listOf(msg("0", 500, "", ChatAttachment.Video(VideoContent("v0", null, durationMs = 42_000)))))
        profiles.pages[SharedMediaTab.FILES] = mutableListOf(listOf(msg("-1", 400, "", ChatAttachment.File(FileContent("f", "отчёт.pdf", 2048)))))
        val model = vm()
        val shared = model.state.value.shared
        assertEquals(listOf("p1", "v0"), shared.media.map { it.attachment.id })
        assertEquals("0:42", shared.media.last().duration)
        assertEquals("PDF", shared.files.single().ext)
        assertEquals("github.com", shared.links.single().host)
        assertEquals(listOf(SharedMediaTab.MEDIA, SharedMediaTab.FILES, SharedMediaTab.LINKS), shared.tabs)
        // Первая страница каждой вкладки — от последнего сообщения окна.
        assertTrue(profiles.requests.all { it.second == "2" })
        // Следующая — от самого старого полученного.
        model.loadMore(SharedMediaTab.MEDIA)
        assertEquals(SharedMediaTab.MEDIA to "0", profiles.requests.last())
        // Пустая страница закрывает вкладку.
        val count = profiles.requests.size
        model.loadMore(SharedMediaTab.MEDIA)
        assertEquals(count, profiles.requests.size)
    }

    @Test
    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    fun sharedPagesGoOneByOneWithPause() {
        repo.list.value = listOf(msg("1", 1_000, "", ChatAttachment.Photo(PhotoContent("p1", "u1"))))
        vm(pauseMs = 400)
        // Сначала только первая вкладка: остальные ждут паузу, а не уходят разом.
        assertEquals(listOf(SharedMediaTab.MEDIA), profiles.requests.map { it.first })
        main.dispatcher.scheduler.advanceTimeBy(401)
        assertEquals(listOf(SharedMediaTab.MEDIA, SharedMediaTab.FILES), profiles.requests.map { it.first })
        main.dispatcher.scheduler.advanceUntilIdle()
        assertEquals(SharedMediaTab.entries.toList(), profiles.requests.map { it.first })
    }

    @Test
    fun firstNonEmptyTabIsSelected() {
        repo.list.value = listOf(msg("1", 1_000, "", ChatAttachment.Voice(VoiceContent("a", "u", durationMs = 5_000))))
        val model = vm()
        assertEquals(SharedMediaTab.VOICE, model.state.value.tab)
        assertEquals("Анна", model.state.value.shared.voices.single().author)
    }

    @Test
    fun linksFromSpansAndTrailingPunctuation() {
        val shared = SharedMedia.collect(
            listOf(
                msg("1", 1, "ссылка", spans = listOf(TextSpan(TextSpan.Kind.LINK, 0, 6, url = "https://www.max.ru/a"))),
                msg("2", 2, "https://example.org/path."),
            ),
            currentUserId = "1",
            zone = ZoneOffset.UTC,
        )
        assertEquals(listOf("example.org", "max.ru"), shared.links.map { it.host })
        assertEquals("https://example.org/path", shared.links.first().url)
        assertNull(shared.links.first().context)
        assertEquals("ссылка", shared.links.last().context)
    }

    @Test
    fun extensionRules() {
        assertEquals("ZIP", SharedMedia.extension("a.zip"))
        assertEquals("", SharedMedia.extension("README"))
        assertEquals("", SharedMedia.extension("a.verylongext"))
    }
}
