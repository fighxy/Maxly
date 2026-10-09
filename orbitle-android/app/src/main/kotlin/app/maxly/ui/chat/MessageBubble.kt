package app.maxly.ui.chat

import app.maxly.presentation.chat.commentsLabel
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.Comment
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.ui.semantics.Role
import app.maxly.presentation.chat.TranscriptToggle
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
import androidx.compose.foundation.shape.CornerBasedShape
import androidx.compose.foundation.shape.CornerSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.material.icons.automirrored.filled.CallMade
import androidx.compose.material.icons.automirrored.filled.CallReceived
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Close
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
import androidx.compose.ui.graphics.Shape
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
import app.maxly.domain.ChatAttachment
import app.maxly.domain.PollContent
import app.maxly.domain.FileContent
import app.maxly.domain.Message
import app.maxly.presentation.media.ImageRequests
import app.maxly.domain.MessageReaction
import app.maxly.domain.MessageStatus
import app.maxly.domain.TextSpan
import app.maxly.domain.PhotoContent
import app.maxly.domain.VideoContent
import app.maxly.domain.VoiceContent
import app.maxly.presentation.chat.CallBubbleText
import app.maxly.presentation.chat.ChatContentFormat
import app.maxly.presentation.chat.ChatItem
import app.maxly.presentation.chat.TranscriptUi
import app.maxly.presentation.chat.WaveformLayout
import app.maxly.presentation.chatlist.ChatListFormatter
import app.maxly.ui.components.Avatar
import app.maxly.ui.theme.AvatarPalette
import app.maxly.ui.theme.MaxlyOutgoing
import coil3.compose.AsyncImage

private val MissedRed = Color(0xFFE5484D)

/** Цвета пузыря: свой — акцент, чужой — поверхность. */
data class BubbleColors(val container: Color, val content: Color, val secondary: Color, val accent: Color)

@Composable
fun bubbleColors(outgoing: Boolean): BubbleColors {
    val scheme = MaterialTheme.colorScheme
    return if (outgoing) {
        // Свой пузырь в обеих темах — фирменный акцент с белым текстом.
        BubbleColors(MaxlyOutgoing, Color.White, Color.White.copy(alpha = 0.72f), Color.White)
    } else {
        // На обоях в светлой теме чужой пузырь белый, чтобы читался на светлом узоре.
        val backdrop = app.maxly.ui.components.LocalChatBackdrop.current
        val onWallpaper = !backdrop.dark && backdrop.wallpaper.image(false) != null
        BubbleColors(if (onWallpaper) Color.White else scheme.surfaceContainerHigh, scheme.onSurface, scheme.onSurfaceVariant, scheme.primary)
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
    onVote: (Message, String) -> Unit = { _, _ -> },
    onDoubleTap: (Message) -> Unit = {},
    /** Нажатие inline-кнопки бота. `null` — кнопки видны, но не нажимаются. */
    onButton: ((Message, app.maxly.domain.InlineButton) -> Unit)? = null,
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
        val radii = app.maxly.presentation.chat.BubbleCorners.of(item.outgoing, item.joinsPrevious, item.continues)
        val shape = RoundedCornerShape(
            topStart = radii.topStart.dp,
            topEnd = radii.topEnd.dp,
            bottomEnd = radii.bottomEnd.dp,
            bottomStart = radii.bottomStart.dp,
        )
        val press = Modifier.combinedClickable(
            onClick = { if (message.status == MessageStatus.FAILED) onRetry(message) },
            onLongClick = { onLongPress(message) },
            onDoubleClick = { onDoubleTap(message) },
        )
        val roundVideo = (message.content.visuals.singleOrNull() as? ChatAttachment.Video)?.video
            ?.takeIf { it.isRound && message.displayText.isBlank() && message.content.reply == null }
        if (roundVideo != null) {
            Column(horizontalAlignment = if (item.outgoing) Alignment.End else Alignment.Start) {
                item.authorName?.let {
                    Text(it, color = AvatarPalette.nameColor(item.authorColor), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 8.dp, bottom = 2.dp))
                }
                RoundNote(message, roundVideo, onLongPress = { onLongPress(message) }, onDoubleTap = { onDoubleTap(message) })
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
        val bigEmoji = ChatContentFormat.bigEmoji(message.displayText)?.takeIf {
            message.content.attachments.isEmpty() && message.content.reply == null &&
                message.content.forward == null && item.comments == null
        }
        if (bigEmoji != null) {
            val lottie = message.content.formatting.firstOrNull { it.kind == TextSpan.Kind.ANIMOJI }?.url
            Column(horizontalAlignment = if (item.outgoing) Alignment.End else Alignment.Start, modifier = press) {
                item.authorName?.let {
                    Text(it, color = AvatarPalette.nameColor(item.authorColor), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 8.dp, bottom = 2.dp))
                }
                if (bigEmoji.size == 1 && !lottie.isNullOrBlank()) {
                    LottieOrStill(lottie, null, Modifier.size(120.dp), bigEmoji.single())
                } else {
                    Text(bigEmoji.joinToString(""), fontSize = ChatContentFormat.bigEmojiSize(bigEmoji.size).sp, modifier = Modifier.padding(horizontal = 2.dp))
                }
                Surface(shape = RoundedCornerShape(10.dp), color = Color.Black.copy(alpha = 0.35f), modifier = Modifier.padding(top = 4.dp)) {
                    TimeRow(item, Color.White, Modifier.padding(horizontal = 6.dp, vertical = 2.dp))
                }
                Reactions(message.content.reactions, colors, item.outgoing) { onReaction(message, it) }
            }
            return@Row
        }
        if (onlySticker) {
            Column(horizontalAlignment = if (item.outgoing) Alignment.End else Alignment.Start) {
                LottieOrStill(
                    sticker!!.lottieUrl,
                    sticker.url,
                    Modifier.size(168.dp).clip(RoundedCornerShape(12.dp)).then(press),
                    "Стикер",
                )
                Surface(shape = RoundedCornerShape(10.dp), color = Color.Black.copy(alpha = 0.35f)) {
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
        Column(horizontalAlignment = if (item.outgoing) Alignment.End else Alignment.Start, modifier = Modifier.widthIn(max = maxWidth)) {
            Surface(
                shape = shape,
                color = colors.container,
                contentColor = colors.content,
                modifier = Modifier.widthIn(max = maxWidth).clip(shape).then(press),
            ) {
                BubbleContent(item, colors, maxWidth, shape, onReaction, onReplyClick, onComments, onLongPress = { onLongPress(message) }, onVote = onVote, onDoubleTap = { onDoubleTap(message) })
            }
            message.content.keyboard?.let { keyboard ->
                InlineKeyboardView(keyboard, enabled = onButton != null) { onButton?.invoke(message, it) }
            }
        }
    }
    }
}

@Composable
private fun BubbleContent(
    item: ChatItem.Bubble,
    colors: BubbleColors,
    maxWidth: Dp,
    mediaShape: Shape,
    onReaction: (Message, String) -> Unit,
    onReplyClick: (String) -> Unit,
    onComments: ((Message) -> Unit)? = null,
    onLongPress: () -> Unit = {},
    onVote: (Message, String) -> Unit = { _, _ -> },
    onDoubleTap: () -> Unit = {},
) {
    val message = item.message
    val content = message.content
    val visuals = content.visuals
    val text = message.displayText.trim()
    val pad = if (visuals.isNotEmpty() && text.isEmpty() && item.authorName == null && content.reply == null && content.forward == null) 3.dp else 0.dp
    // С фото или видео пузырь шириной с медиа: подпись переносится под картинкой,
    // а не растягивает пузырь вбок от узкой вертикальной фотографии.
    val mediaWidth = if (visuals.isNotEmpty()) Modifier.width(visualsWidth(visuals, maxWidth - 6.dp) + pad * 2) else Modifier
    Column(mediaWidth.padding(pad)) {
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
            // Подпись под медиа: снизу у картинки прямые углы, она переходит в подпись.
            val shape = if (text.isNotEmpty()) {
                (mediaShape as? CornerBasedShape)?.copy(bottomStart = CornerSize(0.dp), bottomEnd = CornerSize(0.dp)) ?: mediaShape
            } else {
                mediaShape
            }
            Visuals(visuals, maxWidth - 6.dp, Modifier.padding(top = if (item.authorName != null || content.forward != null || content.reply != null) 6.dp else 0.dp), shape, onLongPress = onLongPress, onDoubleTap = onDoubleTap) {
                bubbleMedia.onVisual(message, it)
            }
        }
        content.sticker?.let { sticker ->
            LottieOrStill(sticker.lottieUrl, sticker.url, Modifier.padding(8.dp).size(140.dp), "Стикер")
        }
        // Одно голосовое без текста: время и галочки справа внизу самого голосового.
        val voiceOnly = text.isEmpty() && content.voices.size == 1 && visuals.isEmpty() && content.files.isEmpty() &&
            content.call == null && content.sticker == null
        val transcriptShown = voiceOnly && LocalBubbleMedia.current.media.value.transcripts[message.id] != null
        content.voices.forEach {
            PlayableVoice(message, it, colors, maxWidth, footer = if (voiceOnly) ({ TimeRow(item, colors.secondary) }) else null)
        }
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
        content.poll?.let { poll -> PollChoices(poll, colors) { onVote(message, it) } }
        if (text.isNotEmpty()) {
            TextWithTime(item, text, colors)
        } else if (voiceOnly && !transcriptShown) {
            Spacer(Modifier.height(6.dp))
        } else {
            TimeRow(item, colors.secondary, Modifier.align(Alignment.End).padding(start = 12.dp, end = 10.dp, bottom = 6.dp, top = 2.dp))
        }
        content.linkPreview?.let { LinkPreviewCard(it, colors) }
        Reactions(content.reactions, colors, item.outgoing, Modifier.padding(start = 8.dp, end = 8.dp, bottom = 6.dp)) { onReaction(message, it) }
        val count = item.comments
        if (count != null && onComments != null) CommentsFooter(count, colors) { onComments(message) }
    }
}

/** Ответы опроса. Касание строки отправляет голос, если сообщение уже на сервере. */
@Composable
private fun PollChoices(poll: PollContent, colors: BubbleColors, onVote: (String) -> Unit) {
    val canVote = app.maxly.presentation.chat.PollRules.canVote(poll)
    Column(Modifier.padding(start = 8.dp, end = 8.dp, top = 6.dp).fillMaxWidth()) {
        Text(poll.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        poll.answers.forEach { answer ->
            val fraction = if (poll.total <= 0) 0f else answer.votes.toFloat() / poll.total.toFloat()
            val chosen = answer.id in poll.picked || (poll.picked.isEmpty() && answer.id in poll.mine)
            Column(
                Modifier
                    .padding(top = 6.dp)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .clickable(enabled = canVote) { onVote(answer.id) }
                    .padding(horizontal = 8.dp, vertical = 6.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        if (chosen) "✓ ${answer.text}" else answer.text,
                        modifier = Modifier.weight(1f),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        fontWeight = if (chosen) FontWeight.SemiBold else null,
                    )
                    Text(answer.votes.toString(), style = MaterialTheme.typography.labelMedium, color = colors.secondary)
                }
                Box(
                    Modifier
                        .padding(top = 4.dp)
                        .fillMaxWidth()
                        .height(4.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(colors.content.copy(alpha = 0.12f)),
                ) {
                    Box(
                        Modifier
                            .fillMaxWidth(fraction.coerceIn(0f, 1f))
                            .height(4.dp)
                            .background(colors.accent),
                    )
                }
            }
        }
        if (poll.multiple && canVote) {
            androidx.compose.material3.TextButton(
                onClick = { onVote(app.maxly.presentation.chat.PollRules.SUBMIT) },
                enabled = poll.picked.isNotEmpty(),
            ) { Text("Голосовать") }
        }
        Text(
            app.maxly.presentation.chat.PollRules.footer(poll),
            style = MaterialTheme.typography.labelSmall,
            color = colors.secondary,
            modifier = Modifier.padding(top = 4.dp, start = 4.dp),
        )
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
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Visuals(visuals: List<ChatAttachment>, maxWidth: Dp, modifier: Modifier = Modifier, shape: Shape, onLongPress: () -> Unit = {}, onDoubleTap: () -> Unit = {}, onOpen: (ChatAttachment) -> Unit) {
    if (visuals.size == 1) {
        val frame = singleFrame(visuals.first(), maxWidth)
        Box(modifier.size(frame.width.dp, frame.height.dp).clip(shape).combinedClickable(onLongClick = onLongPress, onDoubleClick = onDoubleTap) { onOpen(visuals.first()) }) { VisualCell(visuals.first(), frame.width.dp) }
        return
    }
    val cell = (maxWidth - 2.dp) / 2
    Column(modifier.clip(shape), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        visuals.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                row.forEach { Box(Modifier.size(if (row.size == 1) maxWidth else cell, cell).combinedClickable(onLongClick = onLongPress, onDoubleClick = onDoubleTap) { onOpen(it) }) { VisualCell(it, if (row.size == 1) maxWidth else cell) } }
            }
        }
    }
}

/** Одно фото или видео: по пропорциям, не выше 360 dp. */
private fun singleFrame(visual: ChatAttachment, maxWidth: Dp): ChatContentFormat.Frame {
    val (w, h) = when (visual) {
        is ChatAttachment.Photo -> visual.photo.width to visual.photo.height
        is ChatAttachment.Video -> visual.video.width to visual.video.height
        else -> null to null
    }
    return ChatContentFormat.frame(w, h, maxWidth.value.toDouble(), 360.0)
}

/** Ширина медиа пузыря ([Visuals]): одно — по пропорциям, несколько — сетка во всю ширину. */
private fun visualsWidth(visuals: List<ChatAttachment>, maxWidth: Dp): Dp =
    if (visuals.size == 1) singleFrame(visuals.first(), maxWidth).width.dp else maxWidth

@Composable
private fun VisualCell(attachment: ChatAttachment, width: Dp) {
    val fill = Modifier.fillMaxWidth().fillMaxHeight()
    when (attachment) {
        is ChatAttachment.Photo -> PhotoCell(attachment.photo, fill, width)
        is ChatAttachment.Video -> VideoCell(attachment.video, fill, width)
        else -> Unit
    }
}

@Composable
private fun PhotoCell(photo: PhotoContent, modifier: Modifier, width: Dp) {
    val model = ImageRequests.width(photo.url, width.value, LocalDensity.current.density)
    Box(modifier.background(Color.Black.copy(alpha = 0.2f))) {
        AsyncImage(model, "Фото", Modifier.fillMaxWidth().fillMaxHeight(), contentScale = ContentScale.Crop)
    }
}

@Composable
private fun VideoCell(video: VideoContent, modifier: Modifier, width: Dp) {
    Box(modifier.background(Color.Black.copy(alpha = 0.4f)), contentAlignment = Alignment.Center) {
        AsyncImage(ImageRequests.width(video.posterUrl, width.value, LocalDensity.current.density), "Видео", Modifier.fillMaxWidth().fillMaxHeight(), contentScale = ContentScale.Crop)
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
private fun PlayableVoice(message: Message, voice: VoiceContent, colors: BubbleColors, maxWidth: Dp, footer: (@Composable () -> Unit)? = null) {
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
        // С открытой расшифровкой время встаёт под неё, как у текста.
        footer = footer.takeIf { transcript == null },
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

/**
 * Голосовое: кнопка, дорожка на всю ширину пузыря, справа сверху — расшифровка, снизу —
 * длительность и [footer] (время и галочки пузыря). Касание дорожки переходит к месту под
 * пальцем, горизонтальное перетаскивание перематывает с подсветкой и временем под пальцем.
 */
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
    footer: (@Composable () -> Unit)? = null,
) {
    val density = LocalDensity.current
    val haptic = LocalHapticFeedback.current
    var dragging by remember { mutableStateOf<Float?>(null) }
    // Та же раскладка столбиков, что у рисунка: граница подсветки встаёт ровно под палец.
    fun fraction(x: Float, width: Int): Float {
        val layout = WaveformLayout.of(width.toDouble(), with(density) { 3.dp.toPx() }.toDouble(), with(density) { 2.dp.toPx() }.toDouble())
        return layout.progressAt(x.toDouble()).toFloat().coerceIn(0f, 1f)
    }
    Column(Modifier.width(minOf(maxWidth - 8.dp, 300.dp)).padding(start = 8.dp, end = 10.dp, top = 8.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Box(
                Modifier.size(42.dp).clip(CircleShape).background(colors.accent).clickable(enabled = onToggle != null) { onToggle?.invoke() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (playing) "Пауза" else "Воспроизвести", tint = colors.container)
                if (buffering) CircularProgressIndicator(Modifier.size(42.dp), color = colors.container, strokeWidth = 2.dp)
            }
            Spacer(Modifier.width(10.dp))
            val seek = if (onSeek == null) Modifier else Modifier
                .pointerInput(onSeek) {
                    detectTapGestures { offset -> onSeek(fraction(offset.x, size.width)) }
                }
                .pointerInput(onSeek) {
                    detectHorizontalDragGestures(
                        onDragStart = {
                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            dragging = fraction(it.x, size.width)
                        },
                        onHorizontalDrag = { change, _ ->
                            change.consume()
                            dragging = fraction(change.position.x, size.width)
                        },
                        onDragEnd = {
                            dragging?.let(onSeek)
                            dragging = null
                        },
                        onDragCancel = { dragging = null },
                    )
                }
            Waveform(
                voice.waveform,
                dragging ?: progress,
                colors,
                Modifier.weight(1f).padding(top = 4.dp).height(34.dp).then(seek).semantics { contentDescription = "Дорожка голосового" },
            )
            if (onTranscript != null) {
                Spacer(Modifier.width(8.dp))
                // По центру кнопки воспроизведения (42 dp), а не у верха строки.
                Box(Modifier.height(42.dp), contentAlignment = Alignment.Center) {
                    TranscriptButton(transcriptOpen, colors.accent, onTranscript)
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(start = 52.dp), verticalAlignment = Alignment.CenterVertically) {
            val shown = when {
                dragging != null && voice.durationMs > 0 -> (dragging!! * voice.durationMs).toLong()
                positionMs != null && (playing || positionMs > 0) -> positionMs
                else -> voice.durationMs
            }
            Text(CallBubbleText.clock(shown), color = colors.secondary, fontSize = 12.sp)
            Spacer(Modifier.weight(1f))
            footer?.invoke()
        }
    }
}

/**
 * Капсула расшифровки голосового: «→Т», пока текст скрыт, и стрелка вверх, когда он открыт
 * или загружается. Смена содержимого — короткое растворение с лёгким масштабом.
 */
@Composable
private fun TranscriptButton(open: Boolean, accent: Color, onClick: () -> Unit) {
    val background by animateColorAsState(
        accent.copy(alpha = TranscriptToggle.backgroundAlpha(open)),
        animationSpec = tween(TRANSCRIPT_ANIMATION_MS),
        label = "transcriptBackground",
    )
    val description = TranscriptToggle.description(open)
    Box(
        Modifier.size(width = 34.dp, height = 26.dp).clip(RoundedCornerShape(percent = 50))
            .background(background)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        AnimatedContent(
            targetState = open,
            transitionSpec = {
                (fadeIn(tween(TRANSCRIPT_ANIMATION_MS)) + scaleIn(tween(TRANSCRIPT_ANIMATION_MS), initialScale = 0.85f)) togetherWith
                    (fadeOut(tween(TRANSCRIPT_ANIMATION_MS)) + scaleOut(tween(TRANSCRIPT_ANIMATION_MS), targetScale = 0.85f))
            },
            contentAlignment = Alignment.Center,
            label = "transcriptContent",
        ) { expanded ->
            if (expanded) {
                Icon(Icons.Filled.KeyboardArrowUp, null, tint = accent, modifier = Modifier.size(18.dp))
            } else {
                TranscribeMark(accent)
            }
        }
    }
}

private const val TRANSCRIPT_ANIMATION_MS = 200

/**
 * Значок «→Т» линиями, а не текстом: у буквы шрифта свои отступы над и под ней, и стрелка-иконка
 * рядом вставала выше середины «Т». Здесь стрелка ровно на середине буквы, обе по центру капсулы.
 */
@Composable
private fun TranscribeMark(color: Color) {
    androidx.compose.foundation.Canvas(Modifier.size(width = 18.dp, height = 12.dp)) {
        val stroke = 1.8.dp.toPx()
        val cap = androidx.compose.ui.graphics.StrokeCap.Round
        val mid = size.height / 2
        // Стрелка: древко и наконечник.
        val tip = size.width * 0.42f
        val head = size.height * 0.28f
        drawLine(color, androidx.compose.ui.geometry.Offset(stroke / 2, mid), androidx.compose.ui.geometry.Offset(tip, mid), stroke, cap)
        drawLine(color, androidx.compose.ui.geometry.Offset(tip - head, mid - head), androidx.compose.ui.geometry.Offset(tip, mid), stroke, cap)
        drawLine(color, androidx.compose.ui.geometry.Offset(tip - head, mid + head), androidx.compose.ui.geometry.Offset(tip, mid), stroke, cap)
        // «Т»: перекладина у верха, ножка до низа.
        val left = size.width * 0.58f
        val right = size.width - stroke / 2
        val top = stroke / 2
        val bottom = size.height - stroke / 2
        drawLine(color, androidx.compose.ui.geometry.Offset(left, top), androidx.compose.ui.geometry.Offset(right, top), stroke, cap)
        drawLine(color, androidx.compose.ui.geometry.Offset((left + right) / 2, top), androidx.compose.ui.geometry.Offset((left + right) / 2, bottom), stroke, cap)
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
                reaction.mine -> MaterialTheme.colorScheme.onPrimary
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
