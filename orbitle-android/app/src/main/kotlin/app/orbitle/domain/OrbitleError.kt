package app.orbitle.domain

/**
 * Категории ошибок, которые видит UI. Слой данных переводит в них ошибки ядра и сервера.
 */
sealed class OrbitleError(message: String) : Exception(message) {
    /** Нет сети или соединение с сервером потеряно. */
    data object NetworkUnavailable : OrbitleError("Нет соединения с сервером")
    /** Сессия истекла, нужно войти заново. */
    data object AuthExpired : OrbitleError("Сессия истекла, войдите снова")
    /** Сервер вернул ошибку. */
    data class Server(val code: String) : OrbitleError("Ошибка сервера ($code). Попробуйте позже")
    /** Запрос отклонён как неверный. */
    data object InvalidRequest : OrbitleError("Сервер отклонил запрос")
    /** Пользовательский ввод отклонён. Текст можно показать как есть. */
    data class Rejected(val text: String) : OrbitleError(text)
    data object StorageError : OrbitleError("Не удалось сохранить данные на устройстве")
    data object SyncFailed : OrbitleError("Не удалось синхронизироваться с сервером")
    /** Действие отменено. Экран такую ошибку не показывает. */
    data object Cancelled : OrbitleError("Действие отменено")
    data object Unknown : OrbitleError("Что-то пошло не так")

    /** Текст для экрана. `null` у отмены: её пользователю не показывают. */
    val userMessage: String? get() = if (this == Cancelled) null else message

    /** Повтор того же действия позже может пройти без участия пользователя. */
    val isTransient: Boolean get() = this is NetworkUnavailable || this is Server || this is SyncFailed

    companion object {
        /** Код устарел, и сервис входа уже выслал новый. */
        val codeRenewed = Rejected("Код устарел — выслали новый")
    }
}
