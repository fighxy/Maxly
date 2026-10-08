package app.orbitle.ui.chat

// Лента чата: строки, прокрутка, кнопка «вниз», плавающая дата.

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.withFrameNanos
import androidx.compose.runtime.rememberUpdatedState
import app.orbitle.presentation.chat.ChatUiState
import app.orbitle.presentation.chat.ScrollPlace
import app.orbitle.presentation.chat.ScrollRequest
import kotlinx.coroutines.flow.distinctUntilChanged
import androidx.compose.material3.Button
import app.orbitle.presentation.chat.BotAppRequest
import app.orbitle.domain.InlineButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import app.orbitle.presentation.chat.SaveTarget
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Download
import app.orbitle.presentation.chat.ReactionPalette
import androidx.compose.material.icons.outlined.Group
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.material.icons.outlined.EmojiEmotions
import androidx.compose.material.icons.outlined.Keyboard
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import app.orbitle.domain.AnimatedEmoji
import app.orbitle.domain.Sticker
import app.orbitle.presentation.stickers.StickerPanel
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.InsertDriveFile
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.ui.layout.ContentScale
import app.orbitle.domain.OutgoingFile
import coil3.compose.AsyncImage
import java.io.File
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.MarkChatUnread
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.filled.Mic
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import app.orbitle.ui.components.privateBlur
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Forward
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.automirrored.outlined.Comment
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.Poll
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import app.orbitle.domain.Message
import app.orbitle.domain.MessageStatus
import app.orbitle.presentation.chat.ChatItem
import app.orbitle.presentation.chat.ChatViewModel
import app.orbitle.presentation.chatlist.ChatListItem
import app.orbitle.ui.components.Avatar
import app.orbitle.ui.components.ChatWallpaperBackground
import app.orbitle.ui.components.edgeFade
import app.orbitle.ui.components.LocalChatBackdrop
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Закрытый пузырь приватного режима: заглушка или размытый пузырь, касание открывает его. */
@Composable
internal fun PrivateBubble(item: ChatItem.Bubble, privacy: app.orbitle.domain.PrivateModeDisplay, onReveal: () -> Unit) {
    val shown = remember(item, privacy) {
        if (privacy == app.orbitle.domain.PrivateModeDisplay.PLACEHOLDER) app.orbitle.presentation.settings.PrivateModeMask.bubble(item) else item
    }
    Box(Modifier.fillMaxWidth()) {
        Box(Modifier.privateBlur(privacy, 12.dp)) {
            BubbleRow(item = shown, onLongPress = {}, onReaction = { _, _ -> }, onReplyClick = {}, onRetry = {})
        }
        // Поверх пузыря: меню, реакции и смахивание закрытого пузыря недоступны.
        Box(
            Modifier
                .matchParentSize()
                .clickable(
                    interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() },
                    indication = null,
                    onClickLabel = "Покажет сообщение на 15 секунд",
                    onClick = onReveal,
                )
                .semantics { contentDescription = app.orbitle.presentation.settings.PrivateModeMask.messageText(item.message, item.outgoing) },
        )
    }
}

/** Капсула «Отключить приватный режим» и подсказка под ней. */
@Composable
internal fun PrivateModeCapsule(showsHint: Boolean, onDisable: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Surface(
            onClick = onDisable,
            shape = RoundedCornerShape(50),
            color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.92f),
            shadowElevation = 2.dp,
        ) {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.VisibilityOff, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(8.dp))
                Text("Отключить приватный режим", style = MaterialTheme.typography.labelLarge)
            }
        }
        if (showsHint) {
            Surface(
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.colorScheme.surfaceContainer.copy(alpha = 0.85f),
                modifier = Modifier.padding(top = 6.dp, start = 32.dp, end = 32.dp),
            ) {
                Text(
                    app.orbitle.presentation.settings.PrivateModeMask.REVEAL_HINT,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                )
            }
        }
    }
}

@Composable
internal fun DayChip(label: String) {
    Box(Modifier.fillMaxWidth().padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
        Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.9f)) {
            Text(label, Modifier.padding(horizontal = 10.dp, vertical = 3.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
internal fun ServiceChip(text: String) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 4.dp), contentAlignment = Alignment.Center) {
        Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.8f)) {
            Text(text, Modifier.padding(horizontal = 10.dp, vertical = 4.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        }
    }
}

@Composable
internal fun EmptyHint(text: String, modifier: Modifier) {
    Surface(modifier.padding(32.dp), shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh) {
        Text(text, Modifier.padding(20.dp), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * Лента чата: перевёрнутый список (новые снизу). Куда встать — решает модель
 * ([ChatUiState.scroll]): к свежим, к «Непрочитанным» у верха экрана, к сообщению посередине с
 * подсветкой или на прежнее место. Лента сообщает, что видно ([ChatViewModel.onVisible]): чат
 * читается до самого нового увиденного, кнопка «вниз» показывает, сколько пришло ниже. У верха —
 * старые страницы, у низа окна перехода — новые. Плавающая дата видна, пока ленту крутят.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun ChatFeed(
    model: ChatViewModel,
    state: ChatUiState,
    privacy: app.orbitle.domain.PrivateModeDisplay,
    revealed: List<String>,
    onReveal: (String) -> Unit,
    onLongPress: (Message) -> Unit,
    onRetry: (Message) -> Unit,
    quickReaction: String?,
    onButton: (Message, InlineButton) -> Unit,
    onDisablePrivateMode: () -> Unit,
    modifier: Modifier = Modifier,
    /** Выбранные сообщения: непустой набор — режим выбора ([ChatViewModel.selection]). */
    selection: Set<String> = emptySet(),
) {
    val listState = rememberLazyListState()
    val selecting = selection.isNotEmpty()
    val density = LocalDensity.current
    var highlighted by remember { mutableStateOf<String?>(null) }
    val items by rememberUpdatedState(state.items)
    val hasNewer by rememberUpdatedState(state.hasNewer)

    // Запросы модели: выполнить один раз и снять.
    val request = state.scroll
    LaunchedEffect(request?.token) {
        val current = request ?: return@LaunchedEffect
        FeedScroll.perform(listState, items, current.target, with(density) { UNREAD_TOP_GAP.toPx() }) { key ->
            highlighted = key
            delay(HIGHLIGHT_MS)
            if (highlighted == key) highlighted = null
        }
        model.consumeScroll(current.token)
    }
    // Что видно: самое новое сообщение, показанное хотя бы на треть, и лента ли у низа.
    // Считается только лента: верхняя панель, поле ввода и клавиатура снаружи неё, а отступы
    // содержимого прячут строки под накладками внутри ленты — под ними сообщение не прочитано.
    LaunchedEffect(listState) {
        snapshotFlow {
            val info = listState.layoutInfo
            val frames = info.visibleItemsInfo.mapNotNull { row ->
                (items.getOrNull(row.index) as? ChatItem.Bubble)?.let {
                    app.orbitle.presentation.chat.FeedItemFrame(row.index, it.key, row.offset, row.size)
                }
            }
            val newest = app.orbitle.presentation.chat.ReadVisibility.newestVisibleKey(
                frames, info.viewportStartOffset, info.viewportEndOffset, info.reverseLayout,
                beforeContent = info.beforeContentPadding, afterContent = info.afterContentPadding,
            )
            newest to (listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset < BOTTOM_SLOP && !hasNewer)
        }.distinctUntilChanged().collect { (newest, atBottom) -> model.onVisible(newest, atBottom) }
    }
    // У верха — старая страница, у низа окна перехода — новая.
    LaunchedEffect(listState) {
        snapshotFlow {
            val info = listState.layoutInfo
            Triple(info.visibleItemsInfo.firstOrNull()?.index, info.visibleItemsInfo.lastOrNull()?.index, info.totalItemsCount to hasNewer)
        }.collect { (first, last, total) ->
            if (last != null && total.first > 0 && last >= total.first - PAGE_TRIGGER) model.loadOlder()
            if (first != null && total.second && first <= NEWER_TRIGGER) model.loadNewer()
        }
    }
    // Новое внизу, пока лента у низа: показать его. Своё отправленное прокручивает модель.
    val newest = state.items.firstOrNull()?.key
    LaunchedEffect(newest) {
        if (newest != null && !state.hasNewer && state.scroll == null && listState.firstVisibleItemIndex <= 1) listState.animateScrollToItem(0)
    }
    // Ушли из чата: где была лента. У низа — ничего, чат откроется на свежих.
    DisposableEffect(listState) {
        onDispose {
            val index = listState.firstVisibleItemIndex
            val offset = listState.firstVisibleItemScrollOffset
            val key = items.getOrNull(index)?.key
            model.savePlace(if (key == null || index == 0 && offset < BOTTOM_SLOP) null else ScrollPlace(key, offset))
        }
    }
    val awayFromBottom by remember {
        derivedStateOf {
            val info = listState.layoutInfo
            app.orbitle.presentation.chat.ScrollDown.isVisible(info.visibleItemsInfo.map { it.index }, info.totalItemsCount)
        }
    }
    // Плавающая дата: день верхнего видимого сообщения, пока ленту крутят, и чуть после.
    val topDay by remember {
        derivedStateOf {
            listState.layoutInfo.visibleItemsInfo.asReversed().firstNotNullOfOrNull { info ->
                when (val item = items.getOrNull(info.index)) {
                    is ChatItem.Bubble -> item.day.ifEmpty { null }
                    is ChatItem.Day -> item.label
                    else -> null
                }
            }
        }
    }
    var showsDay by remember { mutableStateOf(false) }
    LaunchedEffect(listState.isScrollInProgress) {
        if (listState.isScrollInProgress) showsDay = true else {
            delay(DAY_PILL_LINGER_MS)
            showsDay = false
        }
    }

    Box(modifier) {
        when {
            state.isLoading -> CircularProgressIndicator(Modifier.align(Alignment.Center))
            state.emptyHint != null -> EmptyHint(state.emptyHint!!, Modifier.align(Alignment.Center))
        }
        LazyColumn(
            state = listState,
            reverseLayout = true,
            // Тонкое растворение сверху, лёгкое снизу — в обои или фон.
            modifier = Modifier.fillMaxSize().edgeFade(top = 10.dp, bottom = 16.dp),
            contentPadding = PaddingValues(top = if (privacy != app.orbitle.domain.PrivateModeDisplay.VISIBLE) 88.dp else 10.dp, bottom = 12.dp),
        ) {
            items(state.items, key = { it.key }, contentType = { it::class }) { item ->
                when (item) {
                    is ChatItem.Day -> DayChip(item.label)
                    is ChatItem.Service -> ServiceChip(item.text)
                    ChatItem.Unread -> UnreadDivider()
                    is ChatItem.Bubble -> SelectableBubble(
                        selecting = selecting,
                        selected = item.key in selection,
                        selectable = model.canSelect(item.message),
                        onToggle = { model.toggleSelection(item.message) },
                    ) { if (privacy != app.orbitle.domain.PrivateModeDisplay.VISIBLE && item.key !in revealed) {
                        PrivateBubble(item, privacy) { onReveal(item.key) }
                    } else BubbleRow(
                        item = item,
                        onLongPress = onLongPress,
                        onReaction = { message, emoji -> model.toggleReaction(message, emoji) },
                        // Цитата ответа: к оригиналу, «вниз» вернёт сюда.
                        onReplyClick = { id -> model.jumpTo(id, from = item.key) },
                        onRetry = onRetry,
                        highlighted = highlighted == item.key,
                        onSwipeReply = if (state.canWrite) model::beginReply else null,
                        onComments = model::openComments,
                        onVote = model::vote,
                        onDoubleTap = { message -> quickReaction?.let { model.toggleReaction(message, it) } },
                        onButton = onButton,
                    ) }
                }
            }
            if (state.isLoadingOlder) {
                item(key = "older") {
                    Box(Modifier.fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                    }
                }
            }
        }
        androidx.compose.animation.AnimatedVisibility(
            visible = showsDay && topDay != null && privacy == app.orbitle.domain.PrivateModeDisplay.VISIBLE,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 8.dp),
        ) {
            DayChip(topDay.orEmpty())
        }
        androidx.compose.animation.AnimatedVisibility(
            visible = privacy != app.orbitle.domain.PrivateModeDisplay.VISIBLE,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 8.dp),
        ) {
            PrivateModeCapsule(showsHint = state.items.any { it is ChatItem.Bubble }, onDisable = onDisablePrivateMode)
        }
        if (state.isJumping || state.isLoadingNewer) {
            CircularProgressIndicator(Modifier.align(Alignment.BottomCenter).padding(bottom = 16.dp).size(24.dp), strokeWidth = 2.dp)
        }
        androidx.compose.animation.AnimatedVisibility(
            visible = awayFromBottom || state.hasNewer || state.canReturn,
            enter = fadeIn() + scaleIn(),
            exit = fadeOut() + scaleOut(),
            // Ровно над кнопкой отправки: её центр в 8 + 22 dp от края, у кнопки «вниз» радиус 20.
            modifier = Modifier.align(Alignment.BottomEnd).padding(end = 10.dp, bottom = 12.dp),
        ) {
            BadgedBox(badge = {
                if (state.unreadBelow > 0) Badge { Text(app.orbitle.presentation.chatlist.ChatListFormatter.compactCount(state.unreadBelow)) }
            }) {
                SmallFloatingActionButton(
                    onClick = model::scrollDown,
                    containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                ) { Icon(Icons.Filled.KeyboardArrowDown, if (state.canReturn) "Назад к сообщению" else "Вниз") }
            }
        }
    }
}

/** Как лента выполняет запросы прокрутки модели. */
internal object FeedScroll {
    suspend fun perform(
        list: LazyListState,
        items: List<ChatItem>,
        target: ScrollRequest.Target,
        unreadTopGap: Float,
        highlight: suspend (String) -> Unit,
    ) {
        when (target) {
            ScrollRequest.Target.Bottom -> {
                // Далеко — прыжок почти до низа, дальше плавно.
                if (list.firstVisibleItemIndex > FAR_JUMP) list.scrollToItem(NEAR_BOTTOM)
                list.animateScrollToItem(0)
            }
            is ScrollRequest.Target.Unread -> {
                val index = items.indexOfFirst { it is ChatItem.Unread }.takeIf { it >= 0 }
                    ?: items.indexOfFirst { it.key == target.key }.takeIf { it >= 0 } ?: return
                list.scrollToItem(index)
                // Сдвиг — на следующем кадре: лента только что сменила строки, и второй проход
                // прокрутки в том же кадре упирается в ещё не применённую композицию.
                withFrameNanos { }
                // Перевёрнутый список ставит строку к низу; сдвиг назад поднимает её к верху.
                val viewport = list.layoutInfo.viewportSize.height
                if (viewport > unreadTopGap) list.scrollBy(-(viewport - unreadTopGap))
            }
            is ScrollRequest.Target.Message -> {
                val index = items.indexOfFirst { it.key == target.key }.takeIf { it >= 0 } ?: return
                list.scrollToItem(index)
                withFrameNanos { }
                // Посередине экрана: перевёрнутый список ставит строку к низу, сдвиг назад — на
                // половину оставшейся высоты.
                val viewport = list.layoutInfo.viewportSize.height
                val size = list.layoutInfo.visibleItemsInfo.firstOrNull { it.index == index }?.size ?: 0
                val shift = (viewport - size) / 2
                if (shift > 0) list.scrollBy(-shift.toFloat())
                if (target.highlight) highlight(target.key)
            }
            is ScrollRequest.Target.Place -> {
                val index = items.indexOfFirst { it.key == target.place.key }.takeIf { it >= 0 } ?: return
                list.scrollToItem(index, target.place.offset)
            }
        }
    }

    /** Дальше этого номера строки «вниз» сначала прыгает. */
    private const val FAR_JUMP = 20
    private const val NEAR_BOTTOM = 8
}

/** У низа ленты, если сдвиг первой строки меньше этого (px). */
private const val BOTTOM_SLOP = 8
/** За сколько строк до верха грузится старая страница: заранее, чтобы при быстрой прокрутке
 *  лента не упиралась в верх, пока страница идёт. */
private const val PAGE_TRIGGER = 20
/** За сколько строк до низа окна перехода грузится новая. */
private const val NEWER_TRIGGER = 3
/** Сколько горит подсветка сообщения, к которому перешли. */
private const val HIGHLIGHT_MS = 1_500L
/** Плавающая дата держится после остановки прокрутки. */
private const val DAY_PILL_LINGER_MS = 1_200L
/** «Непрочитанные сообщения» встают на столько ниже верха ленты. */
private val UNREAD_TOP_GAP = 96.dp
