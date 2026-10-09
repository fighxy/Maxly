package app.maxly.platform

import app.maxly.data.AddressBook
import app.maxly.domain.PhoneBookEntry

/** На компьютере телефонной книги нет. */
object DesktopAddressBook : AddressBook {
    override val isAvailable: Boolean = false

    override suspend fun entries(): List<PhoneBookEntry> = emptyList()
}
