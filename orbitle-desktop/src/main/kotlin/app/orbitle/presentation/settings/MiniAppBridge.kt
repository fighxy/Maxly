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
 * Два ответа без команд сервера (Komet отвечает на них локально, и страница может их ждать):
 * сведения об NFC «нет» и эхо настройки захвата экрана. Телефон, хранилище, биометрия,
 * скачивание файла и отправка сообщения в чат остаются неподдержанными: для них нет команды в ядре.
 */
class MiniAppBridge(val entryPoint: String = "settings") {

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
