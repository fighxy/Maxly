package app.orbitle.ui.chat

// Режим выбора нескольких сообщений: шапка с действиями и строка ленты с отметкой.
// Общий для Android и десктопа; правила выбора — в ChatViewModel.

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Forward
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.orbitle.presentation.chat.MessageSelection

/** Шапка чата в режиме выбора: сколько выбрано, крестик выхода и действия над выбранным. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SelectionTopBar(
    count: Int,
    onClose: () -> Unit,
    onCopy: () -> Unit,
    onForward: () -> Unit,
    onDelete: () -> Unit,
) {
    TopAppBar(
        navigationIcon = { IconButton(onClick = onClose) { Icon(Icons.Filled.Close, "Отменить выбор") } },
        title = { Text(MessageSelection.title(count), style = MaterialTheme.typography.titleMedium, maxLines = 1) },
        actions = {
            IconButton(onClick = onCopy) { Icon(Icons.Filled.ContentCopy, "Копировать") }
            IconButton(onClick = onForward) { Icon(Icons.AutoMirrored.Filled.Forward, "Переслать") }
            IconButton(onClick = onDelete) { Icon(Icons.Outlined.Delete, "Удалить", tint = MaterialTheme.colorScheme.error) }
        },
    )
}

/**
 * Строка ленты с пузырём. В режиме выбора ([selecting]) слева отметка, выбранная строка
 * подсвечена, а нажатие (и долгое нажатие) по строке только переключает выбор: ссылки, фото и
 * кнопки внутри пузыря в это время не нажимаются; невыбираемые (служебные, не ушедшие) просто
 * не откликаются. [modifier] — свои жесты клиента над строкой (Ctrl+щелчок на десктопе).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SelectableBubble(
    selecting: Boolean,
    selected: Boolean,
    selectable: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Box(modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .background(if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.14f) else Color.Transparent),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (selecting) {
                Box(Modifier.width(40.dp).padding(start = 8.dp), contentAlignment = Alignment.Center) {
                    if (selectable) {
                        Icon(
                            if (selected) Icons.Filled.CheckCircle else Icons.Outlined.RadioButtonUnchecked,
                            contentDescription = null,
                            tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                }
            }
            Box(Modifier.weight(1f)) { content() }
        }
        if (selecting) {
            // Поверх пузыря: в режиме выбора нажатия не доходят до его содержимого.
            Box(
                Modifier
                    .matchParentSize()
                    .semantics { contentDescription = if (selected) "Снять выбор" else "Выбрать сообщение" }
                    .combinedClickable(
                        onLongClick = { if (selectable) onToggle() },
                        onClick = { if (selectable) onToggle() },
                    ),
            )
        }
    }
}
