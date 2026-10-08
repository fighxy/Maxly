package app.orbitle.presentation.chat

import app.orbitle.SharedFixtures
import app.orbitle.SharedFixtures.Companion.array
import app.orbitle.SharedFixtures.Companion.long
import app.orbitle.SharedFixtures.Companion.obj
import app.orbitle.SharedFixtures.Companion.raw
import app.orbitle.SharedFixtures.Companion.str
import app.orbitle.data.MessageMapping
import app.orbitle.data.TextMarks
import app.orbitle.domain.TextSpan
import app.orbitle.domain.TextSpans
import com.max.core.api.MaxMessage
import com.max.core.api.TextElement
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Общие с iOS сценарии разметки текста из `test-fixtures/formatting` (правила — в README
 * каталога). Путь тот же, что у клиента: чтение — [MessageMapping.content] над сообщением ядра
 * ([TextElement.parseAll], затем [TextMarks.fromRaw]); поле ввода — [FormatDraft] (кнопки, правка
 * текста, обрезка перед отправкой); элементы запроса — [TextMarks.toElements] и
 * [TextElement.payloadFor]; «правка без изменений» — [TextSpans.unchanged], как в `saveEdit`.
 */
class FormattingFixtureTest {
    private val fixtures = SharedFixtures("formatting")

    @Test
    fun everyFixtureIsPlayed() {
        val files = fixtures.files()
        for (file in files) play(file.nameWithoutExtension, fixtures.read(file))
        assertTrue("сыграно ${fixtures.played} случаев", fixtures.played >= files.size)
        fixtures.finish("FormattingFixtureTest", files.size)
    }

    /** Поломанный ожидаемый результат ловится: проигрыватель не проходит молча. */
    @Test
    fun brokenExpectationFails() {
        val file = File(fixtures.files().first().parentFile, "parse-defaults.json")
        val broken = Regex("\"length\": 6,(\\s*)\"text\": \"Привет\"").replaceFirst(file.readText(), "\"length\": 5,$1\"text\": \"Привет\"")
        check(broken != file.readText()) { "в parse-defaults нет ожидаемого отрезка" }
        val failure = runCatching { play("parse-defaults", SharedFixtures.parse(broken)) }.exceptionOrNull()
        assertTrue("сломанный сценарий прошёл", failure is AssertionError)
    }

    private fun play(file: String, fixture: JsonObject) {
        val kind = fixture["kind"].str
        for (case in fixtures.cases(fixture)) {
            fixtures.case("$file / ${case["name"].str}") {
                when (kind) {
                    "parse" -> parse(case)
                    "serialize" -> serialize(case)
                    "toggle" -> toggle(case)
                    "replace" -> replace(case)
                    "edit" -> edit(case)
                    else -> error("$file: незнакомый kind $kind")
                }
            }
        }
    }

    // ---- kind: parse — входящее сообщение -------------------------------------------------------

    private fun SharedFixtures.Case.parse(case: JsonObject) {
        val text = case["text"].str!!
        val raw = linkedMapOf<String, Any?>("id" to 1L, "chatId" to 100L, "time" to 1_000L, "type" to "USER", "sender" to 2L, "text" to text)
        if (case.containsKey("elements")) raw["elements"] = case["elements"]!!.raw()
        val message = MaxMessage.from(raw, 100L)!!
        val expect = case["expect"].obj!!["spans"].array.map { it as JsonObject }
        // Поле text ожидаемого отрезка — накрытый им кусок: проверка самого сценария на UTF-16.
        for (span in expect) {
            val from = span["from"].long!!.toInt()
            val length = span["length"].long!!.toInt()
            span["text"].str?.let { check("кусок текста под ${span["type"].str} $from+$length", it, text.substring(from, from + length)) }
        }
        check("spans", expect.map(::spanKey), MessageMapping.content(message).formatting.map(::spanKey))
    }

    // ---- kind: serialize — отправка из поля ввода ------------------------------------------------

    private fun SharedFixtures.Case.serialize(case: JsonObject) {
        val draft = case["text"].str!!
        val (text, spans) = field(draft, spans(case["spans"])).trimmed(draft)
        val expect = case["expect"].obj!!
        expect["text"].str?.let { check("text", it, text) }
        check("elements", canon(expect["elements"]!!.raw()), canon(TextElement.payloadFor(text, TextMarks.toElements(text, spans))))
    }

    // ---- kind: toggle — кнопка панели и ссылка ---------------------------------------------------

    private fun SharedFixtures.Case.toggle(case: JsonObject) {
        val text = case["text"].str!!
        val draft = field(text, spans(case["spans"]))
        val selection = case["selection"].obj!!
        val start = selection["from"].long!!.toInt()
        val end = start + selection["length"].long!!.toInt()
        val kind = kindOf(case["type"].str!!)
        if (kind == TextSpan.Kind.LINK) draft.setLink(start, end, case["url"].str) else draft.toggle(kind, start, end)
        check("spans", spans(case["expect"].obj!!["spans"]).map(::spanKey), draft.spans.map(::spanKey))
    }

    // ---- kind: replace — правка текста поля ------------------------------------------------------

    private fun SharedFixtures.Case.replace(case: JsonObject) {
        val draft = FormatDraft().apply { restore(spans(case["spans"])) }
        val edit = case["edit"].obj!!
        draft.replace(edit["at"].long!!.toInt(), edit["removed"].long!!.toInt(), edit["inserted"].long!!.toInt())
        check("spans", spans(case["expect"].obj!!["spans"]).map(::spanKey), draft.spans.map(::spanKey))
    }

    // ---- kind: edit — правка своего сообщения -----------------------------------------------------

    private fun SharedFixtures.Case.edit(case: JsonObject) {
        val original = case["original"].obj!!
        val originalText = original["text"].str!!
        val raw = mapOf("id" to 1L, "chatId" to 100L, "time" to 1_000L, "type" to "USER", "sender" to 1L, "text" to originalText, "elements" to original["elements"]?.raw())
        val originalSpans = MessageMapping.content(MaxMessage.from(raw, 100L)!!).formatting
        val draft = case["draft"].obj!!
        val draftText = draft["text"].str!!
        // Как в ChatViewModel: поле — разметка сообщения, правленная кнопками; уходит обрезанное.
        val (text, marks) = field(draftText, spans(draft["spans"])).trimmed(draftText)
        val request = !TextSpans.unchanged(originalText, originalSpans, text, marks)
        val expect = case["expect"].obj!!
        check("request", expect["request"]?.raw(), request)
        if (expect["request"]?.raw() == true && request) {
            check("text", expect["text"].str, text)
            check("elements", canon(expect["elements"]!!.raw()), canon(TextElement.payloadFor(text, TextMarks.toElements(text, marks))))
        }
    }

    // ---- помощники ------------------------------------------------------------------------------

    /** Поле ввода с текстом [text] и разметкой [spans], как после `beginEdit` / восстановления черновика. */
    private fun field(text: String, spans: List<TextSpan>) = FormatDraft().apply { restore(spans, text.length) }

    private fun spans(value: JsonElement?): List<TextSpan> = value.array.map {
        it as JsonObject
        TextSpan(kindOf(it["type"].str!!), it["from"].long!!.toInt(), it["length"].long!!.toInt(), url = it["url"].str)
    }

    private fun spanKey(span: TextSpan) = "${span.kind} ${span.from}+${span.length}" + (span.url?.let { " $it" } ?: "")

    private fun spanKey(span: JsonObject) =
        "${kindOf(span["type"].str!!)} ${span["from"].long}+${span["length"].long}" + (span["url"].str?.let { " $it" } ?: "")

    private fun kindOf(type: String): TextSpan.Kind = when (type) {
        "USER_MENTION" -> TextSpan.Kind.MENTION
        else -> TextSpan.Kind.valueOf(type)
    }

    /** Тело запроса для сравнения: числа — `Long`, ключи по алфавиту. */
    private fun canon(value: Any?): Any? = when (value) {
        is Number -> value.toLong()
        is Map<*, *> -> value.entries.associate { (k, v) -> k.toString() to canon(v) }.toSortedMap()
        is List<*> -> value.map(::canon)
        else -> value
    }
}
