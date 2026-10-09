package app.maxly.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.maxly.data.diagnostics.CrashReport
import app.maxly.data.diagnostics.FileLog
import app.maxly.diagnostics.DesktopDiagnostics
import app.maxly.platform.AppPaths
import app.maxly.platform.BackHandler
import app.maxly.platform.DesktopActions
import java.io.File

/**
 * Журнал и отчёты о сбоях в «О приложении»: папку журнала можно открыть, журнал — сохранить
 * в «Загрузки», отчёт — прочитать, скопировать или удалить.
 */
@Composable
fun DiagnosticsSection() {
    // Счётчик перечитывает список после удаления.
    var revision by remember { mutableIntStateOf(0) }
    val reports = remember(revision) { DesktopDiagnostics.reports?.list().orEmpty() }
    val logEmpty = remember(revision) { DesktopDiagnostics.log?.isEmpty ?: true }
    var opened by remember { mutableStateOf<CrashReport?>(null) }
    var saved by remember { mutableStateOf<File?>(null) }

    HorizontalDivider(Modifier.padding(top = 8.dp))
    SectionTitle("Диагностика")
    ListItem(
        headlineContent = { Text("Открыть папку журнала") },
        supportingContent = { Text(DesktopDiagnostics.log?.dir?.absolutePath.orEmpty()) },
        leadingContent = { Icon(Icons.Outlined.FolderOpen, null) },
        modifier = Modifier.clickable { DesktopDiagnostics.log?.dir?.let { it.mkdirs(); DesktopActions.openFile(it) } },
    )
    ListItem(
        headlineContent = { Text("Сохранить журнал в «Загрузки»") },
        supportingContent = {
            Text(saved?.let { "Сохранён: ${it.name}" } ?: "Приложите файл к сообщению о проблеме: в журнале нет текста переписки")
        },
        leadingContent = { Icon(Icons.Outlined.Description, null) },
        modifier = Modifier.clickable(enabled = !logEmpty) { saved = saveLog() },
    )
    if (!logEmpty) {
        ListItem(
            headlineContent = { Text("Очистить журнал") },
            leadingContent = { Icon(Icons.Outlined.DeleteOutline, null) },
            modifier = Modifier.clickable {
                DesktopDiagnostics.log?.clear()
                saved = null
                revision++
            },
        )
    }

    SectionTitle("Сбои и зависания")
    if (reports.isEmpty()) {
        ListItem(
            headlineContent = { Text("Сбоев не было", color = MaterialTheme.colorScheme.onSurfaceVariant) },
            leadingContent = { Icon(Icons.Outlined.BugReport, null) },
        )
    } else {
        reports.forEach { report ->
            ListItem(
                headlineContent = { Text(report.title, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                supportingContent = { Text(FileLog.timestamp(report.timeMs).take(19)) },
                leadingContent = { Icon(Icons.Outlined.BugReport, null, tint = MaterialTheme.colorScheme.error) },
                modifier = Modifier.clickable { opened = report },
            )
        }
        ListItem(
            headlineContent = { Text("Удалить все отчёты", color = MaterialTheme.colorScheme.error) },
            leadingContent = { Icon(Icons.Outlined.DeleteOutline, null, tint = MaterialTheme.colorScheme.error) },
            modifier = Modifier.clickable {
                DesktopDiagnostics.reports?.removeAll()
                revision++
            },
        )
    }

    opened?.let { report ->
        val text = remember(report.name) { DesktopDiagnostics.reports?.text(report.name).orEmpty() }
        // Esc закрывает отчёт, а не экран «О приложении» под ним.
        BackHandler { opened = null }
        AlertDialog(
            onDismissRequest = { opened = null },
            modifier = Modifier.widthIn(max = 760.dp),
            title = { Text(report.title, maxLines = 3, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleSmall) },
            text = {
                SelectionContainer {
                    Text(
                        text,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 11.sp,
                        lineHeight = 14.sp,
                        modifier = Modifier.heightIn(max = 460.dp).verticalScroll(rememberScrollState()),
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = { DesktopActions.copy(text) }) {
                    Icon(Icons.Outlined.ContentCopy, null, Modifier.padding(end = 6.dp))
                    Text("Скопировать")
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    DesktopDiagnostics.reports?.remove(report.name)
                    opened = null
                    revision++
                }) { Text("Удалить", color = MaterialTheme.colorScheme.error) }
                TextButton(onClick = { opened = null }) { Text("Закрыть") }
            },
        )
    }
}

/** Журнал одним файлом в «Загрузки» со сведениями о сборке в начале; папка открывается. */
private fun saveLog(): File? {
    val log = DesktopDiagnostics.log ?: return null
    return runCatching {
        val stamp = FileLog.timestamp(System.currentTimeMillis()).take(19).replace(':', '-').replace(' ', '_')
        val file = File(AppPaths.downloads, "orbitle-log-$stamp.txt")
        file.writeText("Журнал Orbitle\n" + DesktopDiagnostics.info() + "\n\n" + log.read())
        DesktopActions.openFile(AppPaths.downloads)
        file
    }.getOrNull()
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.fillMaxWidth().padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}
