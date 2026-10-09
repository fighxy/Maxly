import QuickLook
import SwiftUI

/// Системный просмотр скачанного файла. Заголовок — имя вложения, а не имя во временной папке.
struct FileQuickLook: View {
    let url: URL
    let title: String
    let onClose: () -> Void
    @State private var exporting = false
    @State private var saved = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Preview(url: url, title: title)
                .ignoresSafeArea()
            HStack(spacing: 12) {
                // Документ — в «Файлы» (любая папка, iCloud Drive) или в другое приложение.
                ShareLink(item: url) {
                    circle("square.and.arrow.up")
                }
                .accessibilityLabel("Поделиться")
                Button {
                    exporting = true
                } label: {
                    circle(saved ? "checkmark" : "folder")
                }
                .accessibilityLabel("Сохранить в Файлы")
                Button(action: onClose) {
                    circle("xmark")
                }
                .accessibilityLabel("Закрыть")
            }
            .padding(16)
        }
        .background(Color.black)
        .sheet(isPresented: $exporting) {
            FileExportPicker(urls: [url]) { done in
                exporting = false
                if done { saved = true }
            }
            .ignoresSafeArea()
        }
    }

    private func circle(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(.black.opacity(0.45), in: Circle())
    }
}

private struct Preview: UIViewControllerRepresentable {
    let url: URL
    let title: String

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url, title: title) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let item: Item
        init(url: URL, title: String) { item = Item(url: url, title: title) }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            item
        }
    }

    final class Item: NSObject, QLPreviewItem {
        let url: URL
        let title: String
        init(url: URL, title: String) {
            self.url = url
            self.title = title
        }

        var previewItemURL: URL? { url }
        var previewItemTitle: String? { title }
    }
}
