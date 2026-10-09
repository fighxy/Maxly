package app.maxly.ui.profile

import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import app.maxly.data.ChatPerson
import app.maxly.platform.rememberDesktopFilePicker
import app.maxly.presentation.profile.ChatManageViewModel
import app.maxly.ui.settings.AvatarImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Экран управления с выбором фото через системный диалог. */
@Composable
fun ManageRoute(model: ChatManageViewModel, contacts: List<ChatPerson>, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    val pickPhoto = rememberDesktopFilePicker(title = "Выберите изображение", imageOnly = true) { files ->
        val file = files.firstOrNull() ?: return@rememberDesktopFilePicker
        scope.launch {
            val jpeg = withContext(Dispatchers.IO) { AvatarImage.jpeg(file) } ?: return@launch
            model.setPhoto(jpeg)
        }
    }
    ChatManageScreen(model, contacts, onBack, onPickPhoto = pickPhoto)
}
