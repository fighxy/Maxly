package app.maxly.data

import app.maxly.domain.StorageCategory
import app.maxly.domain.StorageUsage

/** Кэш приложения: размер по категориям и очистка. Сообщения и вход не трогаются. */
interface StorageRepository {
    suspend fun usage(): StorageUsage
    suspend fun clear(categories: Set<StorageCategory>)
}
