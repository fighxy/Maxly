package app.orbitle.ui.chat

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.sp
import app.orbitle.domain.TextSpan

/** Текст пузыря с разметкой сервера и ссылками, найденными в тексте. */
object MessageText {
    private val urlPattern = Regex("""(?i)\b((?:https?://|www\.)[^\s<>"]+[^\s<>".,;:!?)\]}'])""")

    fun annotated(text: String, spans: List<TextSpan>, linkColor: Color, mentionColor: Color): AnnotatedString = buildAnnotatedString {
        append(text)
        val linkStyle = TextLinkStyles(SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline))
        val covered = mutableListOf<IntRange>()
        for (span in spans) {
            val start = span.from.coerceIn(0, text.length)
            val end = (span.from + span.length).coerceIn(start, text.length)
            if (start >= end) continue
            when (span.kind) {
                TextSpan.Kind.STRONG -> addStyle(SpanStyle(fontWeight = FontWeight.SemiBold), start, end)
                TextSpan.Kind.EMPHASIZED -> addStyle(SpanStyle(fontStyle = FontStyle.Italic), start, end)
                TextSpan.Kind.UNDERLINE -> addStyle(SpanStyle(textDecoration = TextDecoration.Underline), start, end)
                TextSpan.Kind.STRIKETHROUGH -> addStyle(SpanStyle(textDecoration = TextDecoration.LineThrough), start, end)
                TextSpan.Kind.MONOSPACED -> addStyle(SpanStyle(fontFamily = FontFamily.Monospace), start, end)
                TextSpan.Kind.HEADING -> addStyle(SpanStyle(fontWeight = FontWeight.Bold, fontSize = 18.sp), start, end)
                TextSpan.Kind.QUOTE -> addStyle(SpanStyle(fontStyle = FontStyle.Italic, color = mentionColor.copy(alpha = 0.9f)), start, end)
                TextSpan.Kind.MENTION -> addStyle(SpanStyle(color = mentionColor, fontWeight = FontWeight.Medium), start, end)
                TextSpan.Kind.LINK -> {
                    val url = span.url ?: text.substring(start, end)
                    addLink(LinkAnnotation.Url(normalized(url), linkStyle), start, end)
                    covered += start until end
                }
                // Анимодзи рисуется отдельно; разметка другого клиента не рисуется, но хранится.
                TextSpan.Kind.ANIMOJI, TextSpan.Kind.UNKNOWN -> Unit
            }
        }
        for (match in urlPattern.findAll(text)) {
            val range = match.range
            if (covered.any { it.first <= range.last && range.first <= it.last }) continue
            addLink(LinkAnnotation.Url(normalized(match.value), linkStyle), range.first, range.last + 1)
        }
    }

    private fun normalized(url: String): String =
        if (url.startsWith("http://", true) || url.startsWith("https://", true) || url.contains("://")) url else "https://$url"
}
