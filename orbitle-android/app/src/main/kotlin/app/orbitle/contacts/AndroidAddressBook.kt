package app.orbitle.contacts

import android.content.Context
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.provider.ContactsContract.CommonDataKinds.StructuredName
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
        val names = structuredNames()
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
                val id = cursor.getLong(contactId)
                val key = cursor.getString(lookup)?.takeIf { it.isNotBlank() } ?: id.toString()
                val structured = names[id]
                rows += PhoneBookRow(
                    entryId = key,
                    displayName = cursor.getString(name),
                    number = cursor.getString(number),
                    systemNumber = cursor.getString(normalized),
                    givenName = structured?.first,
                    familyName = structured?.second,
                )
            }
        }
        PhoneBook.entries(rows)
    }

    /** Имя и фамилия записей (`StructuredName`) по `CONTACT_ID`; первая непустая строка записи. */
    private fun structuredNames(): Map<Long, Pair<String?, String?>> {
        val names = HashMap<Long, Pair<String?, String?>>()
        context.contentResolver.query(
            ContactsContract.Data.CONTENT_URI,
            arrayOf(StructuredName.CONTACT_ID, StructuredName.GIVEN_NAME, StructuredName.FAMILY_NAME),
            "${ContactsContract.Data.MIMETYPE} = ?",
            arrayOf(StructuredName.CONTENT_ITEM_TYPE),
            null,
        )?.use { cursor ->
            val contactId = cursor.getColumnIndexOrThrow(StructuredName.CONTACT_ID)
            val given = cursor.getColumnIndexOrThrow(StructuredName.GIVEN_NAME)
            val family = cursor.getColumnIndexOrThrow(StructuredName.FAMILY_NAME)
            while (cursor.moveToNext()) {
                val first = cursor.getString(given)?.trim()?.takeIf { it.isNotEmpty() }
                val last = cursor.getString(family)?.trim()?.takeIf { it.isNotEmpty() }
                if (first == null && last == null) continue
                names.putIfAbsent(cursor.getLong(contactId), first to last)
            }
        }
        return names
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
