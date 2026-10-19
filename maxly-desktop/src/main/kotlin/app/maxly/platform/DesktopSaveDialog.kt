package app.maxly.platform

import java.awt.FileDialog
import java.awt.Frame
import java.io.File

/** Системный диалог «Сохранить как…»: выбранный файл или `null`, если закрыли. */
object DesktopSaveDialog {
    /** [suggested] — имя по умолчанию, папка — «Изображения», если она есть, иначе «Загрузки». */
    fun choose(title: String, suggested: String): File? {
        val dialog = FileDialog(null as Frame?, title, FileDialog.SAVE)
        dialog.directory = startDirectory().absolutePath
        dialog.file = suggested
        dialog.isVisible = true
        val name = dialog.file ?: return null
        val directory = dialog.directory ?: return null
        return File(directory, name)
    }

    private fun startDirectory(): File {
        val home = File(System.getProperty("user.home"))
        return listOf(File(home, "Pictures"), File(home, "Изображения")).firstOrNull { it.isDirectory } ?: AppPaths.downloads
    }
}
