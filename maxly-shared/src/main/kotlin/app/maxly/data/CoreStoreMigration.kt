package app.maxly.data

/**
 * Перенос хранилища ядра на новое пространство имён после переименования Orbitle → Maxly.
 * Ядро (`MaxClient`) кладёт вход, сессию и флаги под ключи `max.<namespace>.*` в хранилище
 * этого же пространства (файл `<namespace>.properties` на ПК, `SharedPreferences`
 * `max_kmp_<namespace>` на Android). Ключи старого пространства переименовываются в новое,
 * остальные переносятся как есть.
 */
object CoreStoreMigration {
    /** Содержимое старого хранилища с ключами нового пространства. */
    fun rekey(entries: Map<String, String>, legacyNamespace: String, namespace: String): Map<String, String> {
        val legacyPrefix = "max.$legacyNamespace."
        val prefix = "max.$namespace."
        return entries.mapKeys { (key, _) ->
            if (key.startsWith(legacyPrefix)) prefix + key.removePrefix(legacyPrefix) else key
        }
    }
}
