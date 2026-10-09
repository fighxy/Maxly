package app.maxly.data

import app.maxly.domain.ServerFolder
import com.max.shared.MaxClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** Папки чатов на сервере: список вместе с «Все», создание, правка, удаление, порядок. */
interface FolderRepository {
    /** `null`, пока папки не пришли с сервера. */
    val folders: Flow<List<ServerFolder>?>
    suspend fun reload()
    suspend fun create(title: String, chatIds: List<String>, filters: List<String>)
    suspend fun rename(folderId: String, title: String)
    suspend fun setChats(folderId: String, chatIds: List<String>)
    suspend fun delete(folderId: String)
    /** Полный список id в новом порядке. */
    suspend fun reorder(order: List<String>)
}

class CoreFolderRepository(private val client: MaxClient) : FolderRepository {
    override val folders: Flow<List<ServerFolder>?> = client.store.state
        .map { it.chatFolders }
        .distinctUntilChanged()
        .map { folders -> folders?.let(ChatMapping::folders) }

    override suspend fun reload() {
        MaxCoreGateway.call { client.loadFolders() }
    }

    override suspend fun create(title: String, chatIds: List<String>, filters: List<String>) {
        MaxCoreGateway.call { client.createFolder(title.trim(), ids(chatIds), filtersOf(filters)) }
    }

    override suspend fun rename(folderId: String, title: String) {
        MaxCoreGateway.call { client.editFolder(folderId, title = title.trim()) }
    }

    override suspend fun setChats(folderId: String, chatIds: List<String>) {
        MaxCoreGateway.call { client.editFolder(folderId, chatIds = ids(chatIds)) }
    }

    override suspend fun delete(folderId: String) {
        MaxCoreGateway.call { client.deleteFolders(listOf(folderId)) }
    }

    override suspend fun reorder(order: List<String>) {
        MaxCoreGateway.call { client.reorderFolders(order) }
    }

    private fun ids(chatIds: List<String>): List<Long> = chatIds.mapNotNull { it.toLongOrNull() }

    companion object {
        /** Коды фильтров сервера уходят числами, имена — строками. */
        fun filtersOf(filters: List<String>): List<Any?> =
            filters.map { it.trim() }.filter { it.isNotEmpty() }.map { it.toLongOrNull() ?: it }
    }
}
