package app.maxly.presentation.stories

import app.maxly.domain.StoryRing

/**
 * Что умеет экран просмотра историй (Android и компьютер): листание и действия над открытой
 * историей. Всё, кроме [onProfile], ведёт в [StoriesViewModel]; профиль открывает экран.
 */
class StoryViewerActions(
    val onNext: () -> Unit,
    val onPrevious: () -> Unit,
    val onNextOwner: () -> Unit,
    val onPreviousOwner: () -> Unit,
    val onOwner: (Int) -> Unit,
    val onClose: () -> Unit,
    val onDelete: () -> Unit,
    val onLike: () -> Unit,
    val onReply: (String) -> Unit,
    val onProfile: (StoryRing) -> Unit,
    val onHideAuthor: () -> Unit,
    val onDownload: () -> Unit,
    val onReport: () -> Unit,
    val onReportReason: (Int) -> Unit,
    val onCloseReport: () -> Unit,
) {
    companion object {
        /** Действия модели [model]; [onProfile] — как экран открывает профиль автора. */
        fun of(model: StoriesViewModel, onProfile: (StoryRing) -> Unit): StoryViewerActions = StoryViewerActions(
            onNext = model::next,
            onPrevious = model::previous,
            onNextOwner = model::nextOwner,
            onPreviousOwner = model::previousOwner,
            onOwner = model::openOwnerAt,
            onClose = model::close,
            onDelete = model::deleteCurrent,
            onLike = model::toggleLike,
            onReply = model::reply,
            onProfile = { ring ->
                model.close()
                onProfile(ring)
            },
            onHideAuthor = model::hideAuthor,
            onDownload = model::download,
            onReport = model::openReport,
            onReportReason = model::report,
            onCloseReport = model::closeReport,
        )
    }
}
