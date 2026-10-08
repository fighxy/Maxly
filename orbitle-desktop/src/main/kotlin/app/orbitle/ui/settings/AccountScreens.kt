package app.orbitle.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BlurOn
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.HourglassEmpty
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Phone
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import app.orbitle.platform.DesktopActions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.orbitle.domain.Account
import app.orbitle.domain.BlockedUser
import app.orbitle.domain.InactiveTtl
import app.orbitle.presentation.auth.PhoneNumber
import app.orbitle.presentation.chatlist.ChatAvatar
import app.orbitle.presentation.settings.AccountSettingsViewModel
import app.orbitle.presentation.settings.GhostModeViewModel
import app.orbitle.presentation.settings.PrivacyText
import app.orbitle.ui.components.Avatar
import kotlinx.coroutines.launch

/** Аватар своего профиля по [Account]. */
@Composable
fun AccountAvatar(account: Account?, size: androidx.compose.ui.unit.Dp) {
    val name = account?.displayName.orEmpty()
    val id = account?.id.orEmpty()
    val initials = ChatAvatar.initials(name.ifEmpty { "?" })
    val avatar = account?.avatarUrl?.let { ChatAvatar(ChatAvatar.Kind.Photo(it, initials), ChatAvatar.colorIndex(id)) }
        ?: ChatAvatar(ChatAvatar.Kind.Initials(initials), ChatAvatar.colorIndex(id))
    Avatar(avatar, size)
}

@Composable
private fun ErrorDialog(model: AccountSettingsViewModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val error = state.error ?: return
    AlertDialog(
        onDismissRequest = model::dismissError,
        text = { Text(error) },
        confirmButton = { TextButton(onClick = model::dismissError) { Text("OK") } },
    )
}

/** «Изменить профиль»: фото, имя, фамилия, «О себе». */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileEditScreen(model: AccountSettingsViewModel, onBack: () -> Unit, onLogout: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    val account = state.account
    val scope = rememberCoroutineScope()
    // Поля заполняются один раз, когда профиль известен, и дальше не перезаписываются.
    var first by rememberSaveable { mutableStateOf<String?>(null) }
    var last by rememberSaveable { mutableStateOf("") }
    var about by rememberSaveable { mutableStateOf("") }
    LaunchedEffect(account?.id) {
        if (first == null && account != null) {
            first = account.firstName
            last = account.lastName
            about = account.description.orEmpty()
        }
    }
    val pickPhoto = app.orbitle.platform.rememberDesktopFilePicker(
        title = "Выберите изображение",
        imageOnly = true,
    ) { files ->
        val file = files.firstOrNull() ?: return@rememberDesktopFilePicker
        scope.launch {
            val jpeg = AvatarImage.jpeg(file)
            if (jpeg != null) model.uploadPhoto(jpeg) else model.photoUnreadable()
        }
    }
    var menu by remember { mutableStateOf(false) }
    var deletion by rememberSaveable { mutableStateOf(DeletionStep.NONE) }
    val changed = account != null && first != null &&
        (first!!.trim() != account.firstName || last.trim() != account.lastName || about.trim() != account.description.orEmpty())
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Профиль") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
                actions = {
                    if (state.saving) {
                        CircularProgressIndicator(Modifier.padding(12.dp).size(24.dp), strokeWidth = 2.dp)
                    } else {
                        IconButton(onClick = { model.saveProfile(first.orEmpty(), last, about, onSaved = onBack) }, enabled = changed) {
                            Icon(Icons.Filled.Check, "Сохранить")
                        }
                    }
                    IconButton(onClick = { deletion = DeletionStep.WARNING }, enabled = !state.deleting) {
                        Icon(Icons.Outlined.Delete, "Удалить профиль", tint = MaterialTheme.colorScheme.error)
                    }
                },
            )
        },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(16.dp))
            Box {
                Box(Modifier.clickable(enabled = !state.updatingPhoto) { menu = true }) {
                    AccountAvatar(account, 112.dp)
                    Box(
                        Modifier.align(Alignment.BottomEnd).size(36.dp).background(MaterialTheme.colorScheme.primary, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (state.updatingPhoto) {
                            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                        } else {
                            Icon(Icons.Outlined.CameraAlt, "Изменить фото", tint = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.size(20.dp))
                        }
                    }
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(
                        text = { Text("Выбрать фото") },
                        leadingIcon = { Icon(Icons.Outlined.Image, null) },
                        onClick = {
                            menu = false
                            pickPhoto()
                        },
                    )
                    if (account?.hasPhoto == true) {
                        DropdownMenuItem(
                            text = { Text("Удалить фото", color = MaterialTheme.colorScheme.error) },
                            leadingIcon = { Icon(Icons.Outlined.Delete, null, tint = MaterialTheme.colorScheme.error) },
                            onClick = {
                                menu = false
                                model.removePhoto()
                            },
                        )
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
            OutlinedTextField(
                value = first.orEmpty(),
                onValueChange = { first = it.take(AccountSettingsViewModel.NAME_LIMIT) },
                label = { Text("Имя") },
                singleLine = true,
                isError = first != null && first!!.isBlank(),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = last,
                onValueChange = { last = it.take(AccountSettingsViewModel.NAME_LIMIT) },
                label = { Text("Фамилия") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = about,
                onValueChange = { about = it.take(AccountSettingsViewModel.ABOUT_LIMIT) },
                label = { Text("О себе") },
                minLines = 2,
                maxLines = 6,
                supportingText = { Text("${about.length} из ${AccountSettingsViewModel.ABOUT_LIMIT}", Modifier.fillMaxWidth(), textAlign = TextAlign.End) },
                modifier = Modifier.fillMaxWidth(),
            )
            account?.phone?.let {
                ListItem(
                    leadingContent = { Icon(Icons.Outlined.Phone, null) },
                    headlineContent = { Text(PhoneNumber.display(it)) },
                    supportingContent = { Text("Номер телефона здесь не меняется") },
                    colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
                )
            }
            Spacer(Modifier.height(24.dp))
        }
    }
    ErrorDialog(model)
    DeleteProfileDialogs(model, deletion, onStep = { deletion = it }, onLogout = onLogout)
}

private enum class DeletionStep { NONE, WARNING, TYPING }

/**
 * Удаление профиля, как в приложении для iOS: предупреждение, затем слово «УДАЛИТЬ»
 * и только после ответа сервера — сообщение о дате и выход из аккаунта.
 */
@Composable
private fun DeleteProfileDialogs(
    model: AccountSettingsViewModel,
    step: DeletionStep,
    onStep: (DeletionStep) -> Unit,
    onLogout: () -> Unit,
) {
    val state by model.state.collectAsStateWithLifecycle()
    state.deleted?.let { deleted ->
        val leave = { model.finishDeletion(onLogout) }
        AlertDialog(
            onDismissRequest = leave,
            title = { Text("Профиль будет удалён") },
            text = { Text(AccountSettingsViewModel.deletionMessage(deleted.at)) },
            confirmButton = { TextButton(onClick = leave) { Text("OK") } },
        )
        return
    }
    when (step) {
        DeletionStep.NONE -> Unit
        DeletionStep.WARNING -> AlertDialog(
            onDismissRequest = { onStep(DeletionStep.NONE) },
            title = { Text("Удалить профиль?") },
            text = { Text("Профиль будет удалён безвозвратно через 30 дней. Если за это время войти снова, удаление отменится.") },
            confirmButton = {
                TextButton(onClick = {
                    model.dismissDeletionError()
                    onStep(DeletionStep.TYPING)
                }) { Text("Продолжить", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { onStep(DeletionStep.NONE) }) { Text("Отмена") } },
        )
        DeletionStep.TYPING -> {
            var word by rememberSaveable { mutableStateOf("") }
            val close = {
                if (!state.deleting) {
                    model.dismissDeletionError()
                    onStep(DeletionStep.NONE)
                }
            }
            val confirmed = AccountSettingsViewModel.isDeleteKeyword(word)
            AlertDialog(
                onDismissRequest = close,
                title = { Text("Подтвердите удаление") },
                text = {
                    Column {
                        Text("Введите слово «${AccountSettingsViewModel.DELETE_KEYWORD}», чтобы удалить профиль.")
                        Spacer(Modifier.height(12.dp))
                        OutlinedTextField(
                            value = word,
                            onValueChange = {
                                word = it
                                model.dismissDeletionError()
                            },
                            placeholder = { Text(AccountSettingsViewModel.DELETE_KEYWORD) },
                            singleLine = true,
                            enabled = !state.deleting,
                            isError = state.deletionError != null,
                            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, imeAction = ImeAction.Done),
                            keyboardActions = KeyboardActions(onDone = { if (confirmed) model.deleteAccount(word) }),
                            modifier = Modifier.fillMaxWidth(),
                        )
                        state.deletionError?.let {
                            Spacer(Modifier.height(8.dp))
                            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                },
                confirmButton = {
                    if (state.deleting) {
                        CircularProgressIndicator(Modifier.padding(12.dp).size(24.dp), strokeWidth = 2.dp)
                    } else {
                        TextButton(onClick = { model.deleteAccount(word) }, enabled = confirmed) {
                            Text("Удалить профиль", color = if (confirmed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f))
                        }
                    }
                },
                dismissButton = { TextButton(onClick = close, enabled = !state.deleting) { Text("Отмена") } },
            )
        }
    }
}

/**
 * «Конфиденциальность»: вверху блок «Дополнительно» с режимом призрака ([ghost], `null` — без него),
 * дальше настройки MAX ([MaxPrivacySection]: безопасный режим, поиск по номеру, звонки,
 * приглашения, контент, «Информация»), приватный режим, чёрный список со счётчиком и срок
 * неактивности. Пароль, семейная защита и устройства — на своих экранах.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PrivacyScreen(
    model: AccountSettingsViewModel,
    onBack: () -> Unit,
    onBlocked: () -> Unit,
    privateMode: app.orbitle.data.PrivateModeSettings? = null,
    ghost: GhostModeViewModel? = null,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val settings = state.settings
    var dialog by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { model.countBlocked() }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Конфиденциальность") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
            )
        },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())) {
            ghost?.let {
                GhostModeSection(it)
                HorizontalDivider(Modifier.padding(vertical = 4.dp))
            }
            if (!settings.known) {
                Text(
                    "Настройки загрузятся после подключения к серверу",
                    Modifier.padding(16.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            val enabled = settings.known
            MaxPrivacySection(model)
            privateMode?.let {
                HorizontalDivider(Modifier.padding(vertical = 4.dp))
                PrivateModeSection(it) { dialog = "privateStyle" }
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            SettingsItem(
                Icons.Outlined.Block,
                PrivacyText.BLACKLIST,
                subtitle = PrivacyText.BLACKLIST_DESCRIPTION,
                trailing = state.blocked?.let { { Text(it.size.toString(), color = MaterialTheme.colorScheme.onSurfaceVariant) } },
                onClick = onBlocked,
            )
            SettingsItem(
                Icons.Outlined.HourglassEmpty,
                "Удалить аккаунт, если меня нет",
                subtitle = settings.inactiveTtl.title,
                enabled = enabled,
            ) { dialog = "ttl" }
        }
    }
    when (dialog) {
        "privateStyle" -> privateMode?.let { settings ->
            val prefs by settings.state.collectAsStateWithLifecycle()
            ChoiceDialog("Вид", app.orbitle.domain.PrivateModeStyle.entries, prefs.style, { it.title }, { dialog = null }) {
                settings.setStyle(it)
            }
        }
        "ttl" -> ChoiceDialog("Удалить аккаунт, если меня нет", InactiveTtl.entries, settings.inactiveTtl, { it.title }, { dialog = null }) {
            model.setInactiveTtl(it)
        }
    }
    ErrorDialog(model)
}

@Composable
private fun <T> ChoiceDialog(title: String, options: List<T>, selected: T, label: (T) -> String, onDismiss: () -> Unit, onPick: (T) -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                options.forEach { option ->
                    Row(
                        Modifier.fillMaxWidth()
                            .selectable(option == selected, role = Role.RadioButton) {
                                onDismiss()
                                onPick(option)
                            }
                            .padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(option == selected, onClick = null)
                        Spacer(Modifier.size(12.dp))
                        Text(label(option), style = MaterialTheme.typography.bodyLarge)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}

/** «Чёрный список»: заблокированные пользователи и разблокировка. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BlockedUsersScreen(model: AccountSettingsViewModel, onBack: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    var confirm by remember { mutableStateOf<BlockedUser?>(null) }
    LaunchedEffect(Unit) { model.loadBlocked() }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Чёрный список") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
            )
        },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        val list = state.blocked
        when {
            list == null -> Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            list.isEmpty() -> Column(
                Modifier.padding(padding).fillMaxSize().padding(32.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(Icons.Outlined.Block, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(12.dp))
                Text("Список пуст", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(4.dp))
                Text(
                    "Заблокированные не смогут писать и звонить вам",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
            else -> LazyColumn(Modifier.padding(padding).fillMaxSize()) {
                items(list, key = { it.id }) { user ->
                    val initials = ChatAvatar.initials(user.name)
                    val avatar = user.avatarUrl?.let { ChatAvatar(ChatAvatar.Kind.Photo(it, initials), ChatAvatar.colorIndex(user.id)) }
                        ?: ChatAvatar(ChatAvatar.Kind.Initials(initials), ChatAvatar.colorIndex(user.id))
                    ListItem(
                        leadingContent = { Avatar(avatar, 44.dp) },
                        headlineContent = { Text(user.name) },
                        supportingContent = user.phone?.let { { Text(PhoneNumber.display(it)) } },
                        trailingContent = { TextButton(onClick = { confirm = user }) { Text("Разблокировать") } },
                        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
                    )
                }
            }
        }
    }
    confirm?.let { user ->
        AlertDialog(
            onDismissRequest = { confirm = null },
            title = { Text("Разблокировать ${user.name}?") },
            text = { Text("Пользователь снова сможет писать и звонить вам.") },
            confirmButton = {
                TextButton(onClick = {
                    confirm = null
                    model.unblock(user)
                }) { Text("Разблокировать") }
            },
            dismissButton = { TextButton(onClick = { confirm = null }) { Text("Отмена") } },
        )
    }
    ErrorDialog(model)
}

/** Приватный режим: только на этом устройстве, в протокол не уходит. */
@Composable
private fun PrivateModeSection(settings: app.orbitle.data.PrivateModeSettings, onStyle: () -> Unit) {
    val prefs by settings.state.collectAsStateWithLifecycle()
    Text(
        "Приватный режим",
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, top = 12.dp, bottom = 4.dp),
    )
    ListItem(
        leadingContent = { Icon(Icons.Outlined.VisibilityOff, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
        headlineContent = { Text("Приватный режим") },
        supportingContent = { Text("Прячет названия чатов, аватары и тексты сообщений") },
        trailingContent = { Switch(prefs.enabled, onCheckedChange = settings::setEnabled) },
        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
        modifier = Modifier.clickable { settings.setEnabled(!prefs.enabled) },
    )
    if (prefs.enabled) {
        SettingsItem(Icons.Outlined.BlurOn, "Вид", subtitle = prefs.style.title, onClick = onStyle)
    }
    ListItem(
        leadingContent = { Icon(Icons.Outlined.Visibility, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
        headlineContent = { Text("Кнопка в списке чатов") },
        trailingContent = { Switch(prefs.quickToggle, onCheckedChange = settings::setQuickToggle) },
        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
        modifier = Modifier.clickable { settings.setQuickToggle(!prefs.quickToggle) },
    )
    Text(
        "Сообщение открывается касанием на 15 секунд. Настройка действует только на этом устройстве, уведомления не меняются.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
}
