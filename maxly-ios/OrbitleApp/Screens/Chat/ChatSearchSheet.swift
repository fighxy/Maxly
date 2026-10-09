import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Поиск принадлежит открытому листу: закрытие не оставляет результатов следующему открытию.
struct ChatSearchSheet: View {
    @Bindable var model: ChatViewModel
    let onSelect: (FoundMessage) -> Void
    @State private var query = ""
    @State private var searchPresented = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.searchHits, id: \.messageId) { hit in
                Button { onSelect(hit) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        PrivateText(hit.text.isEmpty ? "Сообщение" : hit.text, placeholder: PrivateModeMask.archivePreview)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                        if let date = hit.date {
                            Text(date, format: .dateTime.day().month().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Поиск в чате")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, isPresented: $searchPresented, prompt: "Сообщения")
            .overlay {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("Поиск сообщений", systemImage: "magnifyingglass", description: Text("Введите слово или фразу"))
                        .allowsHitTesting(false)
                } else if model.searchBusy {
                    ProgressView("Поиск…")
                } else if let error = model.searchError {
                    ContentUnavailableView {
                        Label("Поиск недоступен", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Повторить") { Task { await model.searchInChat(query) } }
                    }
                } else if model.searchHits.isEmpty {
                    ContentUnavailableView.search(text: query).allowsHitTesting(false)
                }
            }
            .task(id: query) { await model.searchInChat(query, debounce: .milliseconds(300)) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
        }
        .onDisappear { model.resetSearch() }
    }
}
