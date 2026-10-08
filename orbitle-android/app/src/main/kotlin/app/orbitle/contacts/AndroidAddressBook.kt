package app.orbitle.contacts

import android.content.Context
import android.provider.ContactsContract.CommonDataKinds.Phone
import app.orbitle.data.AddressBook
import app.orbitle.domain.PhoneBook
import app.orbitle.domain.PhoneBookEntry
import app.orbitle.domain.PhoneBookRow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Телефонная книга через `ContactsContract`: номера всех записей одним запросом, сборка и
 * нормализация — в общем [PhoneBook]. Нужно разрешение `READ_CONTACTS`, без него система
 * бросает [SecurityException].
 */
class AndroidAddressBook(private val context: Context) : AddressBook {
    /** Книга контактов есть на любом телефоне; если её нет, чтение просто не удастся. */
    override val isAvailable: Boolean = true

    override suspend fun entries(): List<PhoneBookEntry> = withContext(Dispatchers.IO) {
        val rows = ArrayList<PhoneBookRow>()
        context.contentResolver.query(
            Phone.CONTENT_URI,
            PROJECTION,
            null,
            null,
            "${Phone.DISPLAY_NAME_PRIMARY} COLLATE LOCALIZED ASC",
        )?.use { cursor ->
            val lookup = cursor.getColumnIndexOrThrow(Phone.LOOKUP_KEY)
            val contactId = cursor.getColumnIndexOrThrow(Phone.CONTACT_ID)
            val name = cursor.getColumnIndexOrThrow(Phone.DISPLAY_NAME_PRIMARY)
            val number = cursor.getColumnIndexOrThrow(Phone.NUMBER)
            val normalized = cursor.getColumnIndexOrThrow(Phone.NORMALIZED_NUMBER)
            while (cursor.moveToNext()) {
                val key = cursor.getString(lookup)?.takeIf { it.isNotBlank() } ?: cursor.getLong(contactId).toString()
                rows += PhoneBookRow(
                    entryId = key,
                    displayName = cursor.getString(name),
                    number = cursor.getString(number),
                    systemNumber = cursor.getString(normalized),
                )
            }
        }
        PhoneBook.entries(rows)
    }

    private companion object {
        val PROJECTION = arrayOf(
            Phone.LOOKUP_KEY,
            Phone.CONTACT_ID,
            Phone.DISPLAY_NAME_PRIMARY,
            Phone.NUMBER,
            Phone.NORMALIZED_NUMBER,
        )
    }
}
