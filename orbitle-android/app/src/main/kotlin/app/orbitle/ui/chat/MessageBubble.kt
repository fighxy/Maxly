package app.orbitle.ui.chat

import app.orbitle.presentation.chat.commentsLabel
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.Comment
import androidx.compose.animation.core.Animatable
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import kotlinx.coroutines.launch
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallMade
import androidx.compose.material.icons.automirrored.filled.CallReceived
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.Done
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.VideocamOff
import androidx.compose.material.icons.outlined.InsertDriveFile
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.FileContent
import app.orbitle.domain.Message
import app.orbitle.domain.MessageReaction
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.PhotoContent
import app.orbitle.domain.VideoContent
import app.orbitle.domain.VoiceContent
import app.orbitle.presentation.chat.CallBubbleText
import app.orbitle.presentation.chat.ChatContentFormat
import app.orbitle.presentation.chat.ChatItem
import app.orbitle.presentation.chat.TranscriptUi
import app.orbitle.presentation.chat.WaveformLayout
import app.orbitle.presentation.chatlist.ChatListFormatter
import app.orbitle.ui.components.Avatar
import app.orbitle.ui.theme.AvatarPalette
import app.orbitle.ui.theme.OrbitleAccent
import coil3.compose.AsyncImage

private val MissedRed = Color(0xFFE5484D)

/** Цвета пузыря: свой — акцент, чужой — поверхность. */
data class BubbleColors(val container: Color, val content: Color, val secondary: Color, val accent: Color)

@Composable
fun bubbleColors(outgoing: Boolean): BubbleColors {
    val scheme = MaterialTheme.colorScheme
    return if (outgoing) {
        // Свой пузырь в обеих темах — фирменный акцент с белым текстом.
        BubbleColors(OrbitleAccent, Color.White, Color.White.copy(alpha = 0.72f), Color.White)
    } else {
        BubbleColors(scheme.surfaceContainerHigh, scheme.onSurface, scheme.onSurfaceVariant, scheme.primary)
    }
}

/** Строка ленты с пузырём, аватаром автора группы и реакциями. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun BubbleRow(
    item: ChatItem.Bubble,
    onLongPress: (Message) -> Unit,
    onReaction: (Message, String) -> Unit,
    onReplyClick: (String) -> Unit,
    onRetry: (Message) -> Unit,
    highlighted: Boolean = false,
    onSwipeReply: ((Message) -> Unit)? = null,
    onComments: ((Message) -> Unit)? = null,
) {
    val message = item.message
    val maxWidth = (LocalConfiguration.current.screenWidthDp * 0.8f).dp
    val sticker = message.content.sticker
    val onlySticker = sticker != null && message.displayText.isBlank() && message.content.reply == null
    // Свайп влево — ответ, как в популярных мессенджерах.
    val density = LocalDensity.current
    val threshold = with(density) { 64.dp.toPx() }
    val swipe = remember { Animatable(0f) }
    val swipeScope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    val canSwipe = onSwipeReply != null && message.status == MessageStatus.SENT && message.id.toLongOrNull() != null && !message.isService
    Box(Modifier.fillMaxWidth()) {
    if (swipe.value != 0f) {
        val progress = (-swipe.value / threshold).coerceIn(0f, 1f)
        Box(
            Modifier.align(Alignment.CenterEnd).padding(end = 16.dp).size(32.dp).graphicsLayer { alpha = progress; scaleX = 0.6f + 0.4f * progress; scaleY = scaleX }
                .clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHighest),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.AutoMirrored.Filled.Reply, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp)) }
    }
    Row(
        Modifier
            .fillMaxWidth()
            .then(
                if (!canSwipe) Modifier else Modifier.pointerInput(message.id) {
                    detectHorizontalDragGestures(
                        onDragEnd = {
                            if (-swipe.value >= threshold) onSwipeReply?.invoke(message)
                            swipeScope.launch { swipe.animateTo(0f) }
                        },
                        onDragCancel = { swipeScope.launch { swipe.animateTo(0f) } },
                        onHorizontalDrag = { change, delta ->
                            val before = swipe.value
                            val next = (before + delta).coerceIn(-threshold * 1.4f, 0f)
                            if (-before < threshold && -next >= threshold) haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            swipeScope.launch { swipe.snapTo(next) }
                            change.consume()
                        },
                    )
                },
            )
            .graphicsLayer { translationX = swipe.value }
            .background(if (highlighted) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f) else Color.Transparent)
            .padding(start = 8.dp, end = 8.dp, top = if (item.authorName != null) 6.dp else 1.dp, bottom = if (item.continues) 1.dp else 4.dp),
        horizontalArrangement = if (item.outgoing) Arrangement.End else Arrangement.Start,
        verticalAlignment = Alignment.Bottom,
    ) {
        if (item.isGroupChat) {
            Box(Modifier.width(40.dp)) {
                item.avatar?.let { Avatar(it, 34.dp) }
            }
        }
        val colors = bubbleColors(item.outgoing)
        val tail = 6.dp
        val shape = RoundedCornerShape(
            topStart = 18.dp,
            topEnd = 18.dp,
            bottomEnd = if (item.outgoing && !item.continues) tail else 18.dp,
            bottomStart = if (!item.outgoing && !item.continues) tail else 18.dp,
        )
        val press = Modifier.combinedClickable(
            onClick = { if (message.status == MessageStatus.FAILED) onRetry(message) },
            onLongClick = { onLongPress(message) },
        )
        val roundVideo = (message.content.visuals.singleOrNull() as? ChatAttachment.Video)?.video
            ?.takeIf { it.isRound && message.displayText.isBlank() && message.content.reply == null }
        if (roundVideo != null) {
            Column(horizontalAlignment = if (item.outgoing) Alignment.End else Alignment.Start) {
                item.authorName?.let {
                    Text(it, color = AvatarPalette.nameColor(item.authorColor), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 8.dp, bottom = 2.dp))
                }
                RoundNote(message, roundVideo, onLongPress = { onLongPress(message) })
                Surface(shape = RoundedCornerShape(10.dp), color = Color.Black.copy(alpha = 0.35f), modifier = Modifier.padding(top = 4.dp)) {
                    TimeRow(item, Color.White, Modifier.padding(horizontal = 6.dp, vertical = 2.dp))
                }
                Reactions(message.content.reactions, colors, item.outgoing) { onReaction(message, it) }
                val count = item.comments
                if (count != null && onComments != null) {
                    Surface(shape = RoundedCornerShape(14.dp), color = colors.container, contentColor = colors.content, modifier = Modifier.padding(top = 4.dp).widthIn(max = 220.dp)) {
                        CommentsFooter(count, colors) { onComments(message) }
                    }
                }
            }
            return@Row
        }
        if (onlySticker) {
            Column(horizontalAlignment = if (item.outgoing) Alignment.End else Alignment.Start) {
                AsyncImage(
                    model = sticker!!.url,
                    contentDescription = "Стикер",
                    modifier = Modifier.size(160.dp).clip(RoundedCornerShape(12.dp)).then(press),
                    contentScale = ContentScale.Fit,
                )
                Surface(shape = RoundedCornerShape(10.dp), color = Color.Black.copy(alpha = 0.35f)) {
                    TimeRow(item, Color.White, Modifier.padding(horizontal = 6.dp, vertical = 2.dp))
                }
                Reactions(message.content.reactions, colors, item.outgoing) { onReaction(message, it) }
            }
            return@Row
        }
        Surface(
            shape = shape,
            color = colors.container,
            contentColor = colors.content,
            modifier = Modifier.widthIn(max = maxWidth).clip(shape).then(press),
        ) {
            BubbleContent(item, colors, maxWidth, onReaction, onReplyClick, onComments, onLongPress = { onLongPress(message) })
        }
    }
    }
}

@Composable
private fun BubbleContent(
    item: ChatItem.Bubble,
    colors: BubbleColors,
    maxWidth: Dp,
    onReaction: (Message, String) -> Unit,
    onReplyClick: (String) -> Unit,
    onComments: ((Message) -> Unit)? = null,
    onLongPress: () -> Unit = {},
) {
    val message = item.message
    val content = message.content
    val visuals = content.visuals
    val text = message.displayText.trim()
    Column(Modifier.padding(if (visuals.isNotEmpty() && text.isEmpty() && item.authorName == null && content.reply == null && content.forward == null) 3.dp else 0.dp)) {
        val headerPadding = Modifier.padding(start = 12.dp, end = 12.dp, top = 7.dp)
        item.authorName?.let {
            Text(
                it,
                color = AvatarPalette.nameColor(item.authorColor),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = headerPadding,
            )
        }
        content.forward?.let {
            Text(
                "Переслано от ${it.authorName}",
                color = colors.accent,
                style = MaterialTheme.typography.labelMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = headerPadding,
            )
        }
        content.reply?.let { reply ->
            ReplyQuote(
                author = reply.authorName,
                preview = reply.preview,
                colors = colors,
                modifier = Modifier
                    .padding(start = 8.dp, end = 8.dp, top = 6.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .clickable { onReplyClick(reply.messageId) },
            )
        }
        if (visuals.isNotEmpty()) {
            val bubbleMedia = LocalBubbleMedia.current
            Visuals(visuals, maxWidth - 6.dp, Modifier.padding(top = if (item.authorName != null || content.forward != null || content.reply != null) 6.dp else 0.dp), onLongPress = onLongPress) {
                bubbleMedia.onVisual(message, it)
            }
        }
        content.sticker?.let { sticker ->
            AsyncImage(sticker.url, "Стикер", Modifier.padding(8.dp).size(140.dp), contentScale = ContentScale.Fit)
        }
        content.voices.forEach { PlayableVoice(message, it, colors, maxWidth) }
        content.files.forEach { file -> FileRow(message, file, colors) }
        content.attachments.filterIsInstance<ChatAttachment.Contact>().forEach { contact ->
            AttachmentRow(
                icon = { Icon(Icons.Outlined.Person, null, tint = colors.container, modifier = Modifier.size(22.dp)) },
                title = contact.contact.name.ifEmpty { "Контакт" },
                subtitle = contact.contact.phone.takeIf { it.isNotEmpty() }?.let { if (it.startsWith("+")) it else "+$it" } ?: "контакт MAX",
                colors = colors,
            )
        }
        content.call?.let { call ->
            val icon = when (CallBubbleText.icon(call, item.outgoing)) {
                CallBubbleText.Icon.PHONE -> Icons.Filled.Call
                CallBubbleText.Icon.VIDEO -> Icons.Filled.Videocam
                CallBubbleText.Icon.OUTGOING -> Icons.AutoMirrored.Filled.CallMade
                CallBubbleText.Icon.INCOMING -> Icons.AutoMirrored.Filled.CallReceived
                CallBubbleText.Icon.PHONE_DOWN -> Icons.Filled.CallEnd
                CallBubbleText.Icon.VIDEO_OFF -> Icons.Filled.VideocamOff
            }
            val alert = CallBubbleText.isAlert(call, item.outgoing)
            AttachmentRow(
                icon = { Icon(icon, null, tint = if (alert) Color.White else colors.container, modifier = Modifier.size(20.dp)) },
                title = CallBubbleText.title(call, item.outgoing),
                subtitle = CallBubbleText.duration(call) ?: if (call.isVideo) "Видео" else "Аудио",
                colors = colors,
                circle = if (alert) MissedRed else null,
            )
        }
        if (text.isNotEmpty()) {
            TextWithTime(item, text, colors)
        } else {
            TimeRow(item, colors.secondary, Modifier.align(Alignment.End).padding(start = 12.dp, end = 10.dp, bottom = 6.dp, top = 2.dp))
        }
        Reactions(content.reactions, colors, item.outgoing, Modifier.padding(start = 8.dp, end = 8.dp, bottom = 6.dp)) { onReaction(message, it) }
        val count = item.comments
        if (count != null && onComments != null) CommentsFooter(count, colors) { onComments(message) }
    }
}

/** Нижняя строка поста канала: число комментариев (или «Комментировать») и стрелка. */
@Composable
private fun CommentsFooter(count: Int, colors: BubbleColors, onClick: () -> Unit) {
    val label = commentsLabel(count)
    Column(Modifier.fillMaxWidth().clickable(onClickLabel = "Открыть комментарии", onClick = onClick)) {
        HorizontalDivider(thickness = 0.5.dp, color = colors.content.copy(alpha = 0.12f))
        Row(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.AutoMirrored.Outlined.Comment, null, tint = colors.accent, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(label, color = colors.accent, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = colors.accent.copy(alpha = 0.6f), modifier = Modifier.size(20.dp))
        }
    }
}

/** Текст и время в одном блоке: время встаёт в конец последней строки, если там есть место. */
@Composable
private fun TextWithTime(item: ChatItem.Bubble, text: String, colors: BubbleColors) {
    val message = item.message
    val linkColor = if (item.outgoing) colors.content else MaterialTheme.colorScheme.primary
    val annotated = remember(text, message.content.formatting, linkColor) {
        MessageText.annotated(text, if (text == message.text.trim()) message.content.formatting else emptyList(), linkColor, colors.accent)
    }
    val reserve = timeLabel(item)
    Box(Modifier.padding(start = 12.dp, end = 10.dp, top = 6.dp, bottom = 6.dp)) {
        Text(
            buildAnnotatedString {
                append(annotated)
                // Невидимый хвост под время и галочки.
                withStyle(SpanStyle(color = Color.Transparent, fontSize = 12.sp)) { append("\u2002$reserve\u2002\u2002\u2002") }
            },
            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp, lineHeight = 21.sp),
            color = colors.content,
        )
        TimeRow(item, colors.secondary, Modifier.align(Alignment.BottomEnd))
    }
}

private fun timeLabel(item: ChatItem.Bubble): String =
    if (item.message.content.edited) "изм. ${item.time}" else item.time

@Composable
private fun TimeRow(item: ChatItem.Bubble, color: Color, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Text(timeLabel(item), color = color, fontSize = 12.sp, lineHeight = 14.sp)
        if (item.outgoing) {
            Spacer(Modifier.width(3.dp))
            val message = item.message
            val (icon, tint) = when {
                message.status == MessageStatus.SENDING -> Icons.Filled.Schedule to color
                message.status == MessageStatus.FAILED -> Icons.Filled.ErrorOutline to MaterialTheme.colorScheme.error
                message.isRead -> Icons.Filled.DoneAll to color
                else -> Icons.Filled.Done to color
            }
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(14.dp))
        }
    }
}

@Composable
fun ReplyQuote(author: String, preview: String, colors: BubbleColors, modifier: Modifier = Modifier) {
    Row(
        modifier
            .background(colors.accent.copy(alpha = 0.12f))
            .height(IntrinsicSize.Min),
    ) {
        Box(Modifier.width(3.dp).fillMaxHeight().background(colors.accent))
        Column(Modifier.padding(horizontal = 8.dp, vertical = 4.dp)) {
            Text(author, color = colors.accent, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(preview, color = colors.content, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** Фото и видео: одно — по пропорциям, несколько — сеткой по два. */
@Composable
private fun Visuals(visuals: List<ChatAttachment>, maxWidth: Dp, modifier: Modifier = Modifier, onLongPress: () -> Unit = {}, onOpen: (ChatAttachment) -> Unit) {
    val shape = RoundedCornerShape(15.dp)
    if (visuals.size == 1) {
        val (w, h) = when (val v = visuals.first()) {
            is ChatAttachment.Photo -> v.photo.width to v.photo.height
            is ChatAttachment.Video -> v.video.width to v.video.height
            else -> null to null
        }
        val frame = ChatContentFormat.frame(w, h, maxWidth.value.toDouble(), 360.0)
        Box(modifier.size(frame.width.dp, frame.height.dp).clip(shape).combinedClickable(onLongClick = onLongPress) { onOpen(visuals.first()) }) { VisualCell(visuals.first()) }
        return
    }
    val cell = (maxWidth - 2.dp) / 2
    Column(modifier.clip(shape), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        visuals.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                row.forEach { Box(Modifier.size(if (row.size == 1) maxWidth else cell, cell).combinedClickable(onLongClick = onLongPress) { onOpen(it) }) { VisualCell(it) } }
            }
        }
    }
}

@Composable
private fun VisualCell(attachment: ChatAttachment) {
    val fill = Modifier.fillMaxWidth().fillMaxHeight()
    when (attachment) {
        is ChatAttachment.Photo -> PhotoCell(attachment.photo, fill)
        is ChatAttachment.Video -> VideoCell(attachment.video, fill)
        else -> Unit
    }
}

@Composable
private fun PhotoCell(photo: PhotoContent, modifier: Modifier) {
    Box(modifier.background(Color.Black.copy(alpha = 0.2f))) {
        AsyncImage(photo.url, "Фото", Modifier.fillMaxWidth().fillMaxHeight(), contentScale = ContentScale.Crop)
    }
}

@Composable
private fun VideoCell(video: VideoContent, modifier: Modifier) {
    Box(modifier.background(Color.Black.copy(alpha = 0.4f)), contentAlignment = Alignment.Center) {
        AsyncImage(video.posterUrl, "Видео", Modifier.fillMaxWidth().fillMaxHeight(), contentScale = ContentScale.Crop)
        Box(Modifier.size(44.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.5f)), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.PlayArrow, null, tint = Color.White)
        }
        if (video.durationMs > 0) {
            Text(
                CallBubbleText.clock(video.durationMs),
                color = Color.White,
                fontSize = 12.sp,
                modifier = Modifier.align(Alignment.TopStart).padding(6.dp).clip(RoundedCornerShape(8.dp)).background(Color.Black.copy(alpha = 0.5f)).padding(horizontal = 6.dp, vertical = 1.dp),
            )
        }
    }
}

/** Голосовое пузыря: плеер, перемотка по дорожке и расшифровка. */
@Composable
private fun PlayableVoice(message: Message, voice: VoiceContent, colors: BubbleColors, maxWidth: Dp) {
    val media = LocalBubbleMedia.current
    val playback = media.playback.value?.takeIf { it.matches(message.id, voice.id) }
    val transcript = media.media.value.transcripts[message.id]
    VoiceRow(
        voice = voice,
        colors = colors,
        maxWidth = maxWidth,
        progress = playback?.progress ?: 0f,
        playing = playback?.isPlaying == true,
        buffering = playback?.isBuffering == true,
        positionMs = playback?.positionMs,
        onToggle = if (media.canPlay(voice)) ({ media.onVoice(message, voice) }) else null,
        onSeek = if (media.canPlay(voice)) ({ media.onSeek(message, voice, it) }) else null,
        transcriptOpen = transcript != null,
        onTranscript = if (media.canTranscribe(message, voice)) ({ media.onTranscript(message, voice) }) else null,
    )
    when (transcript) {
        TranscriptUi.Loading -> Row(Modifier.padding(start = 12.dp, end = 12.dp, top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(Modifier.size(12.dp), color = colors.secondary, strokeWidth = 1.5.dp)
            Spacer(Modifier.width(6.dp))
            Text("Расшифровка…", color = colors.secondary, style = MaterialTheme.typography.bodySmall)
        }
        is TranscriptUi.Text -> Text(
            transcript.text,
            color = colors.content,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(start = 12.dp, end = 12.dp, top = 6.dp).widthIn(max = maxWidth - 24.dp),
        )
        null -> Unit
    }
}

/** Голосовое: кнопка, дорожка и длительность. Прогресс рисуется, если идёт воспроизведение. */
@Composable
fun VoiceRow(
    voice: VoiceContent,
    colors: BubbleColors,
    maxWidth: Dp,
    progress: Float = 0f,
    playing: Boolean = false,
    buffering: Boolean = false,
    positionMs: Long? = null,
    onToggle: (() -> Unit)? = null,
    onSeek: ((Float) -> Unit)? = null,
    transcriptOpen: Boolean = false,
    onTranscript: (() -> Unit)? = null,
) {
    Row(Modifier.padding(start = 8.dp, end = 12.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.size(42.dp).clip(CircleShape).background(colors.accent).clickable(enabled = onToggle != null) { onToggle?.invoke() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (playing) "Пауза" else "Воспроизвести", tint = colors.container)
            if (buffering) CircularProgressIndicator(Modifier.size(42.dp), color = colors.container, strokeWidth = 2.dp)
        }
        Spacer(Modifier.width(10.dp))
        Column {
            val width = minOf(maxWidth - if (onTranscript != null) 126.dp else 90.dp, 200.dp)
            var dragging by remember { mutableStateOf<Float?>(null) }
            val seek = if (onSeek == null) Modifier else Modifier
                .pointerInput(onSeek) {
                    detectTapGestures { offset -> onSeek((offset.x / size.width).coerceIn(0f, 1f)) }
                }
                .pointerInput(onSeek) {
                    detectHorizontalDragGestures(
                        onDragStart = { dragging = (it.x / size.width).coerceIn(0f, 1f) },
                        onHorizontalDrag = { change, _ -> dragging = (change.position.x / size.width).coerceIn(0f, 1f) },
                        onDragEnd = { dragging?.let(onSeek); dragging = null },
                        onDragCancel = { dragging = null },
                    )
                }
            Waveform(voice.waveform, dragging ?: progress, colors, Modifier.width(width).height(26.dp).then(seek))
            val shown = when {
                dragging != null && voice.durationMs > 0 -> (dragging!! * voice.durationMs).toLong()
                positionMs != null && (playing || positionMs > 0) -> positionMs
                else -> voice.durationMs
            }
            Text(CallBubbleText.clock(shown), color = colors.secondary, fontSize = 12.sp)
        }
        if (onTranscript != null) {
            Spacer(Modifier.width(6.dp))
            Box(
                Modifier.size(30.dp).clip(RoundedCornerShape(8.dp))
                    .background(colors.accent.copy(alpha = if (transcriptOpen) 0.3f else 0.14f))
                    .clickable(onClick = onTranscript),
                contentAlignment = Alignment.Center,
            ) {
                Text("А", color = colors.accent, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                Icon(
                    if (transcriptOpen) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                    "Расшифровка",
                    tint = colors.accent,
                    modifier = Modifier.size(12.dp).align(Alignment.BottomEnd),
                )
            }
        }
    }
}

/** Файл: нажатие скачивает и открывает, во время загрузки — кольцо прогресса. */
@Composable
private fun FileRow(message: Message, file: FileContent, colors: BubbleColors) {
    val media = LocalBubbleMedia.current
    val progress = media.media.value.downloads[file.id]
    Row(
        Modifier.clip(RoundedCornerShape(12.dp)).clickable { media.onFile(message, file) }
            .padding(start = 8.dp, end = 12.dp, top = 8.dp, bottom = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(42.dp).clip(CircleShape).background(colors.accent), contentAlignment = Alignment.Center) {
            if (progress != null) {
                CircularProgressIndicator(
                    progress = { progress.coerceAtLeast(0.02f) },
                    modifier = Modifier.size(36.dp),
                    color = colors.container,
                    strokeWidth = 2.5.dp,
                    trackColor = colors.container.copy(alpha = 0.25f),
                )
                Icon(Icons.Filled.Close, "Отменить", tint = colors.container, modifier = Modifier.size(18.dp))
            } else {
                Icon(Icons.Outlined.InsertDriveFile, null, tint = colors.container, modifier = Modifier.size(22.dp))
            }
        }
        Spacer(Modifier.width(10.dp))
        Column {
            Text(file.name, color = colors.content, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            val subtitle = if (progress != null && file.size > 0) {
                "${ChatContentFormat.fileSize((file.size * progress).toLong())} из ${ChatContentFormat.fileSize(file.size)}"
            } else {
                ChatContentFormat.fileSize(file.size)
            }
            Text(subtitle, color = colors.secondary, style = MaterialTheme.typography.bodySmall, maxLines = 1)
        }
    }
}

@Composable
fun Waveform(samples: List<Int>, progress: Float, colors: BubbleColors, modifier: Modifier) {
    val density = LocalDensity.current
    Canvas(modifier) {
        val layout = WaveformLayout.of(size.width.toDouble(), with(density) { 3.dp.toPx() }.toDouble(), with(density) { 2.dp.toPx() }.toDouble())
        val heights = layout.heights(samples)
        heights.forEachIndexed { index, h ->
            val barHeight = (size.height * h).toFloat()
            val played = layout.isPlayed(index, progress.toDouble())
            drawRoundRect(
                color = if (played) colors.accent else colors.secondary.copy(alpha = 0.45f),
                topLeft = Offset(layout.x(index).toFloat(), (size.height - barHeight) / 2),
                size = Size(layout.barWidth.toFloat(), barHeight),
                cornerRadius = CornerRadius(layout.barWidth.toFloat() / 2),
            )
        }
    }
}

@Composable
private fun AttachmentRow(icon: @Composable () -> Unit, title: String, subtitle: String, colors: BubbleColors, circle: Color? = null) {
    Row(Modifier.padding(start = 8.dp, end = 12.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(42.dp).clip(CircleShape).background(circle ?: colors.accent), contentAlignment = Alignment.Center) { icon() }
        Spacer(Modifier.width(10.dp))
        Column {
            Text(title, color = colors.content, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(subtitle, color = colors.secondary, style = MaterialTheme.typography.bodySmall, maxLines = 1)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Reactions(reactions: List<MessageReaction>, colors: BubbleColors, outgoing: Boolean, modifier: Modifier = Modifier, onTap: (String) -> Unit) {
    if (reactions.isEmpty()) return
    FlowRow(modifier.padding(top = 2.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        reactions.forEach { reaction ->
            val background = when {
                reaction.mine && outgoing -> colors.content.copy(alpha = 0.95f)
                reaction.mine -> colors.accent
                else -> colors.accent.copy(alpha = 0.14f)
            }
            val foreground = when {
                reaction.mine && outgoing -> colors.container
                reaction.mine -> Color.White
                else -> colors.content
            }
            Row(
                Modifier.clip(RoundedCornerShape(14.dp)).background(background).clickable { onTap(reaction.emoji) }.padding(horizontal = 8.dp, vertical = 3.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(reaction.emoji, fontSize = 15.sp)
                Spacer(Modifier.width(4.dp))
                Text(ChatListFormatter.compactCount(reaction.count), color = foreground, fontSize = 13.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}
