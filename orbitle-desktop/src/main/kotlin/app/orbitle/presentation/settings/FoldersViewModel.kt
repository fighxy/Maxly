package app.orbitle.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.orbitle.data.CoreErrors
import app.orbitle.data.FolderRepository
import app.orbitle.domain.ServerFolder
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** «Папки с чатами»: серверные папки, их чаты, порядок и удаление. «Все» не редактируется. */
class FoldersViewModel(private val repository: FolderRepository) : ViewModel() {

    data class State(
        /** «Все» первой, остальные в порядке сервера; `null`, пока не загружены. */
        val folders: List<ServerFolder>? = null,
        val working: Boolean = false,
        val error: String? = null,
    ) {
        val editable: List<ServerFolder> get() = folders?.filterNot { it.isAllChats }.orEmpty()

        /** Каких папок по типам ещё нет (сравнение по названию). */
        val missingTypeFolders: List<Pair<String, List<String>>>
            get() {
                if (folders == null) return emptyList()
                val existing = editable.map { it.title.lowercase() }.toSet()
                return TYPE_FOLDERS.filter { it.first.lowercase() !in existing }
            }
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            repository.folders.collect { list -> if (list != null) _state.update { it.copy(folders = ordered(list)) } }
        }
        viewModelScope.launch {
            try {
                repository.reload()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (_state.value.folders == null) {
                    _state.update { it.copy(folders = emptyList(), error = "Не удалось загрузить папки. ${message(e)}") }
                }
            }
        }
    }

    fun dismissError() = _state.update { it.copy(error = null) }

    fun create(title: String, chatIds: List<String>) {
        val name = title.trim()
        if (name.isEmpty()) return
        work("Не удалось создать папку") { repository.create(name, chatIds, emptyList()) }
    }

    /** «Личные», «Каналы» и «Боты» по фильтрам сервера, которых ещё нет. */
    fun addTypeFolders() {
        val missing = _state.value.missingTypeFolders
        if (missing.isEmpty()) return
        work("Не удалось создать папки") { missing.forEach { (title, filters) -> repository.create(title, emptyList(), filters) } }
    }

    fun rename(folder: ServerFolder, title: String) {
        val name = title.trim()
        if (folder.isAllChats || name.isEmpty() || name == folder.title) return
        work("Не удалось переименовать папку") { repository.rename(folder.id, name) }
    }

    fun setChats(folder: ServerFolder, chatIds: List<String>) {
        if (folder.isAllChats || chatIds.toSet() == folder.chatIds.toSet()) return
        work("Не удалось сохранить чаты папки") { repository.setChats(folder.id, chatIds) }
    }

    fun delete(folder: ServerFolder) {
        if (folder.isAllChats) return
        val before = _state.value.folders
        _state.update { s -> s.copy(folders = s.folders?.filterNot { it.id == folder.id }) }
        work("Не удалось удалить папку", restoring = before) { repository.delete(folder.id) }
    }

    /** Сдвигает папку на [offset] позиций среди редактируемых (действия TalkBack «выше»/«ниже»). */
    fun move(folder: ServerFolder, offset: Int) {
        val ids = _state.value.editable.map { it.id }
        val from = ids.indexOf(folder.id)
        if (from < 0) return
        reorder(FolderOrder.moved(ids, from, from + offset))
    }

    /**
     * Папку отпустили после перетаскивания: [editableIds] — новый порядок папок кроме «Все».
     * Тот же порядок ничего не отправляет; иначе сервер получает весь порядок с «Все» первой,
     * а при отказе возвращается прежний. Порядок, не совпадающий с текущим набором папок, отбрасывается.
     */
    fun reorder(editableIds: List<String>) {
        val current = _state.value.folders ?: return
        val pinned = current.filter { it.isAllChats }
        val rest = current.filterNot { it.isAllChats }
        val restIds = rest.map { it.id }
        if (editableIds == restIds || !FolderOrder.isPermutation(editableIds, restIds)) return
        val byId = rest.associateBy { it.id }
        val next = pinned + editableIds.map(byId::getValue)
        _state.update { it.copy(folders = next) }
        work("Не удалось изменить порядок папок", restoring = current) { repository.reorder(next.map { it.id }) }
    }

    private fun work(failure: String, restoring: List<ServerFolder>? = null, body: suspend () -> Unit) {
        _state.update { it.copy(working = true) }
        viewModelScope.launch {
            try {
                body()
                _state.update { it.copy(working = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { s -> s.copy(working = false, folders = restoring ?: s.folders, error = "$failure. ${message(e)}") }
            }
        }
    }

    private fun message(e: Throwable): String = CoreErrors.map(e).userMessage ?: "Что-то пошло не так"

    companion object {
        /** Папки по типам чатов: фильтры сервера (4 — диалоги, 2 — каналы, 10 — боты). */
        val TYPE_FOLDERS = listOf("Личные" to listOf("4"), "Каналы" to listOf("2"), "Боты" to listOf("10"))

        fun ordered(list: List<ServerFolder>): List<ServerFolder> = list.filter { it.isAllChats } + list.filterNot { it.isAllChats }
    }
}
