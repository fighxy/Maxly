package app.orbitle.ui.calls

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FiberManualRecord
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.ScreenShare
import androidx.compose.material.icons.filled.StopScreenShare
import androidx.compose.material.icons.filled.SwitchVideo
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.VideocamOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.orbitle.domain.CallParticipant
import app.orbitle.domain.CallPhase
import app.orbitle.presentation.calls.ActiveCall
import app.orbitle.presentation.calls.CallCenterState
import app.orbitle.presentation.calls.CallStatusText
import app.orbitle.presentation.chatlist.ChatAvatar
import app.orbitle.ui.components.Avatar
import app.orbitle.ui.components.clickCursor
import kotlinx.coroutines.delay

/** Видео звонка по id дорожки: у Android — SurfaceViewRenderer, у ПК — кадры в картинку. */
class CallVideoRenderer(val render: @Composable (trackId: String, fill: Boolean, modifier: Modifier) -> Unit)

val LocalCallVideo = staticCompositionLocalOf { CallVideoRenderer { _, _, modifier -> Box(modifier.background(Color.Black)) } }

/** Что экран звонка умеет попросить. */
interface CallActions {
    fun answer(video: Boolean)
    fun decline()
    fun hangUp()
    fun minimize()
    fun expand()
    fun toggleMute()
    fun toggleCamera()
    fun switchCamera()
    fun toggleSpeaker()
    fun toggleScreen()
    fun toggleRecording()
    fun shareLink(link: String)

    /** Громкая связь есть только у телефона. */
    val hasSpeaker: Boolean get() = true
}

/** Текущее время раз в секунду: таймер разговора. */
@Composable
private fun rememberNow(): Long {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(1_000)
        }
    }
    return now
}

private val CallBackground = Brush.verticalGradient(listOf(Color(0xFF1A2133), Color(0xFF0A0D14)))

/** Экран звонка: собеседник или участники, статус, кнопки. Порт iOS `CallScreen`. */
@Composable
fun CallScreen(state: CallCenterState, actions: CallActions, modifier: Modifier = Modifier) {
    val call = state.call ?: return
    val video = LocalCallVideo.current
    val grid = isGrid(call)
    val main = mainVideo(call)
    Box(modifier.fillMaxSize().background(CallBackground)) {
        if (main != null) {
            video.render(main, true, Modifier.fillMaxSize())
            Box(Modifier.fillMaxWidth().height(220.dp).background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.55f), Color.Transparent))))
        }
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            TopBar(call, state, actions)
            if (grid) {
                ParticipantsGrid(call, state, Modifier.weight(1f).padding(horizontal = 12.dp, vertical = 8.dp))
            } else {
                Header(call, hasVideo = main != null, modifier = Modifier.padding(top = if (main == null) 48.dp else 8.dp))
                Spacer(Modifier.weight(1f))
            }
            call.state.notice?.let { notice ->
                Text(
                    notice,
                    color = Color.White,
                    fontSize = 13.sp,
                    modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 12.dp)
                        .clip(CircleShape).background(Color.White.copy(alpha = 0.15f)).padding(horizontal = 14.dp, vertical = 8.dp),
                )
            }
            Controls(call, actions, Modifier.align(Alignment.CenterHorizontally).padding(bottom = 24.dp))
        }
        val local = call.state.localTrack
        if (!grid && local != null && !call.state.isEnded) {
            video.render(
                local,
                true,
                Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(top = 60.dp, end = 14.dp)
                    .size(104.dp, 156.dp).clip(RoundedCornerShape(14.dp))
                    .border(1.dp, Color.White.copy(alpha = 0.25f), RoundedCornerShape(14.dp))
                    .clickCursor()
                    .clickable(onClick = actions::switchCamera),
            )
        }
    }
}

@Composable
private fun TopBar(call: ActiveCall, state: CallCenterState, actions: CallActions) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = actions::minimize) {
            Icon(Icons.Filled.KeyboardArrowDown, "Свернуть звонок", tint = Color.White)
        }
        Spacer(Modifier.weight(1f))
        if (call.state.recording) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.FiberManualRecord, null, Modifier.size(14.dp), tint = Color(0xFFFF453A))
                Spacer(Modifier.width(4.dp))
                Text("Запись", color = Color(0xFFFF453A), fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        Spacer(Modifier.weight(1f))
        if (!call.isRinging && !call.state.isEnded) MoreMenu(call, state, actions) else Spacer(Modifier.size(48.dp))
    }
}

@Composable
private fun MoreMenu(call: ActiveCall, state: CallCenterState, actions: CallActions) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }) { Icon(Icons.Filled.MoreVert, "Ещё", tint = Color.White) }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            if (call.state.cameraOn) {
                DropdownMenuItem(
                    text = { Text("Сменить камеру") },
                    leadingIcon = { Icon(Icons.Filled.SwitchVideo, null) },
                    onClick = { open = false; actions.switchCamera() },
                )
            }
            DropdownMenuItem(
                text = { Text(if (call.state.screenSharing) "Остановить показ экрана" else "Показать экран") },
                leadingIcon = { Icon(if (call.state.screenSharing) Icons.Filled.StopScreenShare else Icons.Filled.ScreenShare, null) },
                onClick = { open = false; actions.toggleScreen() },
            )
            call.joinLink?.let { link ->
                DropdownMenuItem(
                    text = { Text("Ссылка на звонок") },
                    leadingIcon = { Icon(Icons.Filled.Link, null) },
                    onClick = { open = false; actions.shareLink(link) },
                )
            }
            if (canRecord(call)) {
                DropdownMenuItem(
                    text = { Text(if (call.state.recording) "Остановить запись" else "Записать звонок") },
                    leadingIcon = { Icon(Icons.Filled.FiberManualRecord, null) },
                    onClick = { open = false; actions.toggleRecording() },
                )
            }
        }
    }
}

@Composable
private fun Header(call: ActiveCall, hasVideo: Boolean, modifier: Modifier) {
    val now = rememberNow()
    Column(modifier.fillMaxWidth().padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        if (!hasVideo) {
            val speaking = call.state.others.firstOrNull()?.speaking == true
            Box(
                Modifier.border(3.dp, if (speaking) Color(0xFF34C759) else Color.Transparent, CircleShape).padding(6.dp),
            ) {
                Avatar(peerAvatar(call), 128.dp)
            }
            Spacer(Modifier.height(18.dp))
        }
        Text(
            call.peer.name.ifEmpty { "Звонок" },
            color = Color.White,
            fontSize = if (hasVideo) 20.sp else 28.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(Modifier.height(8.dp))
        Text(CallStatusText.status(call, now), color = Color.White.copy(alpha = 0.75f), fontSize = 16.sp)
        val other = call.state.others.firstOrNull()
        if (other != null && !other.audioOn && call.state.phase == CallPhase.Active) {
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.MicOff, null, Modifier.size(14.dp), tint = Color.White.copy(alpha = 0.75f))
                Spacer(Modifier.width(4.dp))
                Text("Микрофон собеседника выключен", color = Color.White.copy(alpha = 0.75f), fontSize = 13.sp)
            }
        }
    }
}

@Composable
private fun ParticipantsGrid(call: ActiveCall, state: CallCenterState, modifier: Modifier) {
    val now = rememberNow()
    val video = LocalCallVideo.current
    Column(modifier) {
        Text(call.peer.name, color = Color.White, fontWeight = FontWeight.SemiBold, modifier = Modifier.align(Alignment.CenterHorizontally))
        Text(
            CallStatusText.status(call, now),
            color = Color.White.copy(alpha = 0.7f),
            fontSize = 13.sp,
            modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 8.dp),
        )
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val columns = if (maxWidth > 700.dp) 3 else 2
            LazyVerticalGrid(
                columns = GridCells.Fixed(columns),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(call.state.participants, key = { it.id }) { participant ->
                    Tile(participant, call, state, video)
                }
            }
        }
    }
}

@Composable
private fun Tile(participant: CallParticipant, call: ActiveCall, state: CallCenterState, video: CallVideoRenderer) {
    val name = if (participant.isSelf) "Вы" else state.name(participant.userId) ?: "Участник"
    val track = if (participant.isSelf) call.state.localTrack else participant.visibleTrack
    val shape = RoundedCornerShape(16.dp)
    Box(
        Modifier.aspectRatio(3f / 4f).clip(shape).background(Color.White.copy(alpha = 0.08f))
            .border(3.dp, if (participant.speaking) Color(0xFF34C759) else Color.Transparent, shape),
    ) {
        if (track != null) {
            video.render(track, true, Modifier.fillMaxSize())
        } else {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Avatar(ChatAvatar(ChatAvatar.Kind.Initials(ChatAvatar.initials(name)), ChatAvatar.colorIndex(participant.userId ?: participant.id.toString())), 64.dp)
            }
        }
        Row(
            Modifier.align(Alignment.BottomStart).padding(8.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.4f))
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (!participant.audioOn) Icon(Icons.Filled.MicOff, null, Modifier.size(12.dp), tint = Color.White)
            if (participant.handRaised) Icon(Icons.Filled.PanTool, null, Modifier.size(12.dp), tint = Color.White)
            Text(name, color = Color.White, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 4.dp))
        }
    }
}

@Composable
private fun Controls(call: ActiveCall, actions: CallActions, modifier: Modifier) {
    when {
        call.isRinging -> Row(modifier, horizontalArrangement = Arrangement.spacedBy(40.dp)) {
            RoundButton("Отклонить", Icons.Filled.CallEnd, Color(0xFFFF3B30), onClick = actions::decline)
            if (call.isVideo) RoundButton("С видео", Icons.Filled.Videocam, Color(0xFF34C759)) { actions.answer(true) }
            RoundButton("Ответить", Icons.Filled.Phone, Color(0xFF34C759)) { actions.answer(false) }
        }
        call.state.isEnded -> RoundButton("Закрыть", Icons.Filled.Close, Color.White.copy(alpha = 0.2f), modifier, actions::hangUp)
        else -> Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(22.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                if (actions.hasSpeaker) Toggle("Динамик", Icons.Filled.VolumeUp, call.state.speakerOn, actions::toggleSpeaker)
                Toggle("Видео", if (call.state.cameraOn) Icons.Filled.Videocam else Icons.Filled.VideocamOff, call.state.cameraOn, actions::toggleCamera)
                Toggle("Микрофон", if (call.state.muted) Icons.Filled.MicOff else Icons.Filled.Mic, call.state.muted, actions::toggleMute)
                Toggle("Экран", Icons.Filled.ScreenShare, call.state.screenSharing, actions::toggleScreen)
            }
            RoundButton("Завершить", Icons.Filled.CallEnd, Color(0xFFFF3B30), onClick = actions::hangUp)
        }
    }
}

/** Круглая кнопка-переключатель: включённая — белая с тёмным значком. */
@Composable
private fun Toggle(title: String, icon: ImageVector, isOn: Boolean, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier.size(60.dp).clip(CircleShape).background(if (isOn) Color.White else Color.White.copy(alpha = 0.16f)).clickCursor().clickable(onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, title, tint = if (isOn) Color.Black else Color.White)
        }
        Spacer(Modifier.height(6.dp))
        Text(title, color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp)
    }
}

/** Большая круглая кнопка: ответить, отклонить, завершить. */
@Composable
private fun RoundButton(title: String, icon: ImageVector, fill: Color, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(72.dp).clip(CircleShape).background(fill).clickCursor().clickable(onClick = onClick), contentAlignment = Alignment.Center) {
            Icon(icon, title, Modifier.size(30.dp), tint = Color.White)
        }
        Spacer(Modifier.height(8.dp))
        Text(title, color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp)
    }
}

/** Плашка свёрнутого звонка над приложением: имя и время; нажатие разворачивает звонок. */
@Composable
fun ActiveCallBar(state: CallCenterState, actions: CallActions, modifier: Modifier = Modifier) {
    val call = state.call ?: return
    if (state.isExpanded) return
    val now = rememberNow()
    Row(
        modifier.fillMaxWidth().background(if (call.isRinging) Color(0xFFFF9500) else Color(0xFF34C759))
            .clickCursor().clickable(onClick = actions::expand).padding(horizontal = 16.dp).height(40.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(if (call.isVideo || call.state.cameraOn) Icons.Filled.Videocam else Icons.Filled.Phone, null, Modifier.size(16.dp), tint = Color.White)
        Spacer(Modifier.width(10.dp))
        Text(
            "${call.peer.name.ifEmpty { "Звонок" }} · ${CallStatusText.status(call, now)}",
            color = Color.White,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        if (!call.isRinging && !call.state.isEnded) {
            IconButton(onClick = actions::toggleMute) {
                Icon(if (call.state.muted) Icons.Filled.MicOff else Icons.Filled.Mic, if (call.state.muted) "Включить микрофон" else "Выключить микрофон", tint = Color.White)
            }
        }
        IconButton(onClick = actions::hangUp) { Icon(Icons.Filled.CallEnd, "Завершить звонок", tint = Color.White) }
    }
}

private fun peerAvatar(call: ActiveCall): ChatAvatar {
    val name = call.peer.name.ifEmpty { "Звонок" }
    val initials = ChatAvatar.initials(name)
    val color = ChatAvatar.colorIndex(call.peer.id.ifEmpty { call.conversationId })
    return ChatAvatar(call.peer.avatarUrl?.let { ChatAvatar.Kind.Photo(it, initials) } ?: ChatAvatar.Kind.Initials(initials), color)
}

private fun isGrid(call: ActiveCall) = call.direction == ActiveCall.Direction.GROUP || call.state.others.size > 1

/** Видео собеседника на весь экран (звонок на двоих). */
private fun mainVideo(call: ActiveCall): String? =
    if (isGrid(call) || call.state.isEnded) null else call.state.others.firstOrNull()?.visibleTrack

private fun canRecord(call: ActiveCall) = isGrid(call) && (call.state.participants.firstOrNull { it.isSelf }?.isAdmin == true || call.state.recording)
