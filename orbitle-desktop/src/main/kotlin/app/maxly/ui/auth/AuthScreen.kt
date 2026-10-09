package app.maxly.ui.auth

import app.maxly.platform.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import app.maxly.ui.components.AppSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.ColorFilter
import app.maxly.ui.res.painterResource
import app.maxly.ui.res.stringResource
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.R
import app.maxly.presentation.auth.AuthStep
import app.maxly.presentation.auth.AuthUiState
import app.maxly.presentation.auth.AuthViewModel
import app.maxly.presentation.auth.PhoneCountry
import kotlinx.coroutines.delay

/** Вход: номер → код → пароль или регистрация. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuthScreen(viewModel: AuthViewModel) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    BackHandler(enabled = state.canGoBack) { viewModel.backToPhone() }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { if (state.step != AuthStep.Phone) Text(state.title) },
                navigationIcon = {
                    if (state.canGoBack) {
                        IconButton(onClick = viewModel::backToPhone) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.auth_back))
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface),
            )
        },
    ) { padding ->
        AnimatedContent(
            targetState = state.step::class,
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            modifier = Modifier.padding(padding).fillMaxSize().imePadding(),
            label = "authStep",
        ) { step ->
            // Свой экран у каждого шага: поля и фокус не переносятся между шагами.
            key(step) {
                Column(
                    Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                Column(
                    Modifier.widthIn(max = 440.dp).fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    when (state.step) {
                        AuthStep.Phone -> PhoneStep(state, viewModel)
                        is AuthStep.Code -> CodeStep(state, viewModel)
                        is AuthStep.Password -> PasswordStep(state, viewModel)
                        AuthStep.Registration -> RegistrationStep(state, viewModel)
                    }
                    state.errorMessage?.let {
                        Spacer(Modifier.height(16.dp))
                        Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium)
                    }
                }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PhoneStep(state: AuthUiState, viewModel: AuthViewModel) {
    var picker by rememberSaveable { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    Spacer(Modifier.height(24.dp))
    Box(
        Modifier.size(96.dp).background(MaterialTheme.colorScheme.primary, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painterResource(R.drawable.orbitle_mark),
            contentDescription = null,
            modifier = Modifier.size(72.dp),
            colorFilter = ColorFilter.tint(MaterialTheme.colorScheme.onPrimary),
        )
    }
    Spacer(Modifier.height(20.dp))
    Text(stringResource(R.string.auth_welcome_title), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold)
    Spacer(Modifier.height(8.dp))
    Text(
        stringResource(R.string.auth_welcome_subtitle),
        style = MaterialTheme.typography.bodyLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
    )
    val notice = state.notice
    if (notice != null) {
        // Отказ сервера во входе: сначала его текст, иначе свой по причине.
        Spacer(Modifier.height(12.dp))
        Text(notice.title, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center, fontWeight = FontWeight.SemiBold)
        notice.message?.let { Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center) }
    } else if (state.sessionExpired) {
        Spacer(Modifier.height(12.dp))
        Text(stringResource(R.string.auth_session_expired), color = MaterialTheme.colorScheme.error)
    }
    Spacer(Modifier.height(28.dp))
    // Выбор страны: строка как поле, по нажатию — список с поиском.
    androidx.compose.material3.Surface(
        onClick = { picker = true },
        shape = RoundedCornerShape(4.dp),
        border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
        color = MaterialTheme.colorScheme.surface,
        modifier = Modifier.fillMaxWidth().height(56.dp),
    ) {
        Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(state.country?.flag.orEmpty(), fontSize = 22.sp)
            if (state.country != null) Spacer(Modifier.width(12.dp))
            Text(state.countryTitle, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            Icon(Icons.Filled.ArrowDropDown, contentDescription = stringResource(R.string.auth_country))
        }
    }
    Spacer(Modifier.height(12.dp))
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        OutlinedTextField(
            value = "+" + state.countryCode,
            onValueChange = { viewModel.setCountryCode(it) },
            label = { Text(stringResource(R.string.auth_country_code)) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone, imeAction = ImeAction.Next),
            modifier = Modifier.width(96.dp),
        )
        Spacer(Modifier.width(12.dp))
        var field by remember { mutableStateOf(TextFieldValue(state.nationalNumber, TextRange(state.nationalNumber.length))) }
        if (field.text != state.nationalNumber) {
            field = TextFieldValue(state.nationalNumber, TextRange(state.nationalNumber.length))
        }
        OutlinedTextField(
            value = field,
            onValueChange = {
                field = it
                viewModel.setNationalNumber(it.text)
            },
            label = { Text(stringResource(R.string.auth_phone)) },
            placeholder = { Text(state.phonePlaceholder) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { viewModel.requestCode() }),
            supportingText = state.phoneHint?.let { { Text(it) } },
            modifier = Modifier.weight(1f).focusRequester(focus),
        )
    }
    Spacer(Modifier.height(24.dp))
    PrimaryButton(stringResource(R.string.auth_next), enabled = state.canRequestCode, busy = state.isBusy) { viewModel.requestCode() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    if (picker) {
        CountryPicker(onDismiss = { picker = false }) {
            viewModel.selectCountry(it)
            picker = false
        }
    }
}

@Composable
private fun CodeStep(state: AuthUiState, viewModel: AuthViewModel) {
    val focus = remember { FocusRequester() }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(state.resendAvailableAtMs) {
        while (true) {
            now = System.currentTimeMillis()
            if (state.resendSecondsLeft(now) == 0) break
            delay(500)
        }
    }
    Spacer(Modifier.height(24.dp))
    Text(state.codePrompt, style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.Center)
    Spacer(Modifier.height(28.dp))
    // Ячейки кода поверх невидимого поля: клавиатура цифровая, вставка и автозаполнение работают.
    BasicTextField(
        value = TextFieldValue(state.code, TextRange(state.code.length)),
        onValueChange = { viewModel.setCode(it.text) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { viewModel.verify() }),
        modifier = Modifier.focusRequester(focus),
        decorationBox = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                repeat(state.codeCellCount) { index ->
                    val char = state.code.getOrNull(index)?.toString().orEmpty()
                    val active = index == state.code.length
                    Box(
                        Modifier
                            .size(width = 44.dp, height = 56.dp)
                            .border(
                                width = if (active) 2.dp else 1.dp,
                                color = if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
                                shape = RoundedCornerShape(12.dp),
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(char, fontSize = 24.sp, fontWeight = FontWeight.Medium)
                    }
                }
            }
        },
    )
    Spacer(Modifier.height(24.dp))
    if (state.isBusy) {
        CircularProgressIndicator()
    } else if (state.needsManualCodeSubmit) {
        PrimaryButton(stringResource(R.string.auth_verify), enabled = state.canVerify, busy = false) { viewModel.verify() }
    }
    Spacer(Modifier.height(12.dp))
    TextButton(onClick = viewModel::resendCode, enabled = state.canResend(now)) { Text(state.resendTitle(now)) }
    TextButton(onClick = viewModel::backToPhone) { Text(stringResource(R.string.auth_change_number)) }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
}

@Composable
private fun PasswordStep(state: AuthUiState, viewModel: AuthViewModel) {
    var visible by rememberSaveable { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    Spacer(Modifier.height(24.dp))
    Text(state.passwordPrompt, style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.Center)
    Spacer(Modifier.height(24.dp))
    OutlinedTextField(
        value = state.password,
        onValueChange = viewModel::setPassword,
        label = { Text(stringResource(R.string.auth_password_label)) },
        singleLine = true,
        visualTransformation = if (visible) VisualTransformation.None else PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { viewModel.submitPassword() }),
        trailingIcon = {
            IconButton(onClick = { visible = !visible }) {
                Icon(
                    if (visible) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                    contentDescription = stringResource(if (visible) R.string.auth_hide_password else R.string.auth_show_password),
                )
            }
        },
        modifier = Modifier.fillMaxWidth().focusRequester(focus),
    )
    Spacer(Modifier.height(24.dp))
    PrimaryButton(stringResource(R.string.auth_sign_in), enabled = state.canSubmitPassword, busy = state.isBusy) { viewModel.submitPassword() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
}

@Composable
private fun RegistrationStep(state: AuthUiState, viewModel: AuthViewModel) {
    Spacer(Modifier.height(24.dp))
    Text(stringResource(R.string.auth_register_prompt), style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.Center)
    Spacer(Modifier.height(24.dp))
    OutlinedTextField(
        value = state.firstName,
        onValueChange = viewModel::setFirstName,
        label = { Text(stringResource(R.string.auth_first_name)) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Next),
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.height(12.dp))
    OutlinedTextField(
        value = state.lastName,
        onValueChange = viewModel::setLastName,
        label = { Text(stringResource(R.string.auth_last_name)) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { viewModel.register() }),
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.height(24.dp))
    PrimaryButton(stringResource(R.string.auth_create_account), enabled = state.canRegister, busy = state.isBusy) { viewModel.register() }
}

@Composable
private fun PrimaryButton(text: String, enabled: Boolean, busy: Boolean, onClick: () -> Unit) {
    Button(onClick = onClick, enabled = enabled && !busy, modifier = Modifier.fillMaxWidth().height(52.dp)) {
        if (busy) {
            CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
        } else {
            Text(text, style = MaterialTheme.typography.titleMedium)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CountryPicker(onDismiss: () -> Unit, onSelect: (PhoneCountry) -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    val countries = remember(query) { PhoneCountry.search(query) }
    AppSheet(onDismissRequest = onDismiss) {
        Text(
            stringResource(R.string.country_picker_title),
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
        )
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = { Text(stringResource(R.string.country_search)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        )
        if (countries.isEmpty()) {
            Text(
                stringResource(R.string.country_not_found),
                modifier = Modifier.fillMaxWidth().padding(32.dp),
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 360.dp)) {
            items(countries, key = { it.id }) { country ->
                ListItem(
                    headlineContent = { Text(country.name) },
                    leadingContent = { Text(country.flag, fontSize = 24.sp) },
                    trailingContent = { Text("+" + country.code, color = MaterialTheme.colorScheme.onSurfaceVariant) },
                    modifier = Modifier.clickable { onSelect(country) },
                )
            }
        }
    }
}
