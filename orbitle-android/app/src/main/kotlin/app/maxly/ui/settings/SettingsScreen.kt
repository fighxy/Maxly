package app.maxly.ui.settings

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.Row
import androidx.compose.material.icons.outlined.Badge
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.School
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.outlined.Contacts
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.foundation.layout.Box
import androidx.compose.ui.draw.clip
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.remember
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material.icons.outlined.QrCode2
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.maxly.BuildConfig
import app.maxly.R
import app.maxly.domain.Account
import app.maxly.domain.AccountLimits
import app.maxly.presentation.settings.AccountLimitsText
import app.maxly.presentation.settings.GhostModeViewModel
import app.maxly.ui.auth.AccountLimitsNotice
import app.maxly.presentation.auth.PhoneNumber

/** Шапка профиля и пункты настроек. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    account: Account?,
    onAbout: () -> Unit,
    onLogout: () -> Unit,
    onSaved: () -> Unit = {},
    onContacts: () -> Unit = {},
    onDevices: () -> Unit = {},
    onAppearance: () -> Unit = {},
    onEditProfile: () -> Unit = {},
    onPrivacy: () -> Unit = {},
    onSecurity: () -> Unit = {},
    onStorage: () -> Unit = {},
    onFolders: () -> Unit = {},
    /** «Мои истории»; `null` — пункта нет (сервер не включил `stories-history`). */
    onMyStories: (() -> Unit)? = null,
    onMessages: () -> Unit = {},
    onDigitalId: () -> Unit = {},
    onSferum: () -> Unit = {},
    /** Ссылка на свой профиль для QR и приглашения; `null` — сервер её ещё не дал. */
    profileLink: String? = null,
    /** Отметка нового сеанса: пока ограничения входа действуют, вверху видна строка о них. */
    accountLimits: AccountLimits? = null,
    /** Свой статус под номером («Показывать мой онлайн»); `null` — без него. */
    ghost: GhostModeViewModel? = null,
) {
    var confirm by rememberSaveable { mutableStateOf(false) }
    var sheet by rememberSaveable { mutableStateOf<String?>(null) }
    val limitsText = remember { AccountLimitsText() }
    val now = System.currentTimeMillis()
    val limitsRow = limitsText.row(accountLimits, now)
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings_title)) },
                actions = {
                    if (profileLink != null) {
                        IconButton(onClick = { sheet = "qr" }) { Icon(Icons.Outlined.QrCode2, "QR-код профиля") }
                    }
                    IconButton(onClick = onEditProfile) { Icon(Icons.Outlined.Edit, "Изменить профиль") }
                },
            )
        },
        contentWindowInsets = androidx.compose.foundation.layout.WindowInsets(0),
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())) {
            ProfileHeader(account, onEditProfile, ghost)
            if (limitsRow != null) {
                SettingsItem(Icons.Outlined.Timer, limitsRow.title, subtitle = limitsRow.subtitle) { sheet = "limits" }
            }
            SettingsItem(Icons.Outlined.Edit, "Изменить профиль", onClick = onEditProfile)
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            SettingsItem(Icons.Outlined.Badge, "Цифровой ID", onClick = onDigitalId)
            SettingsItem(Icons.Outlined.School, "Войти в Сферум", onClick = onSferum)
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            SettingsItem(Icons.Outlined.Notifications, "Уведомления и звук", subtitle = "Скоро", enabled = false) {}
            SettingsItem(Icons.Outlined.Key, "Безопасность", onClick = onSecurity)
            SettingsItem(Icons.Outlined.Lock, "Конфиденциальность", onClick = onPrivacy)
            SettingsItem(Icons.Outlined.Devices, "Устройства", onClick = onDevices)
            SettingsItem(Icons.Outlined.Storage, "Данные и память", onClick = onStorage)
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            SettingsItem(Icons.AutoMirrored.Outlined.Chat, "Сообщения", onClick = onMessages)
            SettingsItem(Icons.Outlined.BookmarkBorder, "Избранное", onClick = onSaved)
            if (onMyStories != null) {
                SettingsItem(Icons.Outlined.History, "Мои истории", onClick = onMyStories)
            }
            SettingsItem(Icons.Outlined.Contacts, "Контакты", onClick = onContacts)
            SettingsItem(Icons.Outlined.Folder, "Папки", onClick = onFolders)
            SettingsItem(Icons.Outlined.Palette, "Оформление", onClick = onAppearance)
            if (profileLink != null) {
                SettingsItem(Icons.Outlined.PersonAdd, "Пригласить друзей") { sheet = "invite" }
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            SettingsItem(
                Icons.Outlined.Info,
                stringResource(R.string.settings_about),
                trailing = { Text(BuildConfig.VERSION_NAME, color = MaterialTheme.colorScheme.onSurfaceVariant) },
                onClick = onAbout,
            )
            SettingsItem(Icons.AutoMirrored.Filled.Logout, stringResource(R.string.settings_logout), destructive = true) { confirm = true }
        }
    }
    if (sheet == "limits" && accountLimits != null) {
        AccountLimitsNotice(limitsText.content(accountLimits, now)) { sheet = null }
    }
    if (profileLink != null) {
        when (sheet) {
            "qr" -> ProfileQrSheet(profileLink, "Мой профиль", invite = false) { sheet = null }
            "invite" -> ProfileQrSheet(profileLink, "Пригласить друзей", invite = true) { sheet = null }
        }
    }
    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text(stringResource(R.string.settings_logout_confirm_title)) },
            text = { Text(stringResource(R.string.settings_logout_confirm_text)) },
            confirmButton = {
                TextButton(onClick = {
                    confirm = false
                    onLogout()
                }) { Text(stringResource(R.string.settings_logout), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text(stringResource(R.string.settings_cancel)) } },
        )
    }
}

@Composable
private fun ProfileHeader(account: Account?, onEdit: () -> Unit, ghost: GhostModeViewModel?) {
    Column(Modifier.fillMaxWidth().padding(vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        val name = account?.displayName.orEmpty()
        Box(Modifier.clip(CircleShape).clickable(onClick = onEdit)) { AccountAvatar(account, 96.dp) }
        Spacer(Modifier.height(12.dp))
        Text(name.ifEmpty { " " }, style = MaterialTheme.typography.headlineSmall)
        account?.description?.let {
            Spacer(Modifier.height(4.dp))
            Text(
                it,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                maxLines = 3,
                modifier = Modifier.padding(horizontal = 32.dp),
            )
        }
        account?.phone?.let {
            // Номер скрыт при каждом открытии вкладки, глаз показывает его.
            var shown by remember { mutableStateOf(false) }
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    if (shown) PhoneNumber.display(it) else maskedPhone(it),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                IconButton(onClick = { shown = !shown }) {
                    Icon(if (shown) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility, if (shown) "Скрыть номер" else "Показать номер", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        ghost?.let { OwnPresenceLine(it) }
    }
}

/** `+7 ••• ••• •• ••`: код страны виден, остальное скрыто. */
fun maskedPhone(phone: String): String {
    val digits = phone.filter { it.isDigit() }
    val code = if (digits.startsWith("7") || digits.length <= 10) digits.take(1) else digits.take(digits.length - 10)
    return "+$code ••• ••• •• ••"
}

@Composable
fun SettingsItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String? = null,
    destructive: Boolean = false,
    enabled: Boolean = true,
    trailing: (@Composable () -> Unit)? = null,
    onClick: () -> Unit,
) {
    val color = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
    ListItem(
        headlineContent = { Text(title, color = color) },
        supportingContent = subtitle?.let { { Text(it) } },
        leadingContent = { Icon(icon, null, tint = if (destructive) color else MaterialTheme.colorScheme.onSurfaceVariant) },
        trailingContent = trailing,
        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
        modifier = Modifier.clickable(enabled = enabled, onClick = onClick).alpha(if (enabled) 1f else 0.5f),
    )
}

/** «О приложении»: версия, сборка, ревизия ядра, журнал и отчёты о сбоях. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings_about)) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.auth_back)) }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(24.dp))
            Image(
                painterResource(R.drawable.maxly_mark),
                contentDescription = null,
                modifier = Modifier.size(96.dp).background(MaterialTheme.colorScheme.primary, CircleShape).padding(12.dp),
                colorFilter = ColorFilter.tint(MaterialTheme.colorScheme.onPrimary),
            )
            Spacer(Modifier.height(12.dp))
            Text(stringResource(R.string.app_name), style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.height(8.dp))
            Text(
                stringResource(R.string.about_text),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 32.dp),
            )
            Spacer(Modifier.height(16.dp))
            ListItem(headlineContent = { Text(stringResource(R.string.about_version)) }, trailingContent = { Text(BuildConfig.VERSION_NAME) })
            ListItem(headlineContent = { Text(stringResource(R.string.about_build)) }, trailingContent = { Text(BuildConfig.BUILD_SHA) })
            ListItem(headlineContent = { Text(stringResource(R.string.about_core)) }, trailingContent = { Text(BuildConfig.CORE_REVISION) })
            ListItem(
                headlineContent = { Text(stringResource(R.string.about_source)) },
                leadingContent = { Icon(Icons.Outlined.Code, null) },
                supportingContent = { Text("github.com/fighxy/Orbitle") },
                modifier = Modifier.clickable {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/fighxy/Orbitle")))
                },
            )
            DiagnosticsSection()
            Spacer(Modifier.height(24.dp))
        }
    }
}
