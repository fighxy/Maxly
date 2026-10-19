import SwiftUI
import PhotosUI
import CoreImage
import ImageIO
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Фото из медиатеки для обоев: копия с длинной стороной до 2560 пикселей и поворотом по EXIF
/// делается сразу после выбора. Размытая копия строится один раз, а не на каждый кадр.
enum WallpaperPhoto {
    /// Картинка переходит между потоками только как неизменяемый результат.
    struct Bitmap: @unchecked Sendable {
        let image: CGImage
    }

    /// Какую площадь в пунктах обои закрывают: на iPhone — портретный экран, на iPad — квадрат по
    /// длинной стороне (обе ориентации). По ней радиус размытия переводится в пиксели фото.
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

    /// Копия фото: длинная сторона не больше `CustomWallpaperStyle.maxSide`, маленькие не растягиваются.
    static func decode(_ data: Data) -> Bitmap? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let target = CustomWallpaperStyle.target(width: width, height: height)
        let longest = width > 0 && height > 0 ? max(target.width, target.height) : CustomWallpaperStyle.maxSide
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Bitmap(image: image)
    }

    static func jpeg(_ image: CGImage) -> Data? {
        UIImage(cgImage: image).jpegData(compressionQuality: 0.86)
    }

    /// Размытая копия фото `source` в `target`: радиус `CustomWallpaperStyle.blurRadius` в пунктах
    /// экрана пересчитан в пиксели фото при заполнении `coverPoints`, края не темнеют.
    static func blurredCopy(of source: URL, to target: URL, coverPoints: CGSize) -> UIImage? {
        guard let input = CIImage(contentsOf: source, options: [.applyOrientationProperty: true]) else { return nil }
        let size = input.extent.size
        guard size.width > 0, size.height > 0 else { return nil }
        let pointsPerPixel = max(coverPoints.width / size.width, coverPoints.height / size.height)
        let sigma = CustomWallpaperStyle.blurRadius / max(Double(pointsPerPixel), 0.0001)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let image = context.createCGImage(blurred, from: input.extent, format: .RGBA8, colorSpace: space) else { return nil }
        if let data = jpeg(image) { try? data.write(to: target, options: .atomic) }
        return UIImage(cgImage: image)
    }
}

/// Выбранное фото, ждущее «Установить» или «Отмена».
struct WallpaperDraft: Identifiable {
    let id = UUID()
    let bitmap: WallpaperPhoto.Bitmap
    let preview: UIImage
}

/// Выбор своего фото для `scope`: системное окно выбора (идёт вне приложения, разрешение на
/// медиатеку не нужно), затем предпросмотр с «Установить» и «Отмена».
struct WallpaperPhotoFlow: ViewModifier {
    @Binding var isPresented: Bool
    let scope: WallpaperScope
    let library: ChatWallpaperLibrary

    @State private var item: PhotosPickerItem?
    @State private var draft: WallpaperDraft?
    @State private var problem: String?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $item, matching: .images, preferredItemEncoding: .compatible)
            .onChange(of: item) { _, picked in
                guard let picked else { return }
                item = nil
                Task { await read(picked) }
            }
            .fullScreenCover(item: $draft) { current in
                WallpaperPreviewView(draft: current, library: library) {
                    await apply(current)
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

    private func read(_ picked: PhotosPickerItem) async {
        guard let data = try? await picked.loadTransferable(type: Data.self),
              let bitmap = await Task.detached(priority: .userInitiated, operation: { WallpaperPhoto.decode(data) }).value else {
            problem = "Не удалось открыть фото"
            return
        }
        draft = WallpaperDraft(bitmap: bitmap, preview: UIImage(cgImage: bitmap.image))
    }

    private func apply(_ current: WallpaperDraft) async {
        let bitmap = current.bitmap
        let data = await Task.detached(priority: .userInitiated) { WallpaperPhoto.jpeg(bitmap.image) }.value
        draft = nil
        guard let data, library.setPhoto(data, for: scope) else {
            problem = library.errorMessage ?? "Не удалось сохранить обои"
            library.errorMessage = nil
            return
        }
        // Экран чата покажет новую копию сразу, без чтения файла.
        let backdrop: CustomWallpaperBackdrop? = switch scope {
        case .global: library.globalBackdrop
        case .chat(let key): library.background(chatKey: key).photo
        }
        if let backdrop { CustomWallpaperImages.store(current.preview, for: backdrop.url) }
    }
}

extension View {
    func wallpaperPhotoFlow(isPresented: Binding<Bool>, scope: WallpaperScope, library: ChatWallpaperLibrary) -> some View {
        modifier(WallpaperPhotoFlow(isPresented: isPresented, scope: scope, library: library))
    }

    /// То же для чата, когда обоев чата может не быть (профиль не из чата).
    @ViewBuilder
    func chatWallpaperPhotoFlow(isPresented: Binding<Bool>, chatKey: String?, library: ChatWallpaperLibrary?) -> some View {
        if let chatKey, let library {
            wallpaperPhotoFlow(isPresented: isPresented, scope: .chat(chatKey), library: library)
        } else {
            self
        }
    }
}

/// Предпросмотр перед «Установить»: фото за двумя пузырями с общими затемнением и размытием
/// (их меняют в «Оформлении»). Размытие здесь рисуется на лету: экран не прокручивается, а в
/// чате потом показывается готовая размытая копия.
struct WallpaperPreviewView: View {
    let draft: WallpaperDraft
    let library: ChatWallpaperLibrary
    let onApply: @MainActor () async -> Void
    let onCancel: @MainActor () -> Void

    @State private var applying = false

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
        .environment(\.chatHasPhotoWallpaper, true)
        .interactiveDismissDisabled(applying)
    }

    private var photo: some View {
        Color.clear
            .overlay {
                Image(uiImage: draft.preview)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: library.blur ? CustomWallpaperStyle.blurRadius : 0, opaque: true)
            }
            .overlay { Color.black.opacity(CustomWallpaperStyle.dimOpacity(library.dimPercent)) }
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    private var controls: some View {
        VStack(spacing: 14) {
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
                        await onApply()
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
}

/// «Затемнение — N %» (0–60) и «Размытие»: общие для всех фото обоев, меняются сразу.
struct WallpaperStyleControls: View {
    let library: ChatWallpaperLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CustomWallpaperStyle.dimCaption(library.dimPercent))
                .monospacedDigit()
            Slider(
                value: Binding(
                    get: { Double(library.dimPercent) },
                    set: { library.setDim(Int($0.rounded())) }
                ),
                in: Double(CustomWallpaperStyle.minDim)...Double(CustomWallpaperStyle.maxDim),
                step: 1
            ) {
                Text("Затемнение")
            } minimumValueLabel: {
                Image(systemName: "sun.max").accessibilityHidden(true)
            } maximumValueLabel: {
                Image(systemName: "moon.fill").accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .accessibilityValue("\(library.dimPercent)\u{00A0}%")
            Toggle("Размытие", isOn: Binding(get: { library.blur }, set: { library.setBlur($0) }))
                .frame(minHeight: 44)
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

/// Строки своего фото в разделе «Обои чата» «Оформления»: «Выбрать фото…», «Сбросить», а когда
/// фото есть — «Затемнение — N %» и «Размытие».
struct CustomWallpaperRows: View {
    let library: ChatWallpaperLibrary
    /// Открыть выбор фото: окно выбора и предпросмотр висят на экране «Оформление».
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            Label("Выбрать фото…", systemImage: "photo.on.rectangle")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        Button(role: .destructive) {
            library.resetGlobal()
        } label: {
            Label("Сбросить", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .disabled(!library.hasGlobalPhoto)
        if library.hasGlobalPhoto {
            WallpaperStyleControls(library: library)
        }
    }
}

/// «Обои» в «Ещё» профиля чата: «Своё фото…», «Как в общих», «Без обоев»; выбранное — с галочкой.
struct ChatWallpaperMenu: View {
    let chatKey: String
    let library: ChatWallpaperLibrary
    let onPickPhoto: () -> Void

    var body: some View {
        let choice = library.choice(chatKey: chatKey)
        Menu {
            Button(action: onPickPhoto) {
                Label("Своё фото…", systemImage: isPhoto(choice) ? "checkmark" : "photo")
            }
            Button {
                library.setChoice(.global, chatKey: chatKey)
            } label: {
                Label("Как в общих", systemImage: choice == .global ? "checkmark" : "photo.on.rectangle")
            }
            Button {
                library.setChoice(.plain, chatKey: chatKey)
            } label: {
                Label("Без обоев", systemImage: choice == .plain ? "checkmark" : "rectangle.slash")
            }
        } label: {
            Label("Обои", systemImage: "photo.on.rectangle")
        }
    }

    private func isPhoto(_ choice: ChatWallpaperChoice) -> Bool {
        if case .photo = choice { true } else { false }
    }
}
