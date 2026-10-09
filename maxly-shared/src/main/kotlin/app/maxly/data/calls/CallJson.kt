package app.maxly.data.calls

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/** Чтение JSON сервера звонков: поля бывают числом или строкой, объекта может не быть. */
internal operator fun JsonElement?.get(key: String): JsonElement? = (this as? JsonObject)?.get(key)

internal val JsonElement?.obj: JsonObject? get() = this as? JsonObject

internal val JsonElement?.arr: JsonArray? get() = this as? JsonArray

internal val JsonElement?.str: String?
    get() = (this as? JsonPrimitive)?.takeIf { it.isString }?.content

/** Целое; строка из цифр и дробное без дробной части — тоже, как сервер иногда шлёт id. */
internal val JsonElement?.long: Long?
    get() {
        val primitive = this as? JsonPrimitive ?: return null
        if (primitive is JsonNull) return null
        if (primitive.isString) return primitive.content.toLongOrNull()
        primitive.longOrNull?.let { return it }
        val double = primitive.doubleOrNull ?: return null
        return if (double == Math.rint(double) && Math.abs(double) < 9.0e15) double.toLong() else null
    }

internal val JsonElement?.bool: Boolean?
    get() = (this as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull

internal val JsonElement?.isNull: Boolean get() = this == null || this is JsonNull

/** Короткая запись объектов команд. */
internal fun json(vararg pairs: Pair<String, Any?>): JsonObject = JsonObject(pairs.associate { (key, value) -> key to element(value) })

internal fun element(value: Any?): JsonElement = when (value) {
    null -> JsonNull
    is JsonElement -> value
    is String -> JsonPrimitive(value)
    is Number -> JsonPrimitive(value)
    is Boolean -> JsonPrimitive(value)
    is Map<*, *> -> JsonObject(value.entries.associate { (key, item) -> key.toString() to element(item) })
    is List<*> -> JsonArray(value.map(::element))
    else -> error("не JSON: $value")
}
