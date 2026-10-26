import AVFoundation
import ImageIO
import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Снимки с камеры из кнопки камеры в поле ввода.
///
/// Сразу открывается камера. После снимка — просмотр: снимок во весь экран, сверху
/// «сохранить», «кадр», «текст» и «рисунок» (редактор фото; у видео — обрезка), снизу лента
/// снимков, подпись с камерой для следующего снимка и отправка. Касание снимка в ленте
/// выбирает его, касание выбранного — удаляет. Всё уходит одним альбомом с подписью.
struct CameraCaptureFlow: View {
    let onSend: ([AttachmentDraft], String) -> Void
    let onClose: () -> Void

    @State private var shots: [CameraShot] = []
    @State private var selectedId: String?
    @State private var cameraShown = false
    @State private var caption = ""
    @State private var preparing = false
    @State private var failure: String?
    @State private var editing: EditRequest?
    @State private var confirmClose = false
    @State private var notice: String?
    @FocusState private var captionFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let selected {
                preview(selected)
                    .ignoresSafeArea(.keyboard)
                    .onTapGesture { captionFocused = false }
            }
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomPanel
            }
            if preparing {
                ProgressView()
                    .tint(.white)
                    .padding(20)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .preferredColorScheme(.dark)
        // Камера сразу, поверх ещё пустого просмотра.
        .onAppear { if shots.isEmpty { cameraShown = true } }
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: shots.map(\.id))
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: notice)
        .fullScreenCover(isPresented: $cameraShown, onDismiss: {
            // Камеру закрыли без снимка, а снимков нет: выходить из всего.
            if shots.isEmpty, !preparing { onClose() }
        }) {
            ChatCameraPicker(
                onShot: { shot in
                    cameraShown = false
                    add(shot)
                },
                onCancel: { cameraShown = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $editing) { request in
            editor(request)
        }
        .confirmationDialog("Удалить снимки?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button(shots.count > 1 ? "Удалить \(shots.count) снимка" : "Удалить снимок", role: .destructive, action: onClose)
            Button("Отмена", role: .cancel) {}
        }
        .alert("Не получилось", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private var selected: CameraShot? {
        shots.first { $0.id == selectedId } ?? shots.last
    }

    // MARK: Просмотр

    @ViewBuilder
    private func preview(_ shot: CameraShot) -> some View {
        if let image = shot.thumbnail {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if shot.draft.kind == .video {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.white.opacity(0.85))
                            .allowsHitTesting(false)
                    }
                }
                .id(shot.revision)
                .transition(.opacity)
                .accessibilityLabel(shot.draft.kind == .video ? "Видео" : "Снимок")
        } else {
            ProgressView().tint(.white)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            circleButton("xmark", label: "Закрыть") {
                if shots.isEmpty { onClose() } else { confirmClose = true }
            }
            Spacer(minLength: 0)
            if let selected {
                circleButton("square.and.arrow.down", label: "Сохранить в Фото") { save(selected) }
                if selected.draft.kind == .photo {
                    circleButton("crop.rotate", label: "Кадр") { edit(selected, tool: .crop) }
                    circleButton("textformat", label: "Текст") { edit(selected, tool: .text) }
                    circleButton("pencil.tip", label: "Рисунок") { edit(selected, tool: .draw) }
                } else {
                    circleButton("timeline.selection", label: "Обрезать видео") { edit(selected, tool: .crop) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .overlay(alignment: .bottom) {
            if let notice {
                Text(notice)
                    .font(.app(.footnote, .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: Capsule())
                    .offset(y: 44)
                    .transition(.opacity)
            }
        }
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.45), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(preparing)
        .accessibilityLabel(label)
    }

    // MARK: Низ: лента, подпись, отправка

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            if shots.count > 1 {
                strip
            }
            HStack(alignment: .bottom, spacing: 10) {
                HStack(alignment: .bottom, spacing: 8) {
                    Button {
                        captionFocused = false
                        cameraShown = true
                    } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(preparing || shots.count >= Self.limit)
                    .accessibilityLabel("Ещё снимок")
                    TextField("Добавить подпись…", text: $caption, axis: .vertical)
                        .focused($captionFocused)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .frame(minHeight: 44)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.15)))
                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.maxlyOnAccent)
                        .frame(width: 48, height: 48)
                        .background(Color.maxlyAccent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(shots.isEmpty || preparing)
                .accessibilityLabel(shots.count > 1 ? "Отправить \(shots.count)" : "Отправить")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    /// Лента снимков: касание выбирает, касание выбранного (с корзиной) — удаляет.
    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(shots) { shot in
                    let isSelected = shot.id == selected?.id
                    Button {
                        if isSelected { remove(shot) } else { selectedId = shot.id }
                    } label: {
                        ZStack {
                            if let image = shot.thumbnail {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color.white.opacity(0.1)
                            }
                            if isSelected {
                                Color.black.opacity(0.45)
                                Image(systemName: "trash")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.white, lineWidth: isSelected ? 2 : 0)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSelected ? "Удалить снимок" : "Выбрать снимок")
                }
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 60)
    }

    // MARK: Действия

    /// Сколько снимков уходит одним альбомом.
    static let limit = 10

    private func add(_ shot: ChatCameraPicker.Shot) {
        preparing = true
        Task {
            defer { preparing = false }
            do {
                let draft: AttachmentDraft
                switch shot {
                case .photo(let image): draft = try MediaExporter.draft(camera: image)
                case .video(let url): draft = try await MediaExporter.draft(cameraVideo: url)
                }
                let item = CameraShot(id: UUID().uuidString, original: draft, draft: draft, thumbnail: await Self.thumbnail(draft))
                shots.append(item)
                selectedId = item.id
            } catch {
                failure = error.localizedDescription
                if shots.isEmpty { onClose() }
            }
        }
    }

    private func remove(_ shot: CameraShot) {
        guard let index = shots.firstIndex(where: { $0.id == shot.id }) else { return }
        shots.remove(at: index)
        if shots.isEmpty {
            // Удалили последний снимок: снова камера.
            cameraShown = true
        } else {
            selectedId = shots[min(index, shots.count - 1)].id
        }
    }

    private func edit(_ shot: CameraShot, tool: PhotoEditor.Tool) {
        captionFocused = false
        editing = EditRequest(id: shot.id, tool: tool)
    }

    @ViewBuilder
    private func editor(_ request: EditRequest) -> some View {
        if let shot = shots.first(where: { $0.id == request.id }) {
            if shot.draft.kind == .video {
                VideoEditor(draft: shot.original, onSave: { edited in
                    editing = nil
                    replace(shot.id, with: edited, history: shot.history)
                }, onClose: { editing = nil })
            } else {
                PhotoEditor(draft: shot.original, initialHistory: shot.history, initialTool: request.tool, onSave: { edited, history in
                    editing = nil
                    replace(shot.id, with: edited, history: history)
                }, onClose: { editing = nil })
            }
        }
    }

    private func replace(_ id: String, with draft: AttachmentDraft, history: PhotoEditHistory) {
        Task {
            let thumbnail = await Self.thumbnail(draft)
            guard let index = shots.firstIndex(where: { $0.id == id }) else { return }
            shots[index].draft = draft
            shots[index].history = history
            shots[index].thumbnail = thumbnail
            shots[index].revision += 1
        }
    }

    private func save(_ shot: CameraShot) {
        let file = SavedFile(
            url: URL(fileURLWithPath: shot.draft.path),
            name: shot.draft.fileName,
            kind: shot.draft.kind == .video ? .video : .image
        )
        Task {
            do throws(MaxlyError) {
                try await PhotoLibrarySaver().save([file])
                show("Сохранено в Фото")
            } catch {
                failure = error.userMessage ?? "Не удалось сохранить в «Фото»"
            }
        }
    }

    private func show(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if notice == text { notice = nil }
        }
    }

    private func send() {
        guard !shots.isEmpty else { return }
        captionFocused = false
        onSend(shots.map(\.draft), caption.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Картинка снимка для просмотра и ленты: фото — уменьшенное, видео — первый кадр.
    private static func thumbnail(_ draft: AttachmentDraft) async -> UIImage? {
        let url = URL(fileURLWithPath: draft.path)
        if draft.kind == .video {
            return await videoFrame(url).map { UIImage(cgImage: $0) }
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    /// Генератор живёт внутри одного вызова и не пересекает границы акторов.
    private nonisolated static func videoFrame(_ url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        return try? await generator.image(at: .zero).image
    }
}

/// Снимок в просмотре: исходник для редактора, готовый файл, история правок и картинка.
private struct CameraShot: Identifiable {
    let id: String
    let original: AttachmentDraft
    var draft: AttachmentDraft
    var history = PhotoEditHistory()
    var thumbnail: UIImage?
    /// Меняется после правки: картинка просмотра перерисовывается.
    var revision = 0

    init(id: String, original: AttachmentDraft, draft: AttachmentDraft, thumbnail: UIImage?) {
        self.id = id
        self.original = original
        self.draft = draft
        self.thumbnail = thumbnail
    }
}

private struct EditRequest: Identifiable {
    let id: String
    let tool: PhotoEditor.Tool
}
