package app.maxly.presentation.profile

import app.maxly.MainDispatcherRule
import app.maxly.data.PeerPresence
import app.maxly.data.ProfileRepository
import app.maxly.domain.ChatAttachment
import app.maxly.domain.ChatProfile
import app.maxly.domain.FileContent
import app.maxly.domain.Message
import app.maxly.domain.MessageContent
import app.maxly.domain.OrbitleError
import app.maxly.domain.PhotoContent
import app.maxly.domain.SharedMediaTab
import app.maxly.domain.TextSpan
import app.maxly.domain.VideoContent
import app.maxly.domain.VoiceContent
import app.maxly.presentation.chat.FakeMessages
import app.maxly.presentation.common.PresenceText
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestDispatcher
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
    val presence = MutableStateFlow<PeerPresence?>(null)
    val watched = mutableListOf<String>()

    override fun cached(chatId: String) = cachedProfile
    override suspend fun profile(chatId: String): ChatProfile {
        failure?.let { throw it }
        return fresh!!
    }
    override suspend fun sharedPage(chatId: String, tab: SharedMediaTab, beforeMessageId: String): List<Message> {
        requests += tab to beforeMessageId
        return pages[tab]?.removeFirstOrNull() ?: emptyList()
    }
    override fun presence(peerId: String): MutableStateFlow<PeerPresence?> {
        watched += peerId
        return presence
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
    fun unknownPresenceHasNoSubtitle() {
        profiles.fresh = ChatProfile(ChatProfile.Kind.USER, "10", "Анна", peerId = "10")
        val model = vm()
        assertEquals("", model.state.value.subtitle)
        assertFalse(model.state.value.subtitleAccent)
    }

    @Test
    fun openProfileFollowsStorePresence() {
        profiles.fresh = ChatProfile(ChatProfile.Kind.USER, "10", "Анна", peerId = "10", isOnline = true)
        val model = vm()
        assertEquals(listOf("10"), profiles.watched)
        assertEquals("в сети", model.state.value.subtitle)
        profiles.presence.value = PeerPresence(isOnline = false, lastSeenMs = now - 5 * 60_000)
        assertEquals("был(а) 5 минут назад", model.state.value.subtitle)
        assertFalse(model.state.value.subtitleAccent)
        assertEquals(now - 5 * 60_000, model.state.value.profile.lastSeenMs)
        // Записи нет — известное не стирается.
        profiles.presence.value = null
        assertEquals("был(а) 5 минут назад", model.state.value.subtitle)
        profiles.presence.value = PeerPresence(isOnline = true, lastSeenMs = now)
        assertEquals("в сети", model.state.value.subtitle)
        assertTrue(model.state.value.subtitleAccent)
        assertEquals(listOf("10"), profiles.watched)
    }

    @Test
    fun profilePresenceAgesOnItsOwn() {
        val scheduler = (main.dispatcher as TestDispatcher).scheduler
        profiles.fresh = ChatProfile(ChatProfile.Kind.USER, "10", "Анна", peerId = "10", lastSeenMs = now - 30_000)
        val model = ProfileViewModel("10", "Анна", profiles, repo, now = { now + scheduler.currentTime }, presence = PresenceText(ZoneOffset.UTC))
        assertEquals("был(а) только что", model.state.value.subtitle)
        scheduler.advanceTimeBy(31_000)
        assertEquals("был(а) 1 минуту назад", model.state.value.subtitle)
        scheduler.advanceTimeBy(60 * 60_000)
        assertEquals("был(а) в 11:59", model.state.value.subtitle)
    }

    @Test
    fun groupProfileDoesNotWatchPresence() {
        profiles.fresh = ChatProfile(ChatProfile.Kind.GROUP, "10", "Команда", participants = 3)
        vm()
        assertTrue(profiles.watched.isEmpty())
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

/** Чёрный список для профиля: остальное не используется. */
private class BlockAccount : app.maxly.data.AccountRepository {
    override val account = kotlinx.coroutines.flow.MutableStateFlow<app.maxly.domain.Account?>(null)
    override val settings = kotlinx.coroutines.flow.MutableStateFlow(app.maxly.domain.AccountSettings())
    val blocked = mutableSetOf<String>()

    override suspend fun reload() = Unit
    override suspend fun updateProfile(firstName: String, lastName: String, about: String) = Unit
    override suspend fun uploadAvatar(jpeg: ByteArray) = Unit
    override suspend fun removeAvatar() = Unit
    override suspend fun requestDeletion(): Long? = null
    override suspend fun change(change: app.maxly.domain.PrivacyChange) = settings.value
    override suspend fun blockedUsers() = blocked.map { app.maxly.domain.BlockedUser(it, "Кто-то", null, null) }
    override suspend fun unblock(userId: String) { blocked -= userId }
    override suspend fun block(userId: String) { blocked += userId }
    override suspend fun twoFactorStatus() = app.maxly.domain.TwoFactorStatus(false)
    override suspend fun startEmailChange(password: String) = "track"
    override suspend fun sendEmailCode(trackId: String, email: String) = 60
    override suspend fun confirmEmail(trackId: String, code: String) = app.maxly.domain.TwoFactorStatus(true)
    override suspend fun launchMiniApp(kind: app.maxly.domain.MiniApp.Kind): app.maxly.domain.MiniApp = throw app.maxly.domain.OrbitleError.InvalidRequest
    override suspend fun miniAppCallback(url: String): app.maxly.domain.MiniApp = throw app.maxly.domain.OrbitleError.InvalidRequest
}

class ProfileBlockingTest {
    @get:Rule val main = MainDispatcherRule()

    @Test
    fun blockAndUnblockThePerson() {
        val profiles = FakeProfiles()
        profiles.fresh = ChatProfile(ChatProfile.Kind.USER, "10", "Анна", peerId = "7")
        val account = BlockAccount()
        val model = ProfileViewModel("10", "Анна", profiles, FakeMessages(), account = account)
        assertEquals(false, model.state.value.blocked)
        model.toggleBlocked()
        assertEquals(true, model.state.value.blocked)
        assertEquals(setOf("7"), account.blocked)
        assertEquals("Пользователь заблокирован", model.notice.value)
        model.toggleBlocked()
        assertEquals(false, model.state.value.blocked)
        assertTrue(account.blocked.isEmpty())
    }

    @Test
    fun noBlockingForChannels() {
        val profiles = FakeProfiles()
        profiles.fresh = ChatProfile(ChatProfile.Kind.CHANNEL, "-10", "Новости")
        val model = ProfileViewModel("-10", "Новости", profiles, FakeMessages(), account = BlockAccount())
        assertNull(model.state.value.blocked)
    }
}
