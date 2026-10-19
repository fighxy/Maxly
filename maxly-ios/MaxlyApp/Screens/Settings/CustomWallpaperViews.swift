import SwiftUI
import PhotosUI
import CoreImage
import ImageIO
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Фото из медиатеки для обоев: уменьшается до размера экрана сразу после выбора, а размытие
/// запекается один раз при «Установить». Экран чата потом рисует готовую картинку как есть.
enum WallpaperPhoto {
    /// Картинка переходит между потоками только как неизменяемый результат.
    struct Bitmap: @unchecked Sendable {
        let image: CGImage
        var size: CGSize { CGSize(width: image.width, height: image.height) }
    }

    /// Какую площадь в пунктах обои должны закрыть и сколько пикселей в пункте. На iPhone —
    /// портретный экран, на iPad — квадрат по длинной стороне: обои закрывают обе ориентации.
    @MainActor
    static func cover() -> (points: CGSize, scale: CGFloat) {
        let screen = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
        let bounds = screen?.bounds.size ?? CGSize(width: 393, height: 852)
        let scale = screen?.scale ?? 3
        let short = min(bounds.width, bounds.height)
        let long = max(bounds.width, bounds.height)
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        return (CGSize(width: pad ? long : short, height: long), scale)
    }

    /// Фото, уменьшенное так, чтобы закрыть `pixels` без полей (с учётом поворота из EXIF).
    static func decode(_ data: Data, pixels: CGSize) -> Bitmap? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        var height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        if let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue, orientation >= 5 {
            swap(&width, &height)
        }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if width > 0, height > 0 {
            let scale = min(1, max(pixels.width / width, pixels.height / height))
            options[kCGImageSourceThumbnailMaxPixelSize] = max(1, Int((max(width, height) * scale).rounded(.up)))
        } else {
            options[kCGImageSourceThumbnailMaxPixelSize] = Int(max(pixels.width, pixels.height))
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Bitmap(image: image)
    }

    /// JPEG для `Application Support/Wallpapers`: размытие (`CustomWallpaper.blur`) пересчитано
    /// из пунктов экрана в пиксели картинки, края не темнеют.
    static func render(_ bitmap: Bitmap, blur: Double, coverPoints: CGSize) -> (data: Data, image: UIImage)? {
        var output = bitmap.image
        let radius = CustomWallpaper.blurRadius(blur)
        if radius > 0.5 {
            // Пунктов экрана на пиксель картинки при заполнении `coverPoints`.
            let pointsPerPixel = max(coverPoints.width / bitmap.size.width, coverPoints.height / bitmap.size.height)
            let sigma = radius / max(pointsPerPixel, 0.0001)
            let input = CIImage(cgImage: bitmap.image)
            let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
            let context = CIContext(options: [.useSoftwareRenderer: false])
            guard let cg = context.createCGImage(blurred, from: input.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()) else {
                return nil
            }
            output = cg
        }
        let image = UIImage(cgImage: output)
        guard let data = image.jpegData(compressionQuality: 0.86) else { return nil }
        return (data, image)
    }
}

/// Выбранное фото, ждущее «Установить» или «Отмена».
struct WallpaperDraft: Identifiable {
    let id = UUID()
    let bitmap: WallpaperPhoto.Bitmap
    let preview: UIImage
    var dim: Double
    var blur: Double
}

/// «Обои чата»: своё фото для всех чатов (`.global`, из «Оформления») или для одного чата
/// или канала (из профиля). Фото выбирается системным окном выбора, доступ к медиатеке не нужен.
struct ChatWallpaperSettingsView: View {
    let scope: WallpaperScope
    let library: ChatWallpaperLibrary
    /// Встроенные обои из «Оформления»: видны, пока своего фото нет.
    let builtIn: ChatWallpaper

    @State private var pickerItem: PhotosPickerItem?
    @State private var draft: WallpaperDraft?
    @State private var reading = false
    @State private var problem: String?

    var body: some View {
        List {
            Section {
                AppearancePreview(wallpaper: builtIn, custom: shown)
                    .animation(MaxlyMotion.fade, value: shown)
                    .listRowBackground(Color.maxlyBackground)
            } header: {
                Text("Предпросмотр")
            }
            Section {
                PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .compatible) {
                    HStack(spacing: 12) {
                        Label(hasOwn ? "Выбрать другое фото" : "Выбрать фото", systemImage: "photo.on.rectangle")
                        Spacer(minLength: 8)
                        if reading { ProgressView() }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .disabled(reading)
                if hasOwn {
                    Button(role: .destructive) {
                        library.reset(scope)
                    } label: {
                        Label("Сбросить обои", systemImage: "arrow.counterclockwise")
                            .frame(minHeight: 44)
                    }
                }
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle(scope == .global ? "Обои чата" : "Обои")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task { await read(item) }
        }
        .fullScreenCover(item: $draft) { current in
            WallpaperPreviewView(draft: current) { dim, blur in
                await apply(current, dim: dim, blur: blur)
            } onCancel: {
                draft = nil
            }
        }
        .alert(
            problem ?? "",
            isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    private var hasOwn: Bool { library.hasOwn(scope) }

    /// Что сейчас за лентой этого чата (или всех чатов): своё фото, иначе встроенные.
    private var shown: CustomWallpaperBackdrop? {
        switch scope {
        case .global: library.backdrop(for: .global)
        case .chat(let id): library.backdrop(chatId: id)
        }
    }

    private var footer: String {
        switch scope {
        case .global:
            "Своё фото за сообщениями во всех чатах и каналах. Оно хранится только на этом устройстве."
        case .chat:
            hasOwn
                ? "Фото только для этого чата. «Сбросить обои» вернёт общие обои из „Оформления“."
                : "Фото только для этого чата, хранится на этом устройстве. Пока его нет, здесь общие обои из „Оформления“."
        }
    }

    private func read(_ item: PhotosPickerItem) async {
        reading = true
        defer { reading = false }
        let cover = WallpaperPhoto.cover()
        let pixels = CGSize(width: cover.points.width * cover.scale, height: cover.points.height * cover.scale)
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            problem = "Не удалось прочитать фото"
            return
        }
        let bitmap = await Task.detached(priority: .userInitiated) { WallpaperPhoto.decode(data, pixels: pixels) }.value
        guard let bitmap else {
            problem = "Не удалось прочитать фото"
            return
        }
        let current = library.wallpaper(for: scope)
        draft = WallpaperDraft(
            bitmap: bitmap,
            preview: UIImage(cgImage: bitmap.image),
            dim: current?.dim ?? CustomWallpaper.defaultDim,
            blur: current?.blur ?? CustomWallpaper.defaultBlur
        )
    }

    private func apply(_ current: WallpaperDraft, dim: Double, blur: Double) async {
        let cover = WallpaperPhoto.cover().points
        let bitmap = current.bitmap
        let rendered = await Task.detached(priority: .userInitiated) { () -> RenderedWallpaper? in
            WallpaperPhoto.render(bitmap, blur: blur, coverPoints: cover).map { RenderedWallpaper(data: $0.data, image: $0.image) }
        }.value
        guard let rendered else {
            draft = nil
            problem = "Не удалось подготовить фото"
            return
        }
        if library.apply(image: rendered.data, dim: dim, blur: blur, for: scope), let saved = library.backdrop(for: scope) {
            // Экран чата покажет новую картинку сразу, без чтения файла.
            CustomWallpaperImages.store(rendered.image, for: saved.url)
        } else {
            problem = library.errorMessage ?? "Не удалось сохранить обои"
            library.errorMessage = nil
        }
        draft = nil
    }
}

private struct RenderedWallpaper: @unchecked Sendable {
    let data: Data
    let image: UIImage
}

/// Предпросмотр перед «Установить»: фото за двумя пузырями, ползунки затемнения и размытия.
/// Здесь размытие рисуется на лету: экран не прокручивается, а в чат идёт уже размытая картинка.
struct WallpaperPreviewView: View {
    let draft: WallpaperDraft
    let onApply: @MainActor (Double, Double) async -> Void
    let onCancel: @MainActor () -> Void

    @State private var dim: Double
    @State private var blur: Double
    @State private var applying = false
    @Environment(\.colorScheme) private var colorScheme

    init(draft: WallpaperDraft, onApply: @escaping @MainActor (Double, Double) async -> Void, onCancel: @escaping @MainActor () -> Void) {
        self.draft = draft
        self.onApply = onApply
        self.onCancel = onCancel
        _dim = State(initialValue: draft.dim)
        _blur = State(initialValue: draft.blur)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Предпросмотр")
                .font(.app(.headline))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 4)
            Spacer(minLength: 16)
            WallpaperSampleBubbles()
                .padding(.horizontal, 6)
                .padding(.bottom, 16)
            controls
        }
        .background { photo }
        // Пузыри берут подложку «на обоях», как в чате с картинкой за лентой.
        .environment(\.chatWallpaper, .autumn)
        .interactiveDismissDisabled(applying)
    }

    private var photo: some View {
        Color.clear
            .overlay {
                Image(uiImage: draft.preview)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: CustomWallpaper.blurRadius(blur), opaque: true)
            }
            .overlay { Color.black.opacity(CustomWallpaper.dimOpacity(dim, dark: colorScheme == .dark)) }
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            slider("Затемнение", value: $dim, range: CustomWallpaper.dimRange, low: "sun.max", high: "moon.fill")
            slider("Размытие", value: $blur, range: CustomWallpaper.blurRange, low: "drop", high: "drop.fill")
            HStack(spacing: 12) {
                Button {
                    onCancel()
                } label: {
                    Text("Отмена")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .disabled(applying)
                Button {
                    applying = true
                    Task {
                        await onApply(dim, blur)
                        applying = false
                    }
                } label: {
                    ZStack {
                        Text("Установить").opacity(applying ? 0 : 1)
                        if applying { ProgressView().tint(.white) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.maxlyAccent)
                .disabled(applying)
                .accessibilityLabel("Установить")
            }
            .font(.app(.headline))
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground).opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, low: String, high: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                Text(CustomWallpaper.percent(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.app(.subheadline))
            Slider(value: value, in: range) {
                Text(title)
            } minimumValueLabel: {
                Image(systemName: low).accessibilityHidden(true)
            } maximumValueLabel: {
                Image(systemName: high).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .accessibilityValue(CustomWallpaper.percent(value.wrappedValue))
            .disabled(applying)
        }
    }
}

/// Два пузыря из настоящих компонентов: видно, как сообщения лягут на фото.
struct WallpaperSampleBubbles: View {
    private let incoming: Message
    private let outgoing: Message

    init(now: Date = Date()) {
        incoming = Message(
            id: "wallpaper-preview-1",
            chatId: "wallpaper-preview",
            authorId: "peer",
            text: "Смотри, какие обои получились!",
            timestamp: now,
            status: .sent
        )
        outgoing = Message(
            id: "wallpaper-preview-2",
            chatId: "wallpaper-preview",
            authorId: "me",
            text: "Красиво — оставляем",
            timestamp: now,
            status: .sent
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            MessageBubble(message: incoming, isOutgoing: false)
            MessageBubble(message: outgoing, isOutgoing: true)
        }
        .allowsHitTesting(false)
    }
}

/// Лист «Обои» из профиля чата или канала: свои обои только для этого чата.
struct ChatWallpaperSheet: View {
    let chatId: String
    let library: ChatWallpaperLibrary
    @Environment(\.chatWallpaper) private var builtIn
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ChatWallpaperSettingsView(scope: .chat(chatId), library: library, builtIn: builtIn)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { dismiss() }
                    }
                }
        }
    }
}
