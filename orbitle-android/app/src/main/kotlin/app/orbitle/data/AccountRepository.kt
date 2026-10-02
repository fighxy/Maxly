package app.orbitle.data

import app.orbitle.domain.Account
import com.max.shared.MaxClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** Свой профиль. */
interface AccountRepository {
    val account: Flow<Account?>
    suspend fun reload()
}

class CoreAccountRepository(private val client: MaxClient) : AccountRepository {
    override val account: Flow<Account?> = client.store.state.map { state ->
        val me = state.me ?: return@map null
        val user = state.users[me] ?: return@map Account(me.toString(), "", "", null, null)
        val name = user.names.firstOrNull()
        Account(
            id = me.toString(),
            firstName = name?.firstName?.takeIf { it.isNotBlank() } ?: name?.name.orEmpty(),
            lastName = name?.lastName.orEmpty(),
            phone = user.phone?.let { "+$it" },
            avatarUrl = user.baseUrl?.takeIf { it.isNotBlank() },
            description = user.description?.trim()?.takeIf { it.isNotEmpty() },
            link = user.link?.takeIf { it.isNotBlank() },
        )
    }.distinctUntilChanged()

    override suspend fun reload() {
        MaxCoreGateway.call { client.loadMe() }
    }
}
