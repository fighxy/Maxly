package app.orbitle.data

import app.orbitle.domain.StorageCategory
import app.orbitle.domain.StorageUsage

/** Кэш приложения: размер по категориям и очистка. Сообщения и вход не трогаются. */
interface StorageRepository {
    suspend fun usage(): StorageUsage
    suspend fun clear(categories: Set<StorageCategory>)
}
