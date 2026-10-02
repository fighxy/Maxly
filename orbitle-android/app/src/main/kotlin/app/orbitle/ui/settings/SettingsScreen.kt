package app.orbitle.ui.settings

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
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
import app.orbitle.BuildConfig
import app.orbitle.R
import app.orbitle.domain.Account
import app.orbitle.presentation.auth.PhoneNumber
import app.orbitle.presentation.chatlist.ChatAvatar
import app.orbitle.ui.components.Avatar

/** Шапка профиля и пункты настроек. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(account: Account?, onAbout: () -> Unit, onLogout: () -> Unit) {
    var confirm by rememberSaveable { mutableStateOf(false) }
    Scaffold(
        topBar = { TopAppBar(title = { Text(stringResource(R.string.settings_title)) }) },
        contentWindowInsets = androidx.compose.foundation.layout.WindowInsets(0),
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())) {
            ProfileHeader(account)
            Spacer(Modifier.height(8.dp))
            SettingsItem(Icons.Outlined.Info, stringResource(R.string.settings_about), onClick = onAbout)
            SettingsItem(Icons.AutoMirrored.Filled.Logout, stringResource(R.string.settings_logout), destructive = true) { confirm = true }
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
private fun ProfileHeader(account: Account?) {
    Column(Modifier.fillMaxWidth().padding(vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        val name = account?.displayName.orEmpty()
        val id = account?.id.orEmpty()
        val initials = ChatAvatar.initials(name.ifEmpty { "?" })
        val avatar = account?.avatarUrl?.let { ChatAvatar(ChatAvatar.Kind.Photo(it, initials), ChatAvatar.colorIndex(id)) }
            ?: ChatAvatar(ChatAvatar.Kind.Initials(initials), ChatAvatar.colorIndex(id))
        Avatar(avatar, 96.dp)
        Spacer(Modifier.height(12.dp))
        Text(name.ifEmpty { " " }, style = MaterialTheme.typography.headlineSmall)
        account?.phone?.let {
            Spacer(Modifier.height(4.dp))
            Text(PhoneNumber.display(it), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
fun SettingsItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String? = null,
    destructive: Boolean = false,
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
        modifier = Modifier.clickable(onClick = onClick),
    )
}

/** «О приложении»: версия, сборка, ревизия ядра. */
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
                painterResource(R.drawable.orbitle_mark),
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
        }
    }
}
