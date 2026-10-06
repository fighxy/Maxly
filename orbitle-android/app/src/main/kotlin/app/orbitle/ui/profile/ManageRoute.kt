package app.orbitle.ui.profile

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import app.orbitle.data.ChatPerson
import app.orbitle.presentation.profile.ChatManageViewModel
import app.orbitle.ui.settings.AvatarImage
import kotlinx.coroutines.launch

/** Экран управления с выбором фото из галереи. */
@Composable
fun ManageRoute(model: ChatManageViewModel, contacts: List<ChatPerson>, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val jpeg = AvatarImage.jpeg(context, uri) ?: return@launch
            model.setPhoto(jpeg)
        }
    }
    ChatManageScreen(model, contacts, onBack) {
        pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
    }
}
