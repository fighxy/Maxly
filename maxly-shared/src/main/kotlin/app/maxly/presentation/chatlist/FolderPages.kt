package app.maxly.presentation.chatlist

/**
 * Связь страниц листаемого списка с папками: страница — позиция папки в полосе.
 * Список папок может поменяться (папку удалили, переставили), поэтому номера всегда зажимаются.
 */
object FolderPages {
    /** Страница выбранной папки; неизвестная папка — первая страница («Все»). */
    fun pageOf(folderIds: List<String>, selectedId: String): Int = folderIds.indexOf(selectedId).coerceAtLeast(0)

    /** Папка на странице [page], зажатой в границы списка; `null`, если папок нет. */
    fun folderAt(folderIds: List<String>, page: Int): String? =
        if (folderIds.isEmpty()) null else folderIds[page.coerceIn(0, folderIds.lastIndex)]

    /**
     * Что выбрать, когда листание остановилось на [settledPage]: папку этой страницы,
     * если она не выбрана; `null` — выбор менять не нужно.
     */
    fun selectionAfterSettle(folderIds: List<String>, settledPage: Int, selectedId: String): String? =
        folderAt(folderIds, settledPage)?.takeIf { it != selectedId }

    /** Позиции прокрутки только для папок, которые остались в полосе. */
    fun <T> retain(positions: Map<String, T>, folderIds: List<String>): Map<String, T> {
        val keep = folderIds.toHashSet()
        return positions.filterKeys { it in keep }
    }
}
