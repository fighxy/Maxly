package app.maxly.presentation.settings

import app.maxly.MainDispatcherRule
import app.maxly.data.AccountRepository
import app.maxly.data.CoreAccountRepository
import app.maxly.domain.Account
import app.maxly.domain.AccountSettings
import app.maxly.domain.BlockedUser
import app.maxly.domain.ChatAttachment
import app.maxly.domain.MiniApp
import app.maxly.domain.PrivacyChange
import app.maxly.domain.TwoFactorStatus
import app.maxly.presentation.chat.FakeMessages
import app.maxly.presentation.chat.MediaSaver
import app.maxly.presentation.chat.MessageFiles
import app.maxly.presentation.chat.SavedKind
import app.maxly.presentation.media.AvatarPhoto
import com.maxly.core.api.MaxUser
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class OwnAvatarViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private class Me(initial: Account?) : AccountRepository {
        val me = MutableStateFlow(initial)
        var reloads = 0
        var fresh: Account? = null
        override val account = me
        override val settings = MutableStateFlow(AccountSettings(known = true))
        override suspend fun reload() {
            reloads++
            fresh?.let { me.value = it }
        }
        override suspend fun updateProfile(firstName: String, lastName: String, about: String) = Unit
        override suspend fun uploadAvatar(jpeg: ByteArray) = Unit
        override suspend fun removeAvatar() = Unit
        override suspend fun requestDeletion(): Long? = null
        override suspend fun change(change: PrivacyChange): AccountSettings = settings.value
        override suspend fun blockedUsers(): List<BlockedUser> = emptyList()
        override suspend fun unblock(userId: String) = Unit
        override suspend fun twoFactorStatus(): TwoFactorStatus = TwoFactorStatus(false)
        override suspend fun startEmailChange(password: String): String = "track"
        override suspend fun sendEmailCode(trackId: String, email: String): Int = 60
        override suspend fun confirmEmail(trackId: String, code: String): TwoFactorStatus = TwoFactorStatus(true)
        override suspend fun launchMiniApp(kind: MiniApp.Kind): MiniApp = MiniApp(1, "https://max.ru")
        override suspend fun miniAppCallback(url: String): MiniApp = MiniApp(1, "https://max.ru")
    }

    private class Files : MessageFiles {
        val urls = mutableListOf<String>()
        val broken = mutableSetOf<String>()
        override fun cached(fileId: String, name: String): String? = null
        override suspend fun download(url: String, fileId: String, name: String, progress: (Float) -> Unit): String {
            urls += url
            if (url in broken) throw java.io.IOException("404")
            return "/nonexistent/$fileId/$name"
        }
    }

    private class Saver : MediaSaver {
        val pictures = mutableListOf<String>()
        override suspend fun savePicture(path: String, name: String) {
            pictures += name
        }
        override suspend fun save(path: String, name: String, kind: SavedKind, directory: String?) = Unit
    }

    private val thumb = "https://i.oneme.ru/i?r=b&fn=sqr_288"
    private val raw = "https://i.oneme.ru/i?r=raw"
    private val user = MaxUser.from(mapOf("id" to 5L, "names" to listOf(mapOf("firstName" to "Иван", "lastName" to "Петров")), "baseUrl" to thumb, "baseRawUrl" to raw, "photoId" to 77L))!!
    private val time = java.time.LocalDateTime.of(2026, 10, 19, 21, 30, 0).atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
    private val files = Files()
    private val saver = Saver()

    private fun model(repo: AccountRepository) = OwnAvatarViewModel(repo, FakeMessages(), files, saver, now = { time })

    @Test
    fun ownAccountCarriesTheCoreFullAndViewerUrls() {
        val account = CoreAccountRepository.accountOf(5L, user)
        assertEquals(thumb, account.avatarUrl)
        assertEquals(user.avatarFullUrl, account.avatarFullUrl)
        assertEquals(raw, account.avatarFullUrl)
        assertEquals(user.avatarViewerUrls, account.avatarViewerUrls)
        assertTrue(account.avatarViewerUrls.first().endsWith("fn=w_1440"))
        val none = CoreAccountRepository.accountOf(6L, MaxUser.from(mapOf("id" to 6L))!!)
        assertNull(none.avatarFullUrl)
        assertTrue(none.avatarViewerUrls.isEmpty())
    }

    @Test
    fun opensTheOriginalThenSizesFromLargestNeverTheSquare() {
        val account = CoreAccountRepository.accountOf(5L, user)
        val model = model(Me(account))
        assertTrue(model.canOpen(account))
        assertEquals(AvatarPhoto.photoId("5"), model.photoId(account))
        files.broken += raw
        model.open(account, preview = thumb)
        val viewer = model.media.state.value.viewer!!
        assertTrue(AvatarPhoto.isAvatar(viewer))
        val id = AvatarPhoto.photoId("5")
        assertEquals(listOf(raw) + user.avatarViewerUrls, viewer.fallbacks[id])
        assertFalse(thumb in viewer.fallbacks[id]!!)
        assertEquals(thumb, viewer.previews[id])
        // Оригинал не загрузился: следующим берётся самый большой размер, а не квадрат.
        assertEquals(listOf(raw, user.avatarViewerUrls.first()), files.urls)
        val shown = (viewer.items.single() as ChatAttachment.Photo).photo.url!!
        assertTrue(shown.startsWith("file:"))
        assertTrue(shown.contains(AvatarPhoto.cacheId("5", user.avatarViewerUrls.first())))
    }

    @Test
    fun savesTheShownFullPhoto() {
        val account = CoreAccountRepository.accountOf(5L, user)
        val model = model(Me(account))
        model.open(account)
        assertTrue(model.media.canSaveAvatar())
        model.media.saveAvatar()
        assertEquals(listOf(raw), files.urls)
        assertEquals(listOf("Фото профиля — Иван Петров 2026-10-19 21.30.00.jpg"), saver.pictures)
        assertEquals(AvatarPhoto.SAVED, model.notice.value)
    }

    @Test
    fun failingUrlsRereadOwnProfileOnce() {
        val account = CoreAccountRepository.accountOf(5L, user)
        val repo = Me(account)
        val newRaw = "https://i.oneme.ru/i?r=raw2"
        repo.fresh = account.copy(avatarFullUrl = newRaw, avatarViewerUrls = emptyList())
        files.broken += listOf(raw) + user.avatarViewerUrls
        val model = model(repo)
        model.open(account)
        assertEquals(1, repo.reloads)
        assertEquals(newRaw, files.urls.last())
        assertTrue((model.media.state.value.viewer!!.items.single() as ChatAttachment.Photo).photo.url!!.startsWith("file:"))
    }

    @Test
    fun noPhotoNoViewer() {
        val account = Account("5", "Иван", "", null, null)
        val model = model(Me(account))
        assertFalse(model.canOpen(account))
        assertNull(model.photoId(account))
        model.open(account)
        assertNull(model.media.state.value.viewer)
        // Только квадрат без полей ядра: в просмотр он не растягивается.
        val squareOnly = account.copy(avatarUrl = thumb)
        assertFalse(model.canOpen(squareOnly))
    }
}
