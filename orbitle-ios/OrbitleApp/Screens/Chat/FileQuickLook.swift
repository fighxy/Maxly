import QuickLook
import SwiftUI

/// Системный просмотр скачанного файла. Заголовок — имя вложения, а не имя во временной папке.
struct FileQuickLook: View {
    let url: URL
    let title: String
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Preview(url: url, title: title)
                .ignoresSafeArea()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Закрыть")
        }
        .background(Color.black)
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
