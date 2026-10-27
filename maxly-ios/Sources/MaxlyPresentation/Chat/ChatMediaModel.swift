import Foundation
import Observation
import MaxlyDomain

/// Вложения открытого чата: просмотр фото и видео (с прямыми ссылками на ролики у сервера),
/// кружки в ленте, открытие файлов и сохранение в «Фото» и «Файлы». Ошибки и уведомления
/// показывает экран чата (`onError`, `onNotice`).
@MainActor
@Observable
public final class ChatMediaModel {
    public let chatId: String
    /// Просмотр фото и видео.
    public var viewer: MediaViewerRequest?
    /// Кружок, который играет прямо в ленте (не на весь экран).
    public private(set) var roundPlayback: RoundPlayback?
    /// Открытый файл.
    public var openedFile: OpenedFile?
    /// Открытое окно «Сохранить в Файлы».
    public var fileExport: FileExport?
    /// Идёт сохранение (скачивание перед ним): повторное нажатие ждёт.
    public private(set) var isSaving = false
    /// Вложение, для которого сейчас запрашивается ссылка или качается файл: пузырь рисует на нём загрузку.
    public private(set) var loadingMediaId: String?
    @ObservationIgnored private let media: (any MediaRepository)?
    @ObservationIgnored private let links: (any MediaLinkResolver)?
    /// Прямые адреса видео, полученные у сервера за время жизни экрана.
    @ObservationIgnored private var resolvedVideos: [String: URL] = [:]
    @ObservationIgnored private var mediaTask: Task<Void, Never>?
    @ObservationIgnored private var fileTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let gallery: (any GallerySaving)?
    @ObservationIgnored private let repository: any MessageRepository
    /// Сообщения ленты: из них «Сохранить» в просмотре находит открытое сообщение.
    @ObservationIgnored public var messages: () -> [Message] = { [] }
    /// Своё сообщение: в просмотре автор — «Вы».
    @ObservationIgnored public var isOutgoing: (Message) -> Bool = { _ in false }
    /// Кружок вот-вот заиграет в ленте: голосовое останавливается.
    @ObservationIgnored public var onWillPlayRound: (() -> Void)?
    @ObservationIgnored public var onNotice: ((String) -> Void)?
    @ObservationIgnored public var onError: ((MaxlyError) -> Void)?

    public init(
        chatId: String,
        repository: any MessageRepository,
        media: (any MediaRepository)?,
        links: (any MediaLinkResolver)?,
        gallery: (any GallerySaving)?
    ) {
        self.chatId = chatId
        self.repository = repository
        self.media = media
        self.links = links
        self.gallery = gallery
    }

    /// Чат ушёл с экрана: загрузки для просмотра и файлов отменяются.
    func cancel() {
        fileTask?.cancel()
        fileTask = nil
        mediaTask?.cancel()
        mediaTask = nil
        loadingMediaId = nil
        openedFile = nil
    }

    /// Голосовое заиграло: кружок в ленте останавливается.
    func stopRoundPlayback() {
        roundPlayback = nil
    }

    private func show(_ failure: MaxlyError) {
        onError?(failure)
    }

    private func showNotice(_ text: String) {
        onNotice?(text)
    }

    /// Открывает просмотр фото и видео сообщения. У видео из Max нет адреса в самом вложении:
    /// перед открытием экран спрашивает у сервера прямые ссылки на ролики этого сообщения.
    public func presentMedia(_ message: Message, startId: String) {
        mediaTask?.cancel()
        loadingMediaId = nil
        // Повторное касание играющего кружка останавливает его.
        if roundPlayback?.id == startId {
            roundPlayback = nil
            return
        }
        let pending = message.content.visuals.compactMap(\.video)
            .filter { $0.playbackURL == nil && resolvedVideos[$0.id] == nil }
        guard let links, !pending.isEmpty else {
            showViewer(message, startId: startId)
            return
        }
        loadingMediaId = startId
        mediaTask = Task {
            for video in pending {
                guard !Task.isCancelled else { return }
                if let url = try? await links.link(
                    chatId: message.chatId,
                    messageId: message.serverId ?? message.id,
                    kind: .video,
                    attachmentId: video.id
                ) {
                    resolvedVideos[video.id] = url
                }
            }
            guard !Task.isCancelled else { return }
            loadingMediaId = nil
            showViewer(message, startId: startId)
        }
    }

    private func showViewer(_ message: Message, startId: String) {
        let slides = message.content.visuals.compactMap { attachment -> MediaSlide? in
            if let photo = attachment.photo {
                guard photo.displayURL != nil else { return nil }
                return MediaSlide(id: photo.id, stillURL: photo.displayURL, playURL: nil, isVideo: false)
            }
            if let video = attachment.video {
                let play = video.playbackURL ?? resolvedVideos[video.id]
                guard video.displayURL != nil || play != nil else { return nil }
                return MediaSlide(id: video.id, stillURL: video.displayURL, playURL: play, isVideo: play != nil)
            }
            return nil
        }
        let tappedVideo = message.content.visuals.compactMap(\.video).first { $0.id == startId }
        if let tappedVideo, tappedVideo.playbackURL == nil, resolvedVideos[tappedVideo.id] == nil {
            show(.rejected("Видео не удалось загрузить"))
        }
        if let tappedVideo, tappedVideo.isRound, let url = tappedVideo.playbackURL ?? resolvedVideos[tappedVideo.id] {
            onWillPlayRound?()
            playRound(tappedVideo.id, url: url)
            return
        }
        guard slides.contains(where: { $0.id == startId }) else { return }
        let caption = message.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        viewer = MediaViewerRequest(
            id: startId, slides: slides, messageId: message.id,
            author: isOutgoing(message) ? "Вы" : message.authorName,
            date: message.timestamp,
            caption: caption.isEmpty ? nil : caption
        )
    }

    /// Запасной путь видео с прогрессом: ролик скачивается целиком (доля 0…1 в [progress]) и
    /// играет с диска. Отмена задачи отменяет и загрузку.
    public func downloadVideo(_ slide: MediaSlide, progress: @escaping @MainActor (Double) -> Void) async -> URL? {
        guard let url = slide.playURL, !url.isFileURL, let media else { return slide.playURL }
        let item = MediaItem(id: "video-\(slide.id)", type: .video, url: url, size: 0)
        do {
            for try await value in media.download(item) { progress(value) }
            return try await media.preview(for: item)
        } catch is CancellationError {
            return nil
        } catch let error as MaxlyError {
            if error != .cancelled { show(error) }
            return nil
        } catch {
            show(.networkUnavailable)
            return nil
        }
    }

    /// Запасной путь видео: поток не открылся — ролик скачивается целиком и играет с диска.
    public func downloadVideo(_ slide: MediaSlide) async -> URL? {
        guard let url = slide.playURL, !url.isFileURL, let media else { return slide.playURL }
        do {
            return try await media.preview(for: MediaItem(id: "video-\(slide.id)", type: .video, url: url, size: 0))
        } catch {
            show(error)
            return nil
        }
    }

    public func openFile(_ message: Message, attachmentId: String) {
        fileTask?.cancel()
        fileTask = Task { await self.loadFile(message, attachmentId: attachmentId) }
    }

    /// Кружок играет из кэша («Видеосообщения» в «Данных и памяти»): ролик в полмегабайта
    /// качается целиком, а повторный просмотр не тянет его из сети. Не скачался — играет поток.
    private func playRound(_ id: String, url: URL) {
        guard !url.isFileURL, let media else {
            roundPlayback = RoundPlayback(id: id, url: url)
            return
        }
        loadingMediaId = id
        mediaTask = Task {
            let file = try? await media.preview(for: MediaItem(id: "note-\(id)", type: .videoNote, url: url, size: 0))
            guard !Task.isCancelled else { return }
            loadingMediaId = nil
            roundPlayback = RoundPlayback(id: id, url: file ?? url)
        }
    }

    /// Кружок доиграл или ушёл из ленты.
    public func stopRound(id: String) {
        if roundPlayback?.id == id { roundPlayback = nil }
    }

    private func loadFile(_ message: Message, attachmentId: String) async {
        guard let file = message.content.files.first(where: { $0.id == attachmentId }) else { return }
        if let local = file.fileURL {
            guard !Task.isCancelled else { return }
            openedFile = OpenedFile(id: file.id, url: Self.namedCopy(of: local, name: file.name, id: file.id), name: file.name)
            return
        }
        guard let media else { return }
        loadingMediaId = file.id
        defer { if loadingMediaId == file.id { loadingMediaId = nil } }
        do {
            var item = file.cacheItem()
            if item == nil, let links {
                // У файла из Max в сообщении только id: адрес выдаёт сервер (`FILE_DOWNLOAD`).
                let url = try await links.link(
                    chatId: message.chatId,
                    messageId: message.serverId ?? message.id,
                    kind: .file,
                    attachmentId: file.id
                )
                item = MediaItem(id: file.id, type: .file, url: url, size: file.size, localPath: nil)
            }
            guard let item else {
                show(.rejected("Файл недоступен"))
                return
            }
            let saved = try await media.preview(for: item)
            guard !Task.isCancelled else { return }
            await repository.noteDownloaded(messageId: message.id, attachmentId: file.id, localPath: saved.path)
            guard !Task.isCancelled else { return }
            openedFile = OpenedFile(id: file.id, url: Self.namedCopy(of: saved, name: file.name, id: file.id), name: file.name)
        } catch let failure as MaxlyError {
            guard !Task.isCancelled else { return }
            show(failure)
        } catch {
            guard !Task.isCancelled else { return }
            show(.storageError)
        }
    }

    // MARK: Сохранение на телефон

    /// Есть что сохранить: в «Фото» — фото, видео и кружки, в «Файлы» — любые вложения.
    public func canSave(_ message: Message, to target: SaveTarget) -> Bool {
        switch target {
        case .photos: gallery != nil && !message.content.visuals.isEmpty
        case .files: !Self.saveable(message, to: .files).isEmpty
        case .share: !Self.saveable(message, to: .share).isEmpty
        }
    }

    /// Сохранить вложения сообщения (или одно, `attachmentId`) в «Фото» или в «Файлы».
    /// Нескачанное сначала качается в кэш. `fromViewer` — нажато в просмотре фото.
    public func save(_ message: Message, to target: SaveTarget, attachmentId: String? = nil, fromViewer: Bool = false) {
        guard !isSaving else { return }
        var chosen = Self.saveable(message, to: target)
        if let attachmentId { chosen = chosen.filter { $0.id == attachmentId } }
        guard !chosen.isEmpty else { return }
        isSaving = true
        saveTask = Task {
            await self.performSave(chosen, of: message, to: target, fromViewer: fromViewer)
            self.isSaving = false
        }
    }

    /// Сохранить кадр, открытый в просмотре.
    public func saveViewerSlide(_ slideId: String, to target: SaveTarget) {
        guard let messageId = viewer?.messageId,
              let message = messages().first(where: { $0.id == messageId }) else { return }
        save(message, to: target, attachmentId: slideId, fromViewer: true)
    }

    /// Окно «Сохранить в Файлы» закрыто: `saved` — файлы записаны в выбранную папку.
    public func finishFileExport(saved: Bool) {
        let count = fileExport?.files.count ?? 0
        let shared = fileExport?.share == true
        fileExport = nil
        guard !shared else { return }
        if saved { showNotice(count > 1 ? "Сохранено в «Файлы»: \(count)" : "Сохранено в «Файлы»") }
    }

    static func saveable(_ message: Message, to target: SaveTarget) -> [ChatAttachment] {
        message.content.attachments.filter { attachment in
            switch attachment {
            case .photo, .video: true
            case .voice, .file: target == .files
            case .contact, .sticker, .call, .poll: false
            }
        }
    }

    private func performSave(_ attachments: [ChatAttachment], of message: Message, to target: SaveTarget, fromViewer: Bool) async {
        if attachments.count == 1 { loadingMediaId = attachments[0].id }
        defer { if attachments.count == 1, loadingMediaId == attachments[0].id { loadingMediaId = nil } }
        var files: [SavedFile] = []
        do {
            for (index, attachment) in attachments.enumerated() {
                files.append(try await savedFile(attachment, of: message, index: index))
            }
        } catch let failure as MaxlyError {
            guard !Task.isCancelled else { return }
            showNotice(failure.userMessage ?? "Не удалось сохранить")
            return
        } catch {
            showNotice("Не удалось сохранить")
            return
        }
        guard !Task.isCancelled else { return }
        switch target {
        case .photos:
            guard let gallery else { return }
            do {
                try await gallery.save(files)
                showNotice(Self.photosNotice(files))
            } catch let failure as MaxlyError {
                showNotice(failure.userMessage ?? "Не удалось сохранить в «Фото»")
            } catch {
                showNotice("Не удалось сохранить в «Фото»")
            }
        case .files:
            fileExport = FileExport(files: files, fromViewer: fromViewer)
        case .share:
            fileExport = FileExport(files: files, fromViewer: fromViewer, share: true)
        }
    }

    static func photosNotice(_ files: [SavedFile]) -> String {
        if files.count > 1 { return "Сохранено в «Фото»: \(files.count)" }
        return files.first?.kind == .video ? "Видео сохранено в «Фото»" : "Фото сохранено в «Фото»"
    }

    /// Файл вложения на устройстве с именем для сохранения. Фото и видео берутся из кэша
    /// под теми же id, что и при просмотре: уже открытое не качается заново.
    private func savedFile(_ attachment: ChatAttachment, of message: Message, index: Int) async throws(MaxlyError) -> SavedFile {
        switch attachment {
        case .photo(let photo):
            let local = try await localFile(
                existing: photo.localPath,
                item: photo.url.map { MediaItem(id: photo.id, type: .image, url: $0, size: 0) }
            )
            // Только JPG или PNG: WebP, HEIC и прочее с CDN перекодируются.
            let base = SaveNaming.name(for: message.timestamp, index: index, ext: "")
            let saved = try await SaveFormat.image(at: local, in: SaveFormat.folder(for: photo.id), baseName: base)
            return SavedFile(url: saved, name: saved.lastPathComponent, kind: .image)
        case .video(let video):
            var remote = video.url ?? resolvedVideos[video.id]
            if remote == nil, let links {
                remote = try await links.link(chatId: message.chatId, messageId: message.serverId ?? message.id, kind: .video, attachmentId: video.id)
                resolvedVideos[video.id] = remote
            }
            let item = remote.map {
                MediaItem(id: video.isRound ? "note-\(video.id)" : "video-\(video.id)", type: video.isRound ? .videoNote : .video, url: $0, size: 0)
            }
            let local = try await localFile(existing: video.localPath, item: item)
            // Всегда MP4: QuickTime (.mov) перекладывается в MP4 без перекодирования.
            let name = SaveNaming.name(for: message.timestamp, index: index, ext: "mp4")
            let saved = SaveFormat.folder(for: video.id).appending(path: name)
            try await SaveFormat.video(at: local, to: saved)
            return SavedFile(url: saved, name: name, kind: .video)
        case .voice(let clip):
            let local = try await localFile(existing: clip.localPath, item: clip.cacheItem())
            let name = SaveNaming.name(for: message.timestamp, index: index, ext: local.pathExtension.isEmpty ? "ogg" : local.pathExtension)
            return SavedFile(url: Self.namedCopy(of: local, name: name, id: clip.id), name: name, kind: .other)
        case .file(let file):
            var item = file.cacheItem()
            if item == nil, file.fileURL == nil, let links {
                let url = try await links.link(chatId: message.chatId, messageId: message.serverId ?? message.id, kind: .file, attachmentId: file.id)
                item = MediaItem(id: file.id, type: .file, url: url, size: file.size)
            }
            let local = try await localFile(existing: file.localPath, item: item)
            await repository.noteDownloaded(messageId: message.id, attachmentId: file.id, localPath: local.path)
            return SavedFile(url: Self.namedCopy(of: local, name: file.name, id: file.id), name: file.name, kind: .other)
        case .contact:
            throw .rejected("Контакт нельзя сохранить файлом")
        case .sticker:
            throw .rejected("Стикер нельзя сохранить файлом")
        case .call:
            throw .rejected("Звонок нельзя сохранить файлом")
        case .poll:
            throw .rejected("Опрос нельзя сохранить файлом")
        }
    }

    /// Свой файл, если он ещё на диске, иначе копия из кэша медиа (скачивается при нужде).
    private func localFile(existing path: String?, item: MediaItem?) async throws(MaxlyError) -> URL {
        if let path, FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        guard let item, let media else { throw .rejected("Файл недоступен") }
        if item.url.isFileURL, FileManager.default.fileExists(atPath: item.url.path) { return item.url }
        return try await media.preview(for: item)
    }

    /// Предпросмотр узнаёт тип файла по расширению, а в кэше файл лежит под id. Отдаём копию
    /// с настоящим именем во временной папке.
    static func namedCopy(of url: URL, name: String, id: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safe.isEmpty, safe != url.lastPathComponent else { return url }
        let folder = id.filter { $0.isLetter || $0.isNumber }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MaxlyFiles", directoryHint: .isDirectory)
            .appending(path: folder.isEmpty ? "file" : folder, directoryHint: .isDirectory)
        let target = directory.appending(path: safe)
        let manager = FileManager.default
        if manager.fileExists(atPath: target.path) { return target }
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try manager.copyItem(at: url, to: target)
            return target
        } catch {
            return url
        }
    }
}
