package app.maxly.ui.settings

import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Share
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.maxly.R
import app.maxly.data.diagnostics.CrashReport
import app.maxly.data.diagnostics.FileLog
import app.maxly.diagnostics.Diagnostics

/**
 * Журнал и отчёты о сбоях в «О приложении», как на iOS: журнал отправляется файлом, отчёт
 * открывается, отправляется или удаляется. Хранится до 20 последних отчётов.
 */
@Composable
fun DiagnosticsSection() {
    val context = LocalContext.current
    // Счётчик перечитывает список после удаления.
    var revision by remember { mutableIntStateOf(0) }
    val reports = remember(revision) { Diagnostics.reports?.list().orEmpty() }
    val logEmpty = remember(revision) { Diagnostics.log?.isEmpty ?: true }
    var opened by remember { mutableStateOf<CrashReport?>(null) }

    HorizontalDivider(Modifier.padding(top = 8.dp))
    SectionTitle(stringResource(R.string.diag_title))
    ListItem(
        headlineContent = { Text(stringResource(R.string.diag_log_share)) },
        supportingContent = { Text(stringResource(R.string.diag_log_hint)) },
        leadingContent = { Icon(Icons.Outlined.Description, null) },
        modifier = Modifier.clickable {
            if (!Diagnostics.shareLog(context)) Toast.makeText(context, R.string.diag_log_empty, Toast.LENGTH_SHORT).show()
        },
    )
    if (!logEmpty) {
        ListItem(
            headlineContent = { Text(stringResource(R.string.diag_log_clear)) },
            leadingContent = { Icon(Icons.Outlined.DeleteOutline, null) },
            modifier = Modifier.clickable {
                Diagnostics.log?.clear()
                revision++
            },
        )
    }

    SectionTitle(stringResource(R.string.diag_crashes))
    if (reports.isEmpty()) {
        ListItem(
            headlineContent = { Text(stringResource(R.string.diag_crashes_none), color = MaterialTheme.colorScheme.onSurfaceVariant) },
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
            headlineContent = { Text(stringResource(R.string.diag_crashes_clear), color = MaterialTheme.colorScheme.error) },
            leadingContent = { Icon(Icons.Outlined.DeleteOutline, null, tint = MaterialTheme.colorScheme.error) },
            modifier = Modifier.clickable {
                Diagnostics.reports?.removeAll()
                revision++
            },
        )
    }

    opened?.let { report ->
        val text = remember(report.name) { Diagnostics.reports?.text(report.name).orEmpty() }
        AlertDialog(
            onDismissRequest = { opened = null },
            title = { Text(report.title, maxLines = 3, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleSmall) },
            text = {
                SelectionContainer {
                    Text(
                        text,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 11.sp,
                        lineHeight = 14.sp,
                        modifier = Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState()),
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = { Diagnostics.shareReport(context, report.name) }) {
                    Icon(Icons.Outlined.Share, null, Modifier.padding(end = 6.dp))
                    Text(stringResource(R.string.diag_share))
                }
            },
            dismissButton = {
                Column {
                    TextButton(onClick = {
                        Diagnostics.reports?.remove(report.name)
                        opened = null
                        revision++
                    }) { Text(stringResource(R.string.diag_delete), color = MaterialTheme.colorScheme.error) }
                    TextButton(onClick = { opened = null }) { Text(stringResource(R.string.diag_close)) }
                }
            },
        )
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.fillMaxWidth().padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}
