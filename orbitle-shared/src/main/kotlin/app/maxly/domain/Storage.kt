package app.maxly.domain

/** Части кэша на устройстве. Всё это — копии из облака, после очистки они скачаются снова. */
enum class StorageCategory(val title: String, val subtitle: String) {
    PHOTOS("Фото и аватары", "Картинки из чатов и профилей"),
    FILES("Скачанные файлы", "Документы, видео и голосовые, открытые в приложении"),
    OUTGOING("Подготовленное к отправке", "Копии выбранных вложений"),
    OTHER("Прочее", "Временные файлы"),
}

/** Сколько байт занимает каждая категория. */
data class StorageUsage(val bytes: Map<StorageCategory, Long>) {
    val total: Long get() = bytes.values.sum()
    fun of(category: StorageCategory): Long = bytes[category] ?: 0L
}
