package app.maxly.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.AlternateEmail
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.domain.TwoFactorStatus
import app.maxly.presentation.settings.AccountSettingsViewModel
import app.maxly.presentation.settings.RecoveryEmailViewModel
import app.maxly.presentation.settings.SecurityViewModel
import kotlinx.coroutines.delay

/**
 * «Безопасность»: облачный пароль и почта восстановления, статус семейной защиты из настроек
 * аккаунта [account] (только чтение: здесь она не включается).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SecurityScreen(
    model: SecurityViewModel,
    onBack: () -> Unit,
    onChangeEmail: () -> Unit,
    account: AccountSettingsViewModel,
    /** Касание «Семейной защиты»: мини-приложение бота из конфига (его id). */
    onFamilyProtection: (String) -> Unit = {},
) {
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { model.load() }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Безопасность") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
            )
        },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())) {
            ListItem(
                leadingContent = { Icon(Icons.Outlined.Key, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
                headlineContent = { Text("Пароль для входа") },
                trailingContent = {
                    when {
                        state.loading && state.status == null -> CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        state.status != null -> Text(
                            if (state.status!!.isEnabled) "Включён" else "Выключен",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        else -> Text("Неизвестно", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
            )
            val status = state.status
            if (status != null && status.isEnabled) {
                val masked = model.maskedEmail
                if (masked != null) {
                    SettingsItem(
                        Icons.Outlined.AlternateEmail,
                        "Почта для восстановления",
                        subtitle = "Изменить",
                        trailing = { Text(masked, color = MaterialTheme.colorScheme.onSurfaceVariant) },
                        onClick = onChangeEmail,
                    )
                } else {
                    SettingsItem(Icons.Outlined.AlternateEmail, "Укажите почту для восстановления", onClick = onChangeEmail)
                }
            }
            val footer = when {
                state.failure != null -> state.failure
                status != null && !status.isEnabled -> "Пароль защищает вход с нового устройства."
                status != null -> "Почта нужна, чтобы восстановить доступ, если вы забудете пароль."
                else -> null
            }
            if (footer != null) {
                Text(
                    footer,
                    Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (status != null && state.form == SecurityViewModel.PasswordForm.NONE) {
                if (!status.isEnabled) {
                    TextButton(onClick = { model.openForm(SecurityViewModel.PasswordForm.ENABLE) }, modifier = Modifier.padding(horizontal = 8.dp)) {
                        Text("Включить пароль")
                    }
                } else {
                    TextButton(onClick = { model.openForm(SecurityViewModel.PasswordForm.CHANGE) }, modifier = Modifier.padding(horizontal = 8.dp)) {
                        Text("Сменить пароль")
                    }
                    TextButton(onClick = { model.openForm(SecurityViewModel.PasswordForm.DISABLE) }, modifier = Modifier.padding(horizontal = 8.dp)) {
                        Text("Выключить пароль")
                    }
                }
            }
            state.notice?.let {
                Text(it, Modifier.padding(horizontal = 16.dp, vertical = 4.dp), color = MaterialTheme.colorScheme.primary)
            }
            if (state.form != SecurityViewModel.PasswordForm.NONE) {
                PasswordEditor(state.form, state.working, state.formError, model)
            }
            if (state.failure != null) {
                TextButton(onClick = { model.load() }, modifier = Modifier.padding(horizontal = 8.dp)) { Text("Повторить") }
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            FamilyProtectionRow(account, onOpen = onFamilyProtection)
        }
    }
}

@Composable
private fun PasswordEditor(
    form: SecurityViewModel.PasswordForm,
    working: Boolean,
    error: String?,
    model: SecurityViewModel,
) {
    var first by rememberSaveable(form) { mutableStateOf("") }
    var second by rememberSaveable(form) { mutableStateOf("") }
    Column(Modifier.padding(horizontal = 16.dp)) {
        when (form) {
            SecurityViewModel.PasswordForm.NONE -> Unit
            SecurityViewModel.PasswordForm.ENABLE -> {
                SecretField(first, { first = it }, "Пароль")
                OutlinedTextField(
                    value = second,
                    onValueChange = { second = it },
                    label = { Text("Подсказка") },
                    supportingText = { Text("Можно не заполнять. Почта задаётся отдельно.") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                )
                Button(onClick = { model.enablePassword(first, second) }, enabled = !working, modifier = Modifier.padding(top = 8.dp)) {
                    Text("Включить")
                }
            }
            SecurityViewModel.PasswordForm.CHANGE -> {
                SecretField(first, { first = it }, "Текущий пароль")
                SecretField(second, { second = it }, "Новый пароль")
                Button(onClick = { model.changePassword(first, second) }, enabled = !working, modifier = Modifier.padding(top = 8.dp)) {
                    Text("Сменить")
                }
            }
            SecurityViewModel.PasswordForm.DISABLE -> {
                SecretField(first, { first = it }, "Пароль")
                Button(onClick = { model.disablePassword(first) }, enabled = !working, modifier = Modifier.padding(top = 8.dp)) {
                    Text("Выключить")
                }
            }
        }
        if (working) {
            CircularProgressIndicator(Modifier.padding(top = 8.dp).size(18.dp), strokeWidth = 2.dp)
        }
        error?.let {
            Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp))
        }
        TextButton(onClick = model::closeForm, enabled = !working) { Text("Отмена") }
    }
}

@Composable
private fun SecretField(value: String, onValue: (String) -> Unit, label: String) {
    OutlinedTextField(
        value = value,
        onValueChange = onValue,
        label = { Text(label) },
        singleLine = true,
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
    )
}

/** Смена почты: пароль, адрес, код из письма. По «Готово» на последнем шаге вызывается [onDone]. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecoveryEmailScreen(model: RecoveryEmailViewModel, onBack: () -> Unit, onDone: (TwoFactorStatus) -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    var password by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }
    var code by rememberSaveable { mutableStateOf("") }
    var nowMs by rememberSaveable { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(state.step) {
        val done = state.step as? RecoveryEmailViewModel.Step.Done ?: return@LaunchedEffect
        onDone(done.status)
    }
    LaunchedEffect(state.resendAvailableAt) {
        while (model.resendWaitSeconds(System.currentTimeMillis()) > 0) {
            nowMs = System.currentTimeMillis()
            delay(1000)
        }
        nowMs = System.currentTimeMillis()
    }
    val step = state.step
    val canSubmit = when (step) {
        RecoveryEmailViewModel.Step.Password -> password.isNotEmpty()
        RecoveryEmailViewModel.Step.Email -> email.isNotEmpty()
        is RecoveryEmailViewModel.Step.Code -> code.any { it.isDigit() }
        is RecoveryEmailViewModel.Step.Done -> false
    }
    val title = when (step) {
        RecoveryEmailViewModel.Step.Password -> "Далее"
        RecoveryEmailViewModel.Step.Email -> "Получить код"
        is RecoveryEmailViewModel.Step.Code -> "Готово"
        is RecoveryEmailViewModel.Step.Done -> "Готово"
    }
    fun submit() {
        when (step) {
            RecoveryEmailViewModel.Step.Password -> model.submitPassword(password)
            RecoveryEmailViewModel.Step.Email -> model.submitEmail(email)
            is RecoveryEmailViewModel.Step.Code -> model.submitCode(code)
            is RecoveryEmailViewModel.Step.Done -> Unit
        }
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Почта для восстановления") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
            )
        },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
        ) {
            Spacer(Modifier.height(16.dp))
            when (step) {
                RecoveryEmailViewModel.Step.Password -> {
                    OutlinedTextField(
                        value = password,
                        onValueChange = { password = it },
                        label = { Text("Пароль") },
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        keyboardActions = KeyboardActions(onDone = { if (canSubmit) submit() }),
                        supportingText = { Text("Введите текущий пароль для входа.") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                RecoveryEmailViewModel.Step.Email -> {
                    OutlinedTextField(
                        value = email,
                        onValueChange = { email = it },
                        label = { Text("Почта") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                        keyboardActions = KeyboardActions(onDone = { if (canSubmit) submit() }),
                        supportingText = { Text("На неё придёт код подтверждения.") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                is RecoveryEmailViewModel.Step.Code -> {
                    OutlinedTextField(
                        value = code,
                        onValueChange = { code = it },
                        label = { Text("Код из письма") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        keyboardActions = KeyboardActions(onDone = { if (canSubmit) submit() }),
                        supportingText = { Text("Код отправлен на ${step.email}.") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    val wait = model.resendWaitSeconds(nowMs)
                    TextButton(onClick = { model.resendCode() }, enabled = wait == 0 && !state.working) {
                        Text(if (wait > 0) "Отправить ещё раз через $wait с" else "Отправить код ещё раз")
                    }
                    TextButton(onClick = { model.editEmail() }, enabled = !state.working) { Text("Изменить адрес") }
                }
                is RecoveryEmailViewModel.Step.Done -> {
                    Text("Почта для восстановления сохранена", color = MaterialTheme.colorScheme.primary)
                }
            }
            state.error?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
            }
            Spacer(Modifier.height(16.dp))
            Button(onClick = { submit() }, enabled = canSubmit && !state.working, modifier = Modifier.fillMaxWidth()) {
                if (state.working) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                } else {
                    Text(title)
                }
            }
        }
    }
}
