package app.maxly.ui.chat

import app.maxly.platform.DesktopActions
import app.maxly.presentation.chat.OpenFile
import java.io.File

/** Открыть скачанный файл программой, которая назначена в системе. */
object FileOpener {
    fun open(file: OpenFile): Boolean {
        val target = File(file.path)
        if (!target.isFile) return false
        DesktopActions.openFile(target)
        return true
    }
}
