package app.orbitle.platform

import androidx.compose.runtime.Composable
import com.mohamedrejeb.calf.picker.FilePickerFileType
import com.mohamedrejeb.calf.picker.FilePickerSelectionMode
import com.mohamedrejeb.calf.picker.FilePickerSettings
import com.mohamedrejeb.calf.picker.rememberFilePickerLauncher
import java.io.File

/** Системный выбор файлов. Возвращает действие, которое открывает диалог. */
@Composable
fun rememberDesktopFilePicker(
    title: String,
    imageOnly: Boolean = false,
    media: Boolean = false,
    multiple: Boolean = false,
    onFiles: (List<File>) -> Unit,
): () -> Unit {
    val launcher = rememberFilePickerLauncher(
        type = when {
            media -> FilePickerFileType.ImageVideo
            imageOnly -> FilePickerFileType.Image
            else -> FilePickerFileType.All
        },
        selectionMode = if (multiple) FilePickerSelectionMode.Multiple else FilePickerSelectionMode.Single,
        settings = FilePickerSettings(title = title),
        onResult = { picked ->
            onFiles(picked.map { it.file }.filter { it.isFile })
        },
    )
    return launcher::launch
}
