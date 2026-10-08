package app.orbitle.platform

import app.orbitle.data.AddressBook
import app.orbitle.domain.PhoneBookEntry

/** На компьютере телефонной книги нет. */
object DesktopAddressBook : AddressBook {
    override val isAvailable: Boolean = false

    override suspend fun entries(): List<PhoneBookEntry> = emptyList()
}
