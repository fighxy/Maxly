import SwiftUI
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Фото профиля в `MediaViewer`: текущее фото и, у человека, прошлые фото. Листаются
/// вбок, следующая страница догружается у конца, в шапке «N из M». Кадр открывается
/// оригиналом, а если он не загрузился — самым большим размером сервера.
struct ProfilePhotoViewer: View {
    let gallery: ProfilePhotoGallery
    let title: String
    let saver: ProfilePhotoSaver
    let onClose: () -> Void
    @Environment(\.imageURLSizing) private var imageURLSizing

    var body: some View {
        MediaViewer(
            request: request,
            notice: saver.notice,
            isSaving: saver.isSaving,
            onSave: { id, target in saver.save(gallery.candidates(for: id), title: title, to: target) },
            onShown: { id in Task { await gallery.shown(id) } },
            onClose: onClose
        )
        .profilePhotoExport(saver)
        .task { await gallery.loadMore() }
    }

    private var request: MediaViewerRequest {
        let slides = gallery.items.map { item in
            let first = item.candidates.first
            // Миниатюра ленты — квадрат сервера, а не оригинал.
            let thumb = ImageURLRequests.url(first, shape: .square, pointSize: 44, scale: 3, fullScreen: false, sizing: imageURLSizing)
            return MediaSlide(
                id: item.id, stillURL: first, playURL: nil, isVideo: false,
                fallbackURLs: Array(item.candidates.dropFirst()), thumbnailURL: thumb
            )
        }
        return MediaViewerRequest(id: gallery.items.first?.id ?? "", slides: slides, author: title, total: gallery.total)
    }
}
