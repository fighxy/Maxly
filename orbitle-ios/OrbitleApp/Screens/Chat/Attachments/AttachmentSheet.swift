@preconcurrency import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Лист вложений: галерея с камерой и номерами выбора, файл, контакт; геопозиция и опрос — позже.
/// Внизу плавающая панель вкладок, при выборе вместо неё подпись и кнопка отправки.
struct AttachmentSheet: View {
    var contactList: (() -> AsyncStream<[Contact]>)?
    let onSend: ([AttachmentDraft], String) -> Void
    let onClose: () -> Void

    @State private var model = AttachmentSheetModel()
    @State private var library = PhotoLibrary()
    @State private var feed = CameraFeed()
    @State private var cameraShown = false
    @State private var importerShown = false
    @State private var preparing = false
    @State private var failure: String?
    @State private var editingPhoto: EditablePhoto?
    @State private var editedPhotos: [String: AttachmentDraft] = [:]
    @State private var photoOriginals: [String: AttachmentDraft] = [:]
    @State private var photoHistories: [String: PhotoEditHistory] = [:]
    @State private var pendingShot: ChatCameraPicker.Shot?
    @FocusState private var captionFocused: Bool
    @Namespace private var tabHighlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) { bottomBar }
        .overlay {
            if preparing {
                ProgressView("Готовим…")
                    .padding(20)
                    .orbitleGlassRounded(radius: 18)
                    .transition(.opacity)
            }
        }
        .animation(OrbitleMotion.fade, value: preparing)
        .disabled(preparing)
        .task { await library.prepare() }
        .task(id: contactList == nil) {
            guard let contactList else { return }
            for await list in contactList() {
                model.setContacts(list)
            }
        }
        .onDisappear {
            library.stop()
            feed.stop()
        }
        .onChange(of: model.tab) { _, tab in
            if tab == .file { importerShown = true }
        }
        .fileImporter(isPresented: $importerShown, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .fullScreenCover(isPresented: $cameraShown, onDismiss: {
            if let shot = pendingShot { pendingShot = nil; sendShot(shot) }
        }) {
            ChatCameraPicker(
                onShot: { shot in
                    pendingShot = shot
                    cameraShown = false
                },
                onCancel: { cameraShown = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $editingPhoto) { photo in
            PhotoEditor(draft: photo.draft, initialHistory: photoHistories[photo.id] ?? PhotoEditHistory(), onSave: { edited, history in
                editingPhoto = nil
                if photo.fromCamera { onSend([edited], "") }
                else { editedPhotos[photo.id] = edited; photoHistories[photo.id] = history }
            }, onClose: { editingPhoto = nil })
        }
        .alert("Не получилось", isPresented: failureShown, presenting: failure) { _ in
            Button("OK", role: .cancel) { failure = nil }
        } message: { text in
            Text(text)
        }
        // Панель вкладок сменяется подписью с кнопкой «Отправить» и обратно — выездом снизу.
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: model.hasSelection)
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: model.limitReached)
    }

    // MARK: Шапка

    private var header: some View {
        ZStack {
            if model.tab == .gallery, library.canRead {
                albumMenu
            } else {
                Text(model.tab.title).font(.headline)
            }
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .orbitleGlassCircle(size: 36)
                .accessibilityLabel("Закрыть")
                Spacer()
                if model.hasSelection {
                    Button("Сбросить") { model.clearSelection(); editedPhotos = [:];photoHistories = [:];photoOriginals = [:] }
                        .font(.subheadline)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var albumMenu: some View {
        Menu {
            ForEach(library.albums) { album in
                Button {
                    library.select(album)
                } label: {
                    if album == library.album {
                        Label(album.title, systemImage: "checkmark")
                    } else {
                        Text(album.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(library.album.title).font(.headline)
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: Вкладки

    @ViewBuilder
    private var content: some View {
        switch model.tab {
        case .gallery: gallery
        case .file: filePane
        case .contact: contactPane
        case .location, .poll: soon(model.tab)
        }
    }

    @ViewBuilder
    private var gallery: some View {
        if library.canRead || library.status == .notDetermined {
            ScrollView {
                if library.isLimited {
                    limitedBanner
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    cameraCell
                    ForEach(0..<library.assets.count, id: \.self) { index in
                        if let asset = library.asset(at: index) {
                            AssetCell(
                                asset: asset,
                                number: model.number(of: asset.localIdentifier),
                                editedPath: editedPhotos[asset.localIdentifier]?.path,
                                manager: ManagerRef(manager: library.images)
                            ) {
                                model.toggle(asset.localIdentifier)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if asset.mediaType == .image {
                                    Button { editAsset(asset) } label: {
                                        Image(systemName: "pencil").font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.white).frame(width: 32, height: 32)
                                            .background(.black.opacity(0.55), in: Circle())
                                    }.buttonStyle(.plain).padding(6).accessibilityLabel("Редактировать фото")
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 96)
            }
            .overlay(alignment: .top) {
                if model.limitReached {
                    Text("Можно выбрать не больше \(AttachmentSheetModel.selectionLimit)")
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .orbitleGlassCapsule()
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Нет доступа к фото")
                    .font(.headline)
                Text("Разрешите доступ в настройках, чтобы отправлять фото и видео.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Открыть настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                if ChatCameraPicker.isAvailable {
                    Button("Снять на камеру") { cameraShown = true }
                }
            }
            .padding(32)
        }
    }

    private var limitedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(.secondary)
            Text("Доступ только к выбранным фото")
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Изменить") { library.presentLimitedPicker() }
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var cameraCell: some View {
        Button {
            if ChatCameraPicker.isAvailable { cameraShown = true }
        } label: {
            Color.black
                .aspectRatio(1, contentMode: .fill)
                .overlay {
                    if CameraFeed.isAuthorized, ChatCameraPicker.isAvailable {
                        CameraPreview(feed: feed)
                            .onAppear { feed.start() }
                            .onDisappear { feed.stop() }
                    }
                }
                .overlay {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ChatCameraPicker.isAvailable)
        .accessibilityLabel("Камера")
    }

    private var filePane: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Любой файл из «Файлов» или iCloud Drive")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Выбрать файл") { importerShown = true }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Color.orbitleOnAccent)
                .tint(Color.orbitleAccent)
        }
        .padding(32)
    }

    private var contactPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Имя или номер", text: $model.contactQuery)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            let contacts = model.filteredContacts
            if contacts.isEmpty {
                Text(model.contactQuery.isEmpty ? "Контактов пока нет" : "Никого не нашли")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                List(contacts) { contact in
                    Button {
                        onSend([model.contactDraft(contact)], "")
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(title: contact.displayName, id: contact.id, url: contact.avatarURL, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.displayName).foregroundStyle(.primary)
                                if let phone = contact.phone, !phone.isEmpty {
                                    Text(phone).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .contentMargins(.bottom, 96, for: .scrollContent)
            }
        }
    }

    private func soon(_ tab: AttachmentSheetModel.Tab) -> some View {
        VStack(spacing: 12) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Скоро")
                .font(.headline)
            Text("\(tab.title) появится в следующих версиях.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }

    // MARK: Низ

    @ViewBuilder
    private var bottomBar: some View {
        Group {
            if model.tab == .gallery, model.hasSelection {
                sendBar
                    .transition(.orbitleBar(edge: .bottom, reduceMotion: reduceMotion))
            } else {
                tabBar
                    .transition(.orbitleBar(edge: .bottom, reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AttachmentSheetModel.Tab.allCases) { tab in
                Button {
                    withAnimation(OrbitleMotion.quick(reduceMotion: reduceMotion)) { model.tab = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(model.tab == tab ? Color.orbitleAccent : Color.primary)
                    // Подложка выбранной вкладки переезжает к новой, а не появляется скачком.
                    .background {
                        if model.tab == tab {
                            Capsule()
                                .fill(Color.orbitleAccent.opacity(0.14))
                                .matchedGeometryEffect(id: "tab", in: tabHighlight)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .orbitleGlassCapsule()
    }

    private var sendBar: some View {
        OrbitleGlassGroup(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Подпись", text: $model.caption, axis: .vertical)
                    .focused($captionFocused)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .frame(minHeight: 44)
                    .orbitleGlassCapsule()
                Button {
                    sendSelection()
                } label: {
                    Text(model.sendTitle)
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 6)
                        .frame(minHeight: 30)
                }
                .orbitleProminentButtonStyle()
                .buttonBorderShape(.capsule)
                .tint(Color.orbitleAccent)
                .disabled(preparing)
            }
        }
    }

    // MARK: Отправка

    private var failureShown: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }

    private func sendSelection() {
        let assets = library.assets(ids: model.selection)
        let caption = model.caption
        guard !assets.isEmpty else { return }
        captionFocused = false
        preparing = true
        Task {
            defer { preparing = false }
            var drafts: [AttachmentDraft] = []
            do {
                for ref in assets {
                    if let edited = editedPhotos[ref.asset.localIdentifier] { drafts.append(edited) }
                    else { drafts.append(try await MediaExporter.draft(for: ref)) }
                }
            } catch {
                failure = error.localizedDescription
                return
            }
            model.clearSelection()
            editedPhotos = [:]
            photoHistories = [:];photoOriginals = [:]
            onSend(drafts, caption)
        }
    }

    private func sendShot(_ shot: ChatCameraPicker.Shot) {
        preparing = true
        Task {
            defer { preparing = false }
            do {
                let draft: AttachmentDraft
                switch shot {
                case .photo(let image):
                    draft = try MediaExporter.draft(camera: image)
                    editingPhoto = EditablePhoto(id: UUID().uuidString, draft: draft, fromCamera: true)
                    return
                case .video(let url): draft = try await MediaExporter.draft(cameraVideo: url)
                }
                onSend([draft], "")
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func editAsset(_ asset: PHAsset) {
        guard !preparing else { return }
        if model.number(of: asset.localIdentifier) == nil { model.toggle(asset.localIdentifier) }
        guard model.number(of: asset.localIdentifier) != nil else { return }
        preparing = true
        captionFocused = false
        Task {
            defer { preparing = false }
            do {
                let draft: AttachmentDraft
                if let original = photoOriginals[asset.localIdentifier] { draft = original }
                else { draft = try await MediaExporter.draft(for: AssetRef(asset: asset));photoOriginals[asset.localIdentifier] = draft }
                editingPhoto = EditablePhoto(id: asset.localIdentifier, draft: draft, fromCamera: false)
            } catch { failure = error.localizedDescription }
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            do {
                let drafts = try urls.map { try MediaExporter.draft(file: $0) }
                onSend(drafts, "")
            } catch {
                failure = error.localizedDescription
            }
        case .failure(let error):
            failure = error.localizedDescription
        }
    }
}

private struct EditablePhoto: Identifiable {
    let id: String
    let draft: AttachmentDraft
    let fromCamera: Bool
}

/// Ячейка галереи: превью, длительность видео и кружок с номером выбора.
private struct AssetCell: View {
    let asset: PHAsset
    let number: Int?
    let editedPath: String?
    let manager: ManagerRef
    let onTap: () -> Void

    @State private var image: UIImage?
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            Color.secondary.opacity(0.15)
                .aspectRatio(1, contentMode: .fill)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    }
                }
                // Миниатюра проявляется, а не выскакивает.
                .animation(OrbitleMotion.fade, value: image != nil)
                .clipped()
                // `clipped` режет только картинку, а не касания: вертикальное фото (scaledToFill)
                // выходило за ячейку и ловило нажатия соседей — выбиралась не та фотография,
                // а карандаш редактирования у нижнего края перекрывала ячейка ниже.
                .contentShape(Rectangle())
                .overlay {
                    if number != nil {
                        Color.black.opacity(0.2)
                    }
                }
                .overlay(alignment: .topTrailing) { badge.padding(6) }
                .animation(OrbitleMotion.pop(reduceMotion: reduceMotion), value: number)
                .overlay(alignment: .bottomLeading) {
                    if asset.mediaType == .video {
                        Text(Self.duration(asset.duration))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .padding(6)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(asset.mediaType == .video ? "Видео" : "Фото")
        .accessibilityValue(number.map { "Выбрано, \($0)" } ?? "")
        .task(id: editedPath ?? asset.localIdentifier) {
            if let editedPath {
                image = UIImage(contentsOfFile: editedPath)
                return
            }
            let side = 140 * scale
            image = await PhotoLibrary.thumbnail(AssetRef(asset: asset), size: CGSize(width: side, height: side), manager: manager)
        }
    }

    private var badge: some View {
        ZStack {
            if let number {
                Circle().fill(Color.orbitleAccent)
                    .transition(.orbitlePop(reduceMotion: reduceMotion))
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.orbitleOnAccent)
                    .contentTransition(.numericText(value: Double(number)))
            } else {
                Circle().fill(.black.opacity(0.15))
            }
            Circle().stroke(.white, lineWidth: 1.5)
        }
        .frame(width: 24, height: 24)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
