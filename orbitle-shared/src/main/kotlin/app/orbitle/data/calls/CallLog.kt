package app.orbitle.data.calls

/** Журнал звонков. Приложение подключает свой вывод (logcat, консоль). */
object CallLog {
    @Volatile
    var sink: (level: Char, message: String) -> Unit = { _, _ -> }

    fun info(message: String) = sink('I', message)

    fun warning(message: String) = sink('W', message)
}
