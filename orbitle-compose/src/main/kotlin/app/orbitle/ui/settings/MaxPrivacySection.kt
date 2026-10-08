package app.orbitle.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Call
import androidx.compose.material.icons.outlined.FilterAlt
import androidx.compose.material.icons.outlined.GroupAdd
import androidx.compose.material.icons.outlined.PersonSearch
import androidx.compose.material.icons.outlined.Phone
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.orbitle.domain.PrivacyAccess
import app.orbitle.presentation.settings.AccountSettingsViewModel
import app.orbitle.presentation.settings.PrivacyText

/**
 * Настройки приватности MAX, как в его разделе «Безопасность»: безопасный режим и четыре пункта
 * под ним (пока режим включён, они заперты и показывают его значения), затем «Информация» —
 * статус «в сети» и номер. Пока конфиг не пришёл, всё неактивно.
 */
@Composable
fun MaxPrivacySection(model: AccountSettingsViewModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val settings = state.settings
    val known = settings.known
    val open = known && !settings.lockedBySafeMode
    var dialog by rememberSaveable { mutableStateOf<String?>(null) }

    ListItem(
        leadingContent = { Icon(Icons.Outlined.Shield, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
        headlineContent = { Text(PrivacyText.SAFE_MODE) },
        supportingContent = { Text(PrivacyText.SAFE_MODE_DESCRIPTION) },
        trailingContent = { Switch(settings.safeMode, onCheckedChange = model::setSafeMode, enabled = known) },
        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
        modifier = Modifier.clickable(enabled = known) { model.setSafeMode(!settings.safeMode) },
    )
    PrivacyRow(Icons.Outlined.PersonSearch, PrivacyText.SEARCH_BY_PHONE, settings.shownSearchByPhone.title, open) { dialog = "search" }
    PrivacyRow(Icons.Outlined.Call, PrivacyText.INCOMING_CALL, settings.shownIncomingCalls.title, open) { dialog = "call" }
    PrivacyRow(Icons.Outlined.GroupAdd, PrivacyText.CHATS_INVITE, settings.shownChatInvites.title, open) { dialog = "invite" }
    PrivacyRow(Icons.Outlined.FilterAlt, PrivacyText.CONTENT, PrivacyText.content(settings.shownSafeContentOnly), open) { dialog = "content" }
    if (settings.lockedBySafeMode) {
        Text(
            PrivacyText.SAFE_MODE_LOCK,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
    }
    HorizontalDivider(Modifier.padding(vertical = 4.dp))
    Text(
        PrivacyText.INFORMATION,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, top = 12.dp, bottom = 4.dp),
    )
    PrivacyRow(Icons.Outlined.Visibility, PrivacyText.ONLINE, PrivacyText.online(settings.onlineHidden), known) { dialog = "online" }
    PrivacyRow(Icons.Outlined.Phone, PrivacyText.PHONE, settings.phonePrivacy.title, known) { dialog = "phone" }

    val close = { dialog = null }
    when (dialog) {
        "search" -> Choice(PrivacyText.SEARCH_BY_PHONE, PrivacyText.SEARCH_BY_PHONE_DESCRIPTION, PrivacyText.twoWay, settings.searchByPhone, { it.title }, close, PrivacyText::searchByPhoneHint, model::setSearchByPhone)
        "call" -> Choice(PrivacyText.INCOMING_CALL, PrivacyText.INCOMING_CALL_DESCRIPTION, PrivacyText.twoWay, settings.incomingCalls, { it.title }, close, onPick = model::setIncomingCalls)
        "invite" -> Choice(PrivacyText.CHATS_INVITE, PrivacyText.CHATS_INVITE_DESCRIPTION, PrivacyText.twoWay, settings.chatInvites, { it.title }, close, onPick = model::setChatInvites)
        "content" -> Choice(PrivacyText.CONTENT, PrivacyText.CONTENT_DESCRIPTION, listOf(false, true), settings.safeContentOnly, PrivacyText::content, close, onPick = model::setSafeContentOnly)
        "online" -> Choice(PrivacyText.ONLINE, PrivacyText.ONLINE_DESCRIPTION, listOf(false, true), settings.onlineHidden, PrivacyText::online, close, onPick = model::setOnlineHidden)
        "phone" -> Choice(PrivacyText.PHONE, PrivacyText.PHONE_DESCRIPTION, PrivacyAccess.entries, settings.phonePrivacy, { it.title }, close, onPick = model::setPhonePrivacy)
    }
}

@Composable
private fun PrivacyRow(icon: ImageVector, title: String, value: String, enabled: Boolean, onClick: () -> Unit) {
    ListItem(
        leadingContent = { Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
        headlineContent = { Text(title) },
        supportingContent = { Text(value) },
        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
        modifier = Modifier.clickable(enabled = enabled, onClick = onClick).alpha(if (enabled) 1f else 0.5f),
    )
}

/** Список вариантов с описанием пункта сверху; [hint] — пояснение под вариантом. */
@Composable
private fun <T> Choice(
    title: String,
    description: String,
    options: List<T>,
    selected: T,
    label: (T) -> String,
    onDismiss: () -> Unit,
    hint: (T) -> String? = { null },
    onPick: (T) -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                Text(description, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.size(8.dp))
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
                        Column {
                            Text(label(option), style = MaterialTheme.typography.bodyLarge)
                            hint(option)?.let {
                                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}
