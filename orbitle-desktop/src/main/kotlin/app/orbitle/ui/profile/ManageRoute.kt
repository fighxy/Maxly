package app.orbitle.ui.profile

import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import app.orbitle.data.ChatPerson
import app.orbitle.platform.DesktopActions
import app.orbitle.presentation.profile.ChatManageViewModel
import app.orbitle.ui.settings.AvatarImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Экран управления с выбором фото через системный диалог. */
@Composable
fun ManageRoute(model: ChatManageViewModel, contacts: List<ChatPerson>, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    ChatManageScreen(model, contacts, onBack) {
        val file = DesktopActions.pickFiles(imageOnly = true).firstOrNull() ?: return@ChatManageScreen
        scope.launch {
            val jpeg = withContext(Dispatchers.IO) { AvatarImage.jpeg(file) } ?: return@launch
            model.setPhoto(jpeg)
        }
    }
}
