package app.maxly.presentation.settings

import java.io.File
import java.util.UUID
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Локальные ответы мини-приложения, которым не нужна команда сервера.
 *
 * Цифровой ID на старте спрашивает биометрию и потом кладёт токен и соль ПИН
 * в хранилище страницы. Оба живут на устройстве, отдельно для каждого бота.
 * [deviceId] сеанса страница отправляет на сервер: чужой идентификатор
 * сервер отвергает как `device_mismatch`.
 */
class MiniAppVault private constructor(private val file: File?) {
    data class Biometry(
        val accessRequested: Boolean = false,
        val accessGranted: Boolean = false,
        val token: String? = null,
    )

    private val lock = Any()
    private var root: JsonObject = read()

    fun biometry(botId: Long): Biometry = synchronized(lock) {
        val obj = botObject("biometry", botId) ?: return Biometry()
        Biometry(
            accessRequested = bool(obj, "accessRequested"),
            accessGranted = bool(obj, "accessGranted"),
            token = text(obj, "token"),
        )
    }

    fun saveBiometry(botId: Long, value: Biometry) = synchronized(lock) {
        val fields = linkedMapOf<String, kotlinx.serialization.json.JsonElement>(
            "accessRequested" to JsonPrimitive(value.accessRequested),
            "accessGranted" to JsonPrimitive(value.accessGranted),
        )
        if (!value.token.isNullOrEmpty()) fields["token"] = JsonPrimitive(value.token)
        putBot("biometry", botId, JsonObject(fields))
    }

    /** Пустая строка — уже сохранённый запасной идентификатор, один на файл. */
    fun deviceId(given: String): String = synchronized(lock) {
        if (given.isNotEmpty()) return given
        val existing = (root["deviceId"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotEmpty() }
        if (existing != null) return existing
        val created = UUID.randomUUID().toString().replace("-", "").take(16)
        root = JsonObject(root.toMutableMap().apply { put("deviceId", JsonPrimitive(created)) })
        write()
        created
    }

    fun get(space: String, botId: Long, key: String): String? = synchronized(lock) {
        text(botObject(space, botId) ?: return null, key)
    }

    /** `null` стирает ключ. */
    fun put(space: String, botId: Long, key: String, value: String?) = synchronized(lock) {
        val next = (botObject(space, botId)?.toMutableMap() ?: mutableMapOf())
        if (value == null) next.remove(key) else next[key] = JsonPrimitive(value)
        putBot(space, botId, JsonObject(next))
    }

    fun clear(space: String, botId: Long) = synchronized(lock) {
        putBot(space, botId, JsonObject(emptyMap()))
    }

    private fun botObject(space: String, botId: Long): JsonObject? =
        ((root[space] as? JsonObject)?.get(botId.toString()) as? JsonObject)

    private fun putBot(space: String, botId: Long, value: JsonObject) {
        val bots = ((root[space] as? JsonObject)?.toMutableMap() ?: mutableMapOf())
        bots[botId.toString()] = value
        root = JsonObject(root.toMutableMap().apply { put(space, JsonObject(bots)) })
        write()
    }

    private fun read(): JsonObject {
        val stored = file?.takeIf { it.isFile } ?: return JsonObject(emptyMap())
        return try {
            Json.parseToJsonElement(stored.readText()).jsonObject
        } catch (_: Exception) {
            JsonObject(emptyMap())
        }
    }

    private fun write() {
        val target = file ?: return
        runCatching {
            target.parentFile?.mkdirs()
            target.writeText(root.toString())
        }
    }

    private fun bool(obj: JsonObject, key: String): Boolean =
        (obj[key] as? JsonPrimitive)?.booleanOrNull ?: false

    private fun text(obj: JsonObject, key: String): String? {
        val value = obj[key] ?: return null
        if (value is JsonNull) return null
        val primitive = value as? JsonPrimitive ?: return null
        if (!primitive.isString) return null
        return primitive.content.takeIf { it.isNotEmpty() }
    }

    companion object {
        fun memory(): MiniAppVault = MiniAppVault(null)
        fun file(file: File): MiniAppVault = MiniAppVault(file)
    }
}
