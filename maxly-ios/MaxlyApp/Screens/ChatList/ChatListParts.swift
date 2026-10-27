import SwiftUI

/// Подложка закреплённых папок: размытие под панелью навигации и под капсулой, которое к
/// низу тает, а не обрывается линией.
struct PinnedHeaderBackdrop: View {
    var body: some View {
        Rectangle()
            .fill(.bar)
            .mask {
                LinearGradient(
                    stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .padding(.bottom, -16)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}

/// Значок новой истории: пунктирный круг с плюсом.
struct AddStoryGlyph: View {
    var body: some View {
        ZStack {
            Image(systemName: "circle.dashed")
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
        }
    }
}

/// Новое сообщение. Выбрать собеседника можно будет, когда появится список контактов.
struct ComposeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Новое сообщение",
                systemImage: "square.and.pencil",
                description: Text("Выбор собеседника появится вместе со списком контактов. Пока напишите из существующего чата.")
            )
            .navigationTitle("Новое сообщение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
