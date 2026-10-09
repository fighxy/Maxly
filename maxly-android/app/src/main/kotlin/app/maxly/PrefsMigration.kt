package app.maxly

import android.content.Context
import android.content.SharedPreferences
import app.maxly.data.CoreStoreMigration

/**
 * Файлы `SharedPreferences` после переименования Orbitle → Maxly. Первые сборки с
 * `app.maxly.android` ещё писали вход ядра в `max_kmp_orbitle` (ключи `max.orbitle.*`), а настройки
 * — в `orbitle`, `orbitle.chat`, `orbitle.diagnostics`. При первом запуске новой сборки всё это
 * переезжает в файлы `maxly*`, чтобы не пришлось входить заново. Перенос пропускается, если
 * новый файл уже не пуст или старого нет; старый очищается и удаляется только после того, как
 * новый записан.
 */
internal object PrefsMigration {
    const val LEGACY_CORE_NAMESPACE = "orbitle"
    const val CORE_NAMESPACE = "maxly"

    fun run(context: Context) {
        move(context, "max_kmp_$LEGACY_CORE_NAMESPACE", "max_kmp_$CORE_NAMESPACE") { entries ->
            val strings = entries.filterValues { it is String }.mapValues { it.value as String }
            CoreStoreMigration.rekey(strings, LEGACY_CORE_NAMESPACE, CORE_NAMESPACE)
        }
        move(context, "orbitle", "maxly")
        move(context, "orbitle.chat", "maxly.chat")
        move(context, "orbitle.diagnostics", "maxly.diagnostics")
    }

    private fun move(
        context: Context,
        from: String,
        to: String,
        transform: (Map<String, *>) -> Map<String, *> = { it },
    ) {
        runCatching {
            val source = context.getSharedPreferences(from, Context.MODE_PRIVATE)
            val target = context.getSharedPreferences(to, Context.MODE_PRIVATE)
            val entries = source.all
            if (entries.isEmpty() || target.all.isNotEmpty()) return@runCatching
            val editor = target.edit()
            transform(entries).forEach { (key, value) -> editor.putAny(key, value) }
            if (!editor.commit()) return@runCatching
            if (source.edit().clear().commit()) context.deleteSharedPreferences(from)
        }.onFailure { app.maxly.data.diagnostics.AppLog.w("prefs", "Перенос $from → $to не удался", it) }
    }

    @Suppress("UNCHECKED_CAST")
    private fun SharedPreferences.Editor.putAny(key: String, value: Any?) {
        when (value) {
            is String -> putString(key, value)
            is Long -> putLong(key, value)
            is Int -> putInt(key, value)
            is Boolean -> putBoolean(key, value)
            is Float -> putFloat(key, value)
            is Set<*> -> putStringSet(key, value as Set<String>)
        }
    }
}
