package app.orbitle.ui.chat

// Форматирование текста в поле ввода: разметка поверх набираемого текста, панель кнопок
// и диалог ссылки. Общий для Android и десктопа; учёт отрезков — FormatDraft в ChatViewModel.

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.FormatBold
import androidx.compose.material.icons.filled.FormatItalic
import androidx.compose.material.icons.filled.FormatStrikethrough
import androidx.compose.material.icons.filled.FormatUnderlined
import androidx.compose.material.icons.filled.Link
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.orbitle.domain.TextSpan
import app.orbitle.presentation.chat.FormatDraft

/**
 * Разметка черновика поверх текста поля ввода, как в пузыре: текст не меняется (смещения
 * те же), меняется только вид. Отрезки за концом текста (поле уже короче, модель ещё не
 * успела) обрезаются.
 */
data class FormattingTransformation(val spans: List<TextSpan>, val linkColor: Color) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        if (spans.isEmpty()) return TransformedText(text, OffsetMapping.Identity)
        val length = text.length
        val visible = spans.mapNotNull { span ->
            val from = span.from.coerceIn(0, length)
            val to = (span.from + span.length).coerceIn(from, length)
            if (to > from) Triple(span.kind, from, to) else null
        }
        val builder = AnnotatedString.Builder(text)
        // Отрезки бывают вложены и пересекаются: стиль считается для каждого куска между
        // границами, чтобы подчёркивание и зачёркивание сложились, а не заменили друг друга.
        val bounds = visible.flatMap { listOf(it.second, it.third) }.distinct().sorted()
        for (i in 0 until bounds.size - 1) {
            val start = bounds[i]
            val end = bounds[i + 1]
            val kinds = visible.filter { it.second <= start && it.third >= end }.map { it.first }.toSet()
            if (kinds.isEmpty()) continue
            builder.addStyle(styleOf(kinds), start, end)
        }
        return TransformedText(builder.toAnnotatedString(), OffsetMapping.Identity)
    }

    private fun styleOf(kinds: Set<TextSpan.Kind>): SpanStyle {
        val decorations = buildList {
            if (TextSpan.Kind.UNDERLINE in kinds || TextSpan.Kind.LINK in kinds) add(TextDecoration.Underline)
            if (TextSpan.Kind.STRIKETHROUGH in kinds) add(TextDecoration.LineThrough)
        }
        return SpanStyle(
            fontWeight = when {
                TextSpan.Kind.HEADING in kinds -> FontWeight.Bold
                TextSpan.Kind.STRONG in kinds -> FontWeight.SemiBold
                else -> null
            },
            fontStyle = if (TextSpan.Kind.EMPHASIZED in kinds || TextSpan.Kind.QUOTE in kinds) FontStyle.Italic else null,
            fontFamily = if (TextSpan.Kind.MONOSPACED in kinds) FontFamily.Monospace else null,
            fontSize = if (TextSpan.Kind.HEADING in kinds) 18.sp else androidx.compose.ui.unit.TextUnit.Unspecified,
            color = if (TextSpan.Kind.LINK in kinds) linkColor else Color.Unspecified,
            textDecoration = if (decorations.isEmpty()) null else TextDecoration.combine(decorations),
        )
    }
}

/** Кнопка панели: вид, подпись и что она ставит. */
private data class FormatButton(val kind: TextSpan.Kind, val icon: ImageVector, val label: String)

private val formatButtons = listOf(
    FormatButton(TextSpan.Kind.STRONG, Icons.Filled.FormatBold, "Жирный"),
    FormatButton(TextSpan.Kind.EMPHASIZED, Icons.Filled.FormatItalic, "Курсив"),
    FormatButton(TextSpan.Kind.UNDERLINE, Icons.Filled.FormatUnderlined, "Подчёркнутый"),
    FormatButton(TextSpan.Kind.STRIKETHROUGH, Icons.Filled.FormatStrikethrough, "Зачёркнутый"),
    FormatButton(TextSpan.Kind.MONOSPACED, Icons.Filled.Code, "Моноширинный"),
    FormatButton(TextSpan.Kind.LINK, Icons.Filled.Link, "Ссылка"),
)

/**
 * Панель форматирования над полем ввода. Кнопки действуют на выделение [selection] поля:
 * размеченное целиком — подсвечено и снимается, иначе ставится. Без выделения кнопки
 * неактивны и подсказка просит выделить текст. [hints] — подписи сочетаний клавиш (десктоп).
 */
@Composable
fun FormatBar(
    spans: List<TextSpan>,
    selection: TextRange,
    onToggle: (TextSpan.Kind) -> Unit,
    onLink: () -> Unit,
    modifier: Modifier = Modifier,
    hints: Map<TextSpan.Kind, String> = emptyMap(),
) {
    val enabled = !selection.collapsed
    Row(
        modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        for (button in formatButtons) {
            val active = enabled && FormatDraft.covers(spans, button.kind, selection.min, selection.max)
            val label = hints[button.kind]?.let { "${button.label} ($it)" } ?: button.label
            Box(
                Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (active) MaterialTheme.colorScheme.primary.copy(alpha = 0.16f) else Color.Transparent),
                contentAlignment = Alignment.Center,
            ) {
                IconButton(
                    onClick = { if (button.kind == TextSpan.Kind.LINK) onLink() else onToggle(button.kind) },
                    enabled = enabled,
                    // Нажатие не забирает фокус у поля: выделение в нём остаётся.
                    modifier = Modifier.size(40.dp).focusProperties { canFocus = false },
                ) {
                    Icon(
                        button.icon,
                        label,
                        tint = when {
                            !enabled -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f)
                            active -> MaterialTheme.colorScheme.primary
                            else -> MaterialTheme.colorScheme.onSurfaceVariant
                        },
                    )
                }
            }
        }
        if (!enabled) {
            Text(
                "Выделите текст",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                modifier = Modifier.padding(start = 6.dp),
            )
        }
    }
}

/** Кнопка «Aa» в поле ввода: открыть или закрыть панель форматирования. */
@Composable
fun FormatToggle(open: Boolean, onToggle: () -> Unit, modifier: Modifier = Modifier) {
    IconButton(onClick = onToggle, modifier = modifier.size(44.dp).focusProperties { canFocus = false }) {
        Text(
            "Aa",
            fontWeight = FontWeight.SemiBold,
            fontSize = 16.sp,
            color = if (open) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(bottom = 1.dp),
        )
    }
}

/**
 * Диалог адреса ссылки для выделенного текста. [current] — адрес уже стоящей ссылки: тогда
 * есть «Убрать ссылку». [onDone] получает адрес как ввели (схему добавит модель) или `null`,
 * чтобы убрать ссылку.
 */
@Composable
fun LinkDialog(current: String?, onDone: (String?) -> Unit, onDismiss: () -> Unit) {
    var value by remember { mutableStateOf(TextFieldValue(current.orEmpty(), TextRange(current.orEmpty().length))) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    val ready = value.text.isNotBlank()
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (current == null) "Добавить ссылку" else "Изменить ссылку") },
        text = {
            OutlinedTextField(
                value = value,
                onValueChange = { value = it },
                label = { Text("Адрес") },
                placeholder = { Text("https://") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { if (ready) onDone(value.text) }),
                modifier = Modifier.fillMaxWidth().focusRequester(focus),
            )
        },
        confirmButton = {
            TextButton(onClick = { onDone(value.text) }, enabled = ready) { Text("Готово") }
        },
        dismissButton = {
            Row {
                if (current != null) {
                    TextButton(onClick = { onDone(null) }) { Text("Убрать ссылку", color = MaterialTheme.colorScheme.error) }
                }
                TextButton(onClick = onDismiss) { Text("Отмена") }
            }
        },
    )
}
