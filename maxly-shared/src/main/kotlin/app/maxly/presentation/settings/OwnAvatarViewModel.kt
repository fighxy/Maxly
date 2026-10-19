package app.maxly.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.maxly.data.AccountRepository
import app.maxly.data.CoreErrors
import app.maxly.data.MessageRepository
import app.maxly.domain.Account
import app.maxly.presentation.chat.ChatMedia
import app.maxly.presentation.chat.MediaSaver
import app.maxly.presentation.chat.MessageFiles
import app.maxly.presentation.media.AvatarPhoto
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first

/**
 * Своё фото профиля на весь экран из настроек и сохранение его в полном качестве.
 *
 * Адреса те же, что у чужих профилей: сначала оригинал (`avatarFullUrl` ядра), затем
 * `avatarViewerUrls` от большего к меньшему. Квадрат шапки ([Account.avatarUrl]) виден только
 * пока грузится кадр и не растягивается вместо оригинала. Протухший или не загрузившийся адрес —
 * свой профиль перечитывается один раз.
 */
class OwnAvatarViewModel(
    private val repository: AccountRepository,
    messages: MessageRepository,
    files: MessageFiles?,
    /** Куда сохранить фото; `null` — без «Сохранить». */
    saver: MediaSaver? = null,
    private val now: () -> Long = System::currentTimeMillis,
) : ViewModel() {

    private val _notice = MutableStateFlow<String?>(null)
    val notice: StateFlow<String?> = _notice.asStateFlow()

    val media = ChatMedia(
        chatId = "",
        repository = messages,
        scope = viewModelScope,
        player = null,
        files = files,
        saver = saver,
        onNotice = { _notice.value = it },
        now = now,
        onError = { _notice.value = CoreErrors.text(it) },
    )

    /** У [account] есть фото, которое можно открыть: касание аватара откроет просмотр. */
    fun canOpen(account: Account?): Boolean = account != null && frame(account, null) != null

    /** id кадра своего фото в просмотре; `null` — фото нет. */
    fun photoId(account: Account?): String? = account?.takeIf(::canOpen)?.let { AvatarPhoto.photoId(it.id) }

    /**
     * Открыть своё фото [account] на весь экран. [preview] — квадрат, который шапка уже показала.
     * Без фото ничего не открывается.
     */
    fun open(account: Account?, preview: String? = null) {
        val me = account ?: return
        val current = frame(me, preview) ?: return
        media.openAvatar(me.id, listOf(current), me.displayName, refresh = {
            repository.reload()
            listOfNotNull(repository.account.first()?.takeIf { it.id == me.id }?.let { frame(it, null) })
        })
    }

    /** «Сохранить фото как…» без просмотра: в выбранный [file]. */
    fun saveAs(account: Account?, file: String) {
        val me = account ?: return
        val current = frame(me, null) ?: return
        media.saveAvatar(AvatarPhoto.viewer(me.id, listOf(current), me.displayName), file)
    }

    /** Имя, которое «Сохранить как…» предлагает для своего фото. */
    fun fileName(account: Account?): String = AvatarPhoto.fileName(account?.displayName.orEmpty(), now(), "jpg")

    fun consumeNotice() {
        _notice.value = null
    }

    fun notify(text: String) {
        _notice.value = text
    }

    private fun frame(account: Account, preview: String?): AvatarPhoto.Frame? =
        AvatarPhoto.current(account.id, account.avatarFullUrl, account.avatarViewerUrls, preview)
}
