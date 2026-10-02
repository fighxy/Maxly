package app.orbitle.data

import app.orbitle.domain.Contact
import com.max.core.api.MaxUser
import com.max.core.state.MaxState
import com.max.shared.MaxClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** Контакты аккаунта из стора ядра. */
interface ContactRepository {
    val contacts: Flow<List<Contact>>
    suspend fun sync()
}

class CoreContactRepository(private val client: MaxClient) : ContactRepository {
    override val contacts: Flow<List<Contact>> = client.store.state
        .map { state -> state.contactIds.mapNotNull { id -> state.users[id]?.let { contact(it, state) } } }
        .distinctUntilChanged()

    override suspend fun sync() {
        MaxCoreGateway.call { client.syncContacts() }
    }

    companion object {
        fun contact(user: MaxUser, state: MaxState): Contact {
            val name = user.names.firstOrNull()
            val first = name?.firstName?.takeIf { it.isNotBlank() } ?: name?.name.orEmpty()
            val presence = state.presence[user.id]
            return Contact(
                id = user.id.toString(),
                firstName = first,
                lastName = name?.lastName.orEmpty(),
                phone = user.phone?.toString().orEmpty(),
                avatarUrl = user.baseUrl?.takeIf { it.isNotBlank() },
                isOnline = presence?.status == 1,
                lastSeenMs = presence?.seen?.let { if (it < 100_000_000_000L) it * 1000 else it } ?: 0L,
            )
        }
    }
}
