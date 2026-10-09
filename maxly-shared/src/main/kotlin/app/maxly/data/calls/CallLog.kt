package app.maxly.data.calls

import app.maxly.data.diagnostics.AppLog

/**
 * Журнал звонков. По умолчанию строки идут в журнал приложения ([AppLog]) с меткой `calls`:
 * в файл, который можно отправить из «О приложении», и в системный журнал платформы.
 */
object CallLog {
    const val TAG = "calls"

    @Volatile
    var sink: (level: Char, message: String) -> Unit = { level, message ->
        if (level == 'W') AppLog.w(TAG, message) else AppLog.i(TAG, message)
    }

    fun info(message: String) = sink('I', message)

    fun warning(message: String) = sink('W', message)

    /** Ошибка со стеком: стек нужен в журнале, чтобы понять, где сломалось. */
    fun error(message: String, error: Throwable) {
        sink('W', "$message: $error")
        AppLog.file?.append('W', TAG, "↳ стек", error)
    }
}
