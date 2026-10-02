package app.orbitle.presentation.settings

import app.orbitle.domain.ChatFolderRules
import app.orbitle.domain.ServerFolder

/** «5 чатов · сами: личные, боты». */
fun folderSummary(folder: ServerFolder, count: Int): String? {
    val parts = mutableListOf(chatsCount(count))
    folderFilterSummary(folder)?.let(parts::add)
    return parts.joinToString(" · ")
}

/** Что папка набирает сама по фильтрам сервера; `null`, если фильтров нет. */
fun folderFilterSummary(folder: ServerFolder): String? {
    if (folder.filters.isEmpty()) return null
    val names = mapOf(
        ChatFolderRules.Code.DIALOG to "личные", ChatFolderRules.Code.CONTACT to "контакты",
        ChatFolderRules.Code.NOT_CONTACT to "не контакты", ChatFolderRules.Code.GROUP to "группы",
        ChatFolderRules.Code.CHANNEL to "каналы", ChatFolderRules.Code.BOT to "боты",
        ChatFolderRules.Code.UNREAD to "непрочитанные", ChatFolderRules.Code.MARKED_UNREAD to "непрочитанные",
        ChatFolderRules.Code.READ to "прочитанные", ChatFolderRules.Code.MUTED to "без звука",
        ChatFolderRules.Code.NOT_MUTED to "со звуком",
    )
    val seen = folder.filters.mapNotNull(ChatFolderRules.Code::fromText).mapNotNull(names::get).distinct()
    return if (seen.isEmpty()) "по правилам сервера" else "сами: " + seen.joinToString(", ")
}

/** «1 чат», «3 чата», «5 чатов». */
fun chatsCount(count: Int): String {
    val mod10 = count % 10
    val mod100 = count % 100
    val word = when {
        mod10 == 1 && mod100 != 11 -> "чат"
        mod10 in 2..4 && mod100 !in 12..14 -> "чата"
        else -> "чатов"
    }
    return "$count $word"
}
