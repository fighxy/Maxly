import SwiftUI
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Лист нового опроса: вопрос и два ответа. Поля живут в самом листе, а не в экране чата.
struct PollComposerSheet: View {
    let onSend: (_ title: String, _ answers: [String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var first = ""
    @State private var second = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Вопрос", text: $title)
                TextField("Ответ 1", text: $first)
                TextField("Ответ 2", text: $second)
            }
            .navigationTitle("Опрос")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить") {
                        dismiss()
                        onSend(title, [first, second])
                    }
                    .disabled(!ready)
                }
            }
        }
    }

    /// Опрос уходит, когда заполнены оба ответа.
    private var ready: Bool {
        !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !second.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Лист «Отправить позже»: запланировать черновик поля ввода, изменить, отправить сейчас или
/// отменить запланированное.
struct ScheduleMessageSheet: View {
    let viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date().addingTimeInterval(3600)
    @State private var editing: FoundMessage?
    @State private var editText = ""

    var body: some View {
        NavigationStack {
            Form {
                if !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Новое") {
                        DatePicker("Когда", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        Button("Запланировать") {
                            dismiss()
                            Task { await viewModel.schedule(text: viewModel.draft, at: date) }
                        }
                    }
                }
                Section("Запланированные") {
                    if viewModel.scheduledItems.isEmpty {
                        Text("Пока ничего не ждёт отправки")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.scheduledItems, id: \.messageId) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.text).lineLimit(2)
                            if let date = item.date {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Сейчас") { Task { await viewModel.sendScheduledNow(item) } }
                                .tint(.maxlyAccent)
                            Button("Отменить", role: .destructive) { Task { await viewModel.cancelScheduled(item) } }
                        }
                        .onTapGesture {
                            editing = item
                            editText = item.text
                            date = item.date ?? Date().addingTimeInterval(3600)
                        }
                    }
                }
                if editing != nil {
                    Section("Изменить") {
                        TextField("Текст", text: $editText, axis: .vertical)
                        DatePicker("Когда", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        Button("Сохранить") {
                            guard let item = editing else { return }
                            editing = nil
                            Task { await viewModel.editScheduled(item, text: editText, at: date) }
                        }
                        .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Отправить позже")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
            .task {
                await viewModel.loadScheduled()
            }
        }
    }
}
