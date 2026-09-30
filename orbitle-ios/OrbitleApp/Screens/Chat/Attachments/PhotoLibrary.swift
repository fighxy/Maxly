@preconcurrency import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Медиатека для листа вложений: доступ, альбомы, ассеты выбранного альбома и превью.
/// Живёт, пока открыт лист; изменения медиатеки подхватывает сама.
@MainActor
@Observable
final class PhotoLibrary: NSObject, PHPhotoLibraryChangeObserver {
    struct Album: Identifiable, Hashable {
        let id: String
        let title: String
    }

    static let recentsId = "recents"

    private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var albums: [Album] = [Album(id: recentsId, title: "Недавние")]
    private(set) var album = Album(id: recentsId, title: "Недавние")
    /// Ассеты альбома, новые сверху.
    private(set) var assets: PHFetchResult<PHAsset> = PHFetchResult()
    @ObservationIgnored let images = PHCachingImageManager()
    @ObservationIgnored private var observing = false

    var canRead: Bool { status == .authorized || status == .limited }
    var isLimited: Bool { status == .limited }

    /// Спрашивает доступ, если его ещё не спрашивали, и загружает ассеты.
    func prepare() async {
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard canRead else { return }
        if !observing {
            PHPhotoLibrary.shared().register(self)
            observing = true
        }
        reloadAlbums()
        reloadAssets()
    }

    func stop() {
        guard observing else { return }
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        observing = false
        images.stopCachingImagesForAllAssets()
    }

    func select(_ album: Album) {
        self.album = album
        reloadAssets()
    }

    func asset(at index: Int) -> PHAsset? {
        index < assets.count ? assets.object(at: index) : nil
    }

    /// Ассеты по id в заданном порядке (порядок выбора, а не порядок медиатеки).
    func assets(ids: [String]) -> [AssetRef] {
        let found = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var byId: [String: PHAsset] = [:]
        found.enumerateObjects { asset, _, _ in byId[asset.localIdentifier] = asset }
        return ids.compactMap { byId[$0].map(AssetRef.init) }
    }

    /// Системный выбор фото при частичном доступе.
    func presentLimitedPicker() {
        guard let presenter = UIApplication.shared.attachmentPresenter else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter)
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            self?.status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            self?.reloadAlbums()
            self?.reloadAssets()
        }
    }

    private func reloadAlbums() {
        var list = [Album(id: Self.recentsId, title: "Недавние")]
        let smart: [PHAssetCollectionSubtype] = [.smartAlbumFavorites, .smartAlbumVideos, .smartAlbumScreenshots]
        for subtype in smart {
            let result = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
            result.enumerateObjects { collection, _, _ in
                list.append(Album(id: collection.localIdentifier, title: collection.localizedTitle ?? ""))
            }
        }
        let user = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        user.enumerateObjects { collection, _, _ in
            list.append(Album(id: collection.localIdentifier, title: collection.localizedTitle ?? ""))
        }
        albums = list.filter { !$0.title.isEmpty }
        if !albums.contains(where: { $0.id == album.id }) {
            album = albums[0]
        }
    }

    private func reloadAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        if album.id == Self.recentsId {
            assets = PHAsset.fetchAssets(with: options)
            return
        }
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album.id], options: nil)
        if let collection = collections.firstObject {
            assets = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            assets = PHAsset.fetchAssets(with: options)
        }
    }

    /// Превью ассета. Один ответ: без промежуточной размытой картинки.
    nonisolated static func thumbnail(_ ref: AssetRef, size: CGSize, manager: ManagerRef) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            manager.manager.requestImage(
                for: ref.asset, targetSize: size, contentMode: .aspectFill, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

/// Ассет для передачи в фоновую работу. PHAsset неизменяем, читать его можно из любого потока.
struct AssetRef: @unchecked Sendable {
    let asset: PHAsset
}

/// Менеджер картинок медиатеки: его методы потокобезопасны.
struct ManagerRef: @unchecked Sendable {
    let manager: PHImageManager
}

extension UIApplication {
    /// Верхний показанный контроллер активной сцены: от него показываем системные листы.
    var attachmentPresenter: UIViewController? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}
