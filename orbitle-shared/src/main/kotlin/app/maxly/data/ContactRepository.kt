package app.maxly.data

import app.maxly.domain.Contact
import com.maxly.core.api.MaxUser
import com.maxly.core.api.UserName
import com.maxly.core.events.MaxEvent
import com.maxly.core.protocol.Opcode
import com.maxly.core.state.MaxState
import com.maxly.shared.MaxClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.map

/** Контакты аккаунта из стора ядра. */
interface ContactRepository {
    val contacts: Flow<List<Contact>>
    suspend fun sync()

    /**
     * Человек по номеру (`CONTACT_INFO_BY_PHONE` 46, телефон `+` и цифры).
     * `null` — не найден. В контакты сам по себе не добавляет.
     */
    suspend fun findByPhone(phone: String): Contact? = null

    /** Уже известный пользователь в контакты (`CONTACT_UPDATE` 34, `action: ADD`). */
    suspend fun add(userId: String): Contact? = null

    /**
     * То же, но с именем, если оно непустое. Пустое имя — это [add] без `firstName`.
     */
    suspend fun add(userId: String, firstName: String): Contact? = add(userId)

    /** Своё имя контакта, видное только этому аккаунту (`CUSTOM`). Пустая фамилия — без неё. */
    suspend fun rename(userId: String, firstName: String, lastName: String?): Contact? = null

    /** Убрать из контактов. `false` — не вышло или не поддерживается. */
    suspend fun remove(userId: String): Boolean = false

    /** В контакты по номеру, с именем, если оно задано. `null` — не поддерживается. */
    suspend fun addByPhone(phone: String, firstName: String?, lastName: String?): AddedContact? = null

    /** Контакты, изменённые на другом устройстве (пуш `NOTIF_CONTACT`). */
    val changes: Flow<Contact> get() = emptyFlow()

    companion object {
        /** Короче форма на iOS не отправляет запрос. */
        const val MIN_PHONE_DIGITS = 7
    }
}

/** Контакт после добавления по номеру; [isNew] — раньше его в списке не было. */
data class AddedContact(val contact: Contact, val isNew: Boolean)

class CoreContactRepository(private val client: MaxClient) : ContactRepository {
    override val contacts: Flow<List<Contact>> = client.store.state
        .map { state ->
            state.contactIds.mapNotNull { id ->
                val user = state.users[id] ?: return@mapNotNull null
                // Удалённый аккаунт (`accountStatus != 0`) в список не попадает. Пустого поля нет — человек жив.
                if (!isListed(user)) return@mapNotNull null
                contact(user, state)
            }
        }
        .distinctUntilChanged()

    override suspend fun sync() {
        // Ядро шлёт opcode 8 `{contactsSync: 0}` и добавляет ответ к уже известным id.
        // Список дописывается, а не заменяется целиком.
        MaxCoreGateway.call { client.syncContacts() }
    }

    override suspend fun findByPhone(phone: String): Contact? {
        val digits = phone.filter { it.isDigit() }
        if (digits.length < ContactRepository.MIN_PHONE_DIGITS) return null
        val user = MaxCoreGateway.call { client.api.users.findByPhone("+$digits") }
        client.store.putUsers(listOf(user))
        return contact(user, client.store.state.value)
    }

    override suspend fun add(userId: String): Contact? = add(userId, "")

    override suspend fun rename(userId: String, firstName: String, lastName: String?): Contact? {
        val id = userId.toLongOrNull() ?: return null
        val user = MaxCoreGateway.call { client.renameContact(id, firstName, lastName) }
        return contact(user, client.store.state.value)
    }

    override suspend fun remove(userId: String): Boolean {
        val id = userId.toLongOrNull() ?: return false
        MaxCoreGateway.call { client.removeContact(id) }
        return true
    }

    override suspend fun addByPhone(phone: String, firstName: String?, lastName: String?): AddedContact? {
        val added = MaxCoreGateway.call { client.addContactByPhone(phone, firstName, lastName) }
        return AddedContact(contact(added.user, client.store.state.value), added.isNew)
    }

    // Пуш стор ядра применяет сам; здесь — чтобы открытые экраны обновили имя.
    override val changes: Flow<Contact> = client.events.of<MaxEvent.ContactUpdated>()
        .map { contact(it.user, client.store.state.value) }

    override suspend fun add(userId: String, firstName: String): Contact? {
        val id = userId.toLongOrNull() ?: return null
        val name = firstName.trim()
        val user = if (name.isEmpty()) {
            MaxCoreGateway.call { client.api.users.addContact(id) }
        } else {
            val packet = MaxCoreGateway.call {
                client.session.request(Opcode.CONTACT_UPDATE, LockPayloads.addContact(id, name))
            }
            MaxUser.from((packet.payload as? Map<*, *>)?.get("contact")) ?: return null
        }
        client.store.putContacts(listOf(user))
        return contact(user, client.store.state.value)
    }

    companion object {
        /** Удалённый аккаунт в список не входит. Нет `accountStatus` — аккаунт жив. */
        fun isListed(user: MaxUser): Boolean = (user.accountStatus ?: 0) == 0

        /**
         * Имя для списка: запись `CUSTOM`, иначе `ONEME`, иначе первая.
         * Берутся `firstName` и `lastName`. Если оба пусты, остаётся поле `name`.
         */
        fun visibleName(names: List<UserName>): Pair<String, String> {
            val chosen = names.firstOrNull { it.type == "CUSTOM" }
                ?: names.firstOrNull { it.type == "ONEME" }
                ?: names.firstOrNull()
                ?: return "" to ""
            val first = chosen.firstName?.trim().orEmpty()
            val last = chosen.lastName?.trim().orEmpty()
            if (first.isNotEmpty() || last.isNotEmpty()) return first to last
            return chosen.name?.trim().orEmpty() to ""
        }

        fun contact(user: MaxUser, state: MaxState): Contact {
            val (first, last) = visibleName(user.names)
            val presence = state.presence[user.id]
            return Contact(
                id = user.id.toString(),
                firstName = first,
                lastName = last,
                label = state.displayName(user.id),
                phone = user.phone?.toString().orEmpty(),
                avatarUrl = user.baseUrl?.takeIf { it.isNotBlank() },
                isOnline = PresenceTime.isOnline(presence),
                lastSeenMs = PresenceTime.ms(presence?.seen),
                presence = PresenceTime.status(presence),
                isBot = "BOT" in user.options,
                isOfficial = "OFFICIAL" in user.options,
                isServiceAccount = "SERVICE_ACCOUNT" in user.options,
            )
        }
    }
}
