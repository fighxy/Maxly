import SwiftUI
import AVFoundation
import CoreImage.CIFilterBuiltins
import UIKit
import MaxlyUI

/// Строка настроек как в системных Настройках: цветная плитка с символом и подпись.
struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    var badge: String?
    var subtitle: String?

    init(_ title: String, systemImage: String, tint: Color, badge: String? = nil, subtitle: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.badge = badge
        self.subtitle = subtitle
    }

    var body: some View {
        Label {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let badge {
                    Spacer()
                    Text(badge)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

/// Строка-кнопка в списке настроек: выглядит как обычная строка, без синего текста.
struct SettingsButtonRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    var isWorking = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                SettingsRowLabel(title, systemImage: systemImage, tint: tint)
                Spacer()
                if isWorking { ProgressView() }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
    }
}

/// Метка «Скоро» у пунктов, протокол которых ещё не подтверждён.
struct SoonBadge: View {
    var body: some View {
        Text("Скоро")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}

/// Экран-заглушка для разделов, которые ещё не описаны.
struct PlaceholderSettingsView: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text("Скоро здесь появятся настройки")
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// QR-код ссылки: CoreImage, коррекция M, чёрный на белом.
enum QRCode {
    static func image(for text: String, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Лист со ссылкой: QR-код, сама ссылка, «Поделиться» ссылкой и картинкой, «Скопировать».
struct LinkQRSheet: View {
    let title: String
    let caption: String
    let link: URL?
    /// Текст для «Поделиться ссылкой»; ссылка добавляется в конец.
    var shareMessage: String?
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Group {
                if let link {
                    content(link)
                } else {
                    ContentUnavailableView {
                        Label("Ссылки пока нет", systemImage: "link")
                    } description: {
                        Text("Сервер MAX ещё не прислал ссылку. Попробуйте позже.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func content(_ link: URL) -> some View {
        let qr = QRCode.image(for: link.absoluteString)
        return ScrollView {
            VStack(spacing: 20) {
                if let qr {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .frame(maxWidth: 280)
                        .accessibilityLabel("QR-код ссылки")
                }
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(link.absoluteString)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    ShareLink(item: link, message: shareMessage.map { Text($0) }) {
                        Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Color.maxlyOnAccent)
                    if let qr {
                        let image = Image(uiImage: qr)
                        ShareLink(item: image, preview: SharePreview(title, image: image)) {
                            Label("Поделиться QR-кодом", systemImage: "qrcode")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    Button {
                        UIPasteboard.general.url = link
                        copied = true
                    } label: {
                        Label(copied ? "Скопировано" : "Скопировать ссылку", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding(24)
        }
    }
}

/// JPEG для аватара: до 1280 px по длинной стороне, качество 0.85.
enum AvatarJPEG {
    static func make(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return make(from: image)
    }

    static func make(from image: UIImage, maxSide: CGFloat = 1280) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

/// Доступ к камере: системный запрос при первом обращении.
@MainActor
enum CameraAccess {
    enum Result { case granted, denied, unavailable }

    static func request() async -> Result {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .granted
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        default:
            return .denied
        }
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// Системная камера для снимка аватара. У SwiftUI своей нет.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
