package app.maxly.ui.calls

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import app.maxly.presentation.calls.CallCenter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** Звуки звонка: гудки исходящего и звонок входящего. */
interface CallSounds {
    fun ringback()
    fun ringtone()
    fun stop()
}

/**
 * Действия экрана звонка поверх [CallCenter]. [answer] и [hangUp] платформа может обернуть:
 * Android сначала спрашивает микрофон.
 */
open class CenterCallActions(
    private val center: CallCenter,
    private val scope: CoroutineScope,
    override val hasSpeaker: Boolean,
    private val onAnswer: (video: Boolean) -> Unit = { video -> scope.launch { center.answer(video) } },
) : CallActions {
    var onShowLink: (String) -> Unit = {}

    override fun answer(video: Boolean) = onAnswer(video)
    override fun decline() { scope.launch { center.decline() } }
    override fun hangUp() { scope.launch { center.hangUp() } }
    override fun minimize() = center.minimize()
    override fun expand() = center.expand()
    override fun toggleMute() { scope.launch { center.toggleMute() } }
    override fun toggleCamera() { scope.launch { center.toggleCamera() } }
    override fun switchCamera() { scope.launch { center.switchCamera() } }
    override fun toggleSpeaker() = center.toggleSpeaker()
    override fun toggleScreen() { scope.launch { center.toggleScreenSharing() } }
    override fun toggleRecording() { scope.launch { center.toggleRecording() } }
    override fun shareLink(link: String) = onShowLink(link)
}

/**
 * Звонки поверх приложения: плашка свёрнутого звонка сверху, полноэкранный звонок, ошибки,
 * ссылка на звонок, гудки и звонок входящего. Порт iOS `CallHost`.
 */
@Composable
fun CallHost(
    center: CallCenter,
    actions: CenterCallActions,
    sounds: CallSounds,
    /** Поделиться ссылкой через систему; `null` — только скопировать. */
    onShareLink: ((String) -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val state by center.state.collectAsState()
    var link by remember { mutableStateOf<String?>(null) }
    actions.onShowLink = { link = it }
    val ringing = state.call?.isRinging == true
    LaunchedEffect(state.playsRingback, ringing) {
        when {
            state.playsRingback -> sounds.ringback()
            ringing -> sounds.ringtone()
            else -> sounds.stop()
        }
    }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            ActiveCallBar(state, actions)
            Box(Modifier.weight(1f)) { content() }
        }
        if (state.call != null && state.isExpanded) {
            MaterialTheme(colorScheme = androidx.compose.material3.darkColorScheme()) {
                CallScreen(state, actions, Modifier.fillMaxSize())
            }
        }
    }
    state.errorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = center::dismissError,
            title = { Text("Звонок") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = center::dismissError) { Text("Понятно") } },
        )
    }
    link?.let { shown -> CallLinkDialog(shown, onJoin = null, onShare = onShareLink, onDismiss = { link = null }) }
}

/** Ссылка на звонок: войти, поделиться или скопировать. */
@Composable
fun CallLinkDialog(link: String, onJoin: (() -> Unit)?, onShare: ((String) -> Unit)?, onDismiss: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    var copied by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (onJoin == null) "Ссылка на звонок" else "Новый звонок") },
        text = {
            Column {
                SelectionContainer { Text(link, style = MaterialTheme.typography.bodyLarge) }
                Spacer(Modifier.height(8.dp))
                Text(
                    if (copied) "Ссылка скопирована" else "Отправьте ссылку тем, кого хотите позвать в звонок.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        },
        confirmButton = {
            if (onJoin != null) {
                TextButton(onClick = {
                    onDismiss()
                    onJoin()
                }) { Text("Войти в звонок") }
            } else {
                TextButton(onClick = onDismiss) { Text("Готово") }
            }
        },
        dismissButton = {
            if (onShare != null) {
                TextButton(onClick = { onShare(link) }) { Text("Поделиться") }
            }
            TextButton(onClick = {
                clipboard.setText(AnnotatedString(link))
                scope.launch { copied = true }
            }) { Text("Скопировать") }
        },
    )
}
