package app.orbitle.presentation.settings

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull

/**
 * Мост между страницей мини-приложения и приложением.
 *
 * Страница вызывает `window.WebViewHandler.postEvent(имя, JSON)`, ответ приходит ей через
 * `window.WebApp.sendEvent(имя, JSON)`. Здесь только разбор запросов и сборка ответов:
 * веб-вид и системные действия — в приложении.
 *
 * Неизвестные методы с `requestId` получают `client.<метод>.unsupported`, как на iPhone.
 * Ответы без команд сервера: NFC «нет», эхо захвата экрана, биометрия и хранилище страницы.
 * Цифровой ID на старте вызывает `WebAppBiometryGetInfo`. Ответ `unsupported` страница
 * считает техническим сбоем и показывает «Техническая заминка». Телефон, скачивание файла
 * и отправка сообщения в чат остаются неподдержанными: для них нет команды в ядре.
 */
class MiniAppBridge(
    val entryPoint: String = "settings",
    private val botId: Long = 0,
    private val deviceId: String = "",
    private val vault: MiniAppVault = MiniAppVault.memory(),
) {

    sealed interface Action {
        data object Ready : Action
        data object Close : Action
        data class BackButton(val visible: Boolean) : Action
        data class ClosingConfirmation(val needed: Boolean) : Action
        data class OpenLink(val url: String) : Action
        data class Haptic(val kind: HapticKind) : Action
        data class Share(val text: String, val requestId: String?) : Action
        data class Reply(val event: String, val json: String) : Action
        data object Ignore : Action
    }

    sealed interface HapticKind {
        data class Impact(val style: String) : HapticKind
        data class Notification(val type: String) : HapticKind
        data object Selection : HapticKind
    }

    /**
     * Разбор события страницы. [width] и [height] — размер страницы в пикселях,
     * уже округлённый.
     * Невалидный JSON даёт пустой список: событие не игнорируется и не исполняется.
     */
    fun handle(name: String, json: String?, width: Int, height: Int): List<Action> {
        val data = fields(json) ?: return emptyList()
        val requestId = requestId(data)
        return when (name) {
            "WebAppReady" -> listOf(Action.Ready)
            "WebAppClose" -> listOf(Action.Close)
            "WebAppSetupBackButton" -> listOf(Action.BackButton(bool(data, "isVisible") ?: false))
            "WebAppSetupClosingBehavior" -> listOf(Action.ClosingConfirmation(bool(data, "needConfirmation") ?: false))
            "WebAppGetLaunchContext" -> listOf(reply(name, requestId, mapOf("entryPoint" to entryPoint)))
            "WebAppGetViewportSize" -> listOf(reply(name, requestId, mapOf(
                "width" to width,
                "height" to height,
                "isStateStable" to true,
            )))
            "WebAppOpenLink", "WebAppOpenMaxLink" -> {
                val url = text(data, "url")?.takeIf { it.isNotEmpty() && hasScheme(it) } ?: return emptyList()
                listOf(Action.OpenLink(url))
            }
            "WebAppHapticFeedbackImpact" -> listOf(
                Action.Haptic(HapticKind.Impact(text(data, "impactStyle") ?: "light")),
                status(name, requestId, "impactOccured"),
            )
            "WebAppHapticFeedbackNotification" -> listOf(
                Action.Haptic(HapticKind.Notification(text(data, "notificationType") ?: "success")),
                status(name, requestId, "notificationOccured"),
            )
            "WebAppHapticFeedbackSelectionChange" -> listOf(
                Action.Haptic(HapticKind.Selection),
                status(name, requestId, "selectionChanged"),
            )
            "WebAppShare" -> {
                val parts = listOfNotNull(text(data, "text"), text(data, "link")).filter { it.isNotEmpty() }
                if (parts.isEmpty()) listOfNotNull(failure(name, requestId, "invalid_request"))
                else listOf(Action.Share(parts.joinToString("\n"), requestId))
            }
            // Страница может ждать ответ, а команда сервера для этого не нужна.
            "WebAppSetupScreenCaptureBehavior" -> listOf(reply(name, requestId, mapOf(
                "isScreenCaptureEnabled" to (bool(data, "isScreenCaptureEnabled") ?: false),
            )))
            "WebAppNfcGetInfo" -> listOf(reply(name, requestId, mapOf("available" to false, "enabled" to false)))
            "WebAppBiometryGetInfo" -> listOf(biometryInfo(name, requestId))
            "WebAppBiometryRequestAccess" -> listOf(biometryAccess(name, requestId))
            "WebAppBiometryRequestAuth" -> listOf(biometryAuth(name, requestId))
            "WebAppBiometryUpdateToken" -> listOf(biometryUpdate(name, requestId, data))
            "WebAppBiometryOpenSettings" -> listOf(reply(name, requestId, mapOf("status" to "opened")))
            "WebAppSecureStorageGetKey" -> listOf(storageGet("secure", name, requestId, data))
            "WebAppSecureStorageSaveKey" -> listOf(storageSave("secure", name, requestId, data))
            "WebAppSecureStorageClear" -> listOf(storageClear("secure", name, requestId))
            "WebAppDeviceStorageGetKey" -> listOf(storageGet("device", name, requestId, data))
            "WebAppDeviceStorageSaveKey" -> listOf(storageSave("device", name, requestId, data))
            "WebAppDeviceStorageClear" -> listOf(storageClear("device", name, requestId))
            "WebAppStat", "WebAppUrlInterceptor", "WebAppBackButtonPressed" -> listOf(Action.Ignore)
            else -> listOf(failure(name, requestId, "unsupported") ?: Action.Ignore)
        }
    }

    /** Ответ на `WebAppShare` после листа «Поделиться». */
    fun shareFinished(requestId: String?, completed: Boolean): Action =
        reply("WebAppShare", requestId, mapOf("status" to if (completed) "shared" else "cancelled"))

    /** Нажата «Назад», когда страница показала свою кнопку. */
    val backPressed: Action = Action.Reply("WebAppBackButtonPressed", "{}")

    /** `request_phone` из `WebAppRequestPhone`: имя метода без `WebApp` в snake_case. */
    fun slug(method: String): String {
        val bare = if (method.startsWith("WebApp")) method.drop(6) else method
        if (bare.isEmpty()) return "unsupported_method"
        val out = StringBuilder()
        bare.forEachIndexed { index, char ->
            if (char.isUpperCase() && index > 0) out.append('_')
            out.append(char.lowercaseChar())
        }
        return out.toString().ifEmpty { "unsupported_method" }
    }

    /**
     * Вызов `window.__orbitleDeliver`. Строки — литералы JavaScript,
     * чтобы страница получила тот же JSON, что собран здесь.
     */
    fun deliverCall(event: String, json: String): String {
        val name = Json.encodeToString(event)
        val payload = Json.encodeToString(json)
        return "window.__orbitleDeliver && window.__orbitleDeliver($name, $payload);"
    }

    private fun biometryInfo(name: String, requestId: String?): Action =
        reply(name, requestId, infoFields(vault.biometry(botId)))

    private fun biometryAccess(name: String, requestId: String?): Action {
        val next = vault.biometry(botId).copy(accessRequested = true, accessGranted = true)
        vault.saveBiometry(botId, next)
        return reply(name, requestId, infoFields(next))
    }

    private fun biometryAuth(name: String, requestId: String?): Action {
        val current = vault.biometry(botId)
        val token = current.token?.takeIf { it.isNotEmpty() } ?: newToken()
        vault.saveBiometry(botId, current.copy(accessRequested = true, accessGranted = true, token = token))
        return reply(name, requestId, mapOf(
            "token" to token,
            "status" to "authorized",
            "granted" to true,
            "accessGranted" to true,
        ))
    }

    private fun biometryUpdate(name: String, requestId: String?, data: Map<String, JsonElement>): Action {
        val raw = data["token"]
        val token = if (raw == null || raw is JsonNull) null else text(data, "token")
        if (token != null && token.length > TOKEN_LIMIT) return failure(name, requestId, "too_large") ?: Action.Ignore
        val current = vault.biometry(botId)
        return if (token.isNullOrEmpty()) {
            vault.saveBiometry(botId, current.copy(token = null))
            reply(name, requestId, mapOf("status" to "removed"))
        } else {
            vault.saveBiometry(botId, current.copy(accessRequested = true, accessGranted = true, token = token))
            reply(name, requestId, mapOf("status" to "updated"))
        }
    }

    private fun infoFields(bio: MiniAppVault.Biometry): Map<String, Any?> = mapOf(
        "available" to true,
        "accessRequested" to bio.accessRequested,
        "accessGranted" to bio.accessGranted,
        "tokenSaved" to !bio.token.isNullOrEmpty(),
        "deviceId" to vault.deviceId(deviceId),
        "type" to listOf("unknown"),
    )

    private fun storageGet(space: String, name: String, requestId: String?, data: Map<String, JsonElement>): Action {
        val key = text(data, "key")?.takeIf { it.isNotEmpty() }
            ?: return failure(name, requestId, "invalid_request") ?: Action.Ignore
        val value = vault.get(space, botId, key) ?: return failure(name, requestId, "not_found") ?: Action.Ignore
        return reply(name, requestId, mapOf("key" to key, "value" to value))
    }

    private fun storageSave(space: String, name: String, requestId: String?, data: Map<String, JsonElement>): Action {
        val key = text(data, "key")?.takeIf { it.isNotEmpty() }
            ?: return failure(name, requestId, "invalid_request") ?: Action.Ignore
        if (key.length > KEY_LIMIT) return failure(name, requestId, "too_large_key") ?: Action.Ignore
        val raw = data["value"]
        if (raw == null || raw is JsonNull) {
            vault.put(space, botId, key, null)
            return reply(name, requestId, mapOf("status" to "saved"))
        }
        val value = text(data, "value") ?: return failure(name, requestId, "invalid_request") ?: Action.Ignore
        if (value.length > VALUE_LIMIT) return failure(name, requestId, "too_large_value") ?: Action.Ignore
        vault.put(space, botId, key, value)
        return reply(name, requestId, mapOf("status" to "saved"))
    }

    private fun storageClear(space: String, name: String, requestId: String?): Action {
        vault.clear(space, botId)
        return reply(name, requestId, mapOf("status" to "cleared"))
    }

    private fun newToken(): String = java.util.UUID.randomUUID().toString().replace("-", "")

    private fun status(name: String, requestId: String?, value: String): Action =
        reply(name, requestId, mapOf("status" to value))

    private fun failure(name: String, requestId: String?, reason: String): Action? {
        requestId ?: return null
        return reply(name, requestId, mapOf("error" to mapOf("code" to "client.${slug(name)}.$reason")))
    }

    private fun reply(name: String, requestId: String?, fields: Map<String, Any?>): Action.Reply {
        val body = LinkedHashMap<String, Any?>()
        body.putAll(fields)
        if (requestId != null) body["requestId"] = requestId
        return Action.Reply(name, jsonObject(body))
    }

    private fun fields(json: String?): Map<String, JsonElement>? {
        if (json.isNullOrEmpty()) return emptyMap()
        val element = try {
            Json.parseToJsonElement(json)
        } catch (_: Exception) {
            return null
        }
        return (element as? JsonObject) ?: return null
    }

    private fun requestId(data: Map<String, JsonElement>): String? {
        val value = data["requestId"] ?: return null
        if (value is JsonNull) return null
        val primitive = value as? JsonPrimitive ?: return value.toString()
        return primitive.contentOrNull
    }

    private fun text(data: Map<String, JsonElement>, key: String): String? {
        val primitive = data[key] as? JsonPrimitive ?: return null
        if (!primitive.isString) return null
        return primitive.content
    }

    private fun bool(data: Map<String, JsonElement>, key: String): Boolean? =
        (data[key] as? JsonPrimitive)?.booleanOrNull

    private fun hasScheme(url: String): Boolean = try {
        !java.net.URI(url).scheme.isNullOrBlank()
    } catch (_: Exception) {
        false
    }

    private fun jsonObject(fields: Map<String, Any?>): String = buildString {
        append('{')
        var first = true
        for (key in fields.keys.sorted()) {
            val value = fields[key] ?: continue
            if (!first) append(',')
            first = false
            append(quote(key))
            append(':')
            append(jsonValue(value))
        }
        append('}')
    }

    private fun jsonValue(value: Any): String = when (value) {
        is String -> quote(value)
        is Boolean -> if (value) "true" else "false"
        is Int -> value.toString()
        is Long -> value.toString()
        is Map<*, *> -> jsonObject(value.entries.associate { it.key.toString() to it.value })
        is List<*> -> buildString {
            append('[')
            value.forEachIndexed { index, item ->
                if (index > 0) append(',')
                append(if (item == null) "null" else jsonValue(item))
            }
            append(']')
        }
        else -> quote(value.toString())
    }

    private fun quote(text: String): String = buildString {
        append('"')
        for (char in text) {
            when (char) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> if (char.code < 0x20) append("\\u%04x".format(char.code)) else append(char)
            }
        }
        append('"')
    }

    companion object {
        private const val TOKEN_LIMIT = 1024
        private const val KEY_LIMIT = 128
        private const val VALUE_LIMIT = 8192

        /** Вызов интерфейса Android `OrbitleWebApp.postEvent`. */
        const val ANDROID_POST = "OrbitleWebApp.postEvent(String(name), String(body));"

        /**
         * Вызов `window.cefQuery`. Пока маршрутизатор CEF не поднял функцию,
         * событие ждёт в очереди того же скрипта.
         */
        const val DESKTOP_POST =
            "if (typeof window.cefQuery === 'function') {" +
                " window.cefQuery({ request: JSON.stringify({ name: String(name), data: String(body) })," +
                " persistent: false, onSuccess: function () {}, onFailure: function () {} });" +
                " } else { cefQueue.push({ name: String(name), data: String(body) }); }"

        /**
         * Скрипт до загрузки страницы. [postStatement] — как отдать событие приложению.
         * Повторный запуск ничего не делает: страницу можно открыть ещё раз в том же виде.
         */
        fun userScript(postStatement: String): String = """
            (function () {
              if (window.__orbitleBridgeReady) { return; }
              window.__orbitleBridgeReady = true;
              var outbox = [];
              function drain() {
                var target = window.WebApp;
                if (!target || typeof target.sendEvent !== 'function') { return; }
                while (outbox.length > 0) {
                  var next = outbox.shift();
                  try { target.sendEvent(next.name, next.data); } catch (e) {}
                }
              }
              setInterval(drain, 50);
              window.__orbitleDeliver = function (name, data) {
                outbox.push({ name: name, data: data });
                drain();
              };
              var cefQueue = [];
              setInterval(function () {
                if (!cefQueue.length || typeof window.cefQuery !== 'function') { return; }
                while (cefQueue.length) {
                  var item = cefQueue.shift();
                  try {
                    window.cefQuery({
                      request: JSON.stringify(item),
                      persistent: false,
                      onSuccess: function () {},
                      onFailure: function () {}
                    });
                  } catch (e) {}
                }
              }, 50);
              function post(name, data) {
                var body = data;
                if (body !== undefined && body !== null && typeof body !== 'string') {
                  try { body = JSON.stringify(body); } catch (e) { body = null; }
                }
                if (body === undefined || body === null) { body = ''; }
                try { $postStatement } catch (e) {}
              }
              window.WebViewHandler = { postEvent: post, resolveShare: function () {} };
            })();
        """.trimIndent()
    }
}
