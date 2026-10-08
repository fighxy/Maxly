import SwiftUI
import UIKit
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Нижняя панель режима выбора: «Копировать», «Переслать», «Удалить» в стеклянной капсуле
/// на месте поля ввода.
struct MessageSelectionBar: View {
    let selection: MessageSelectionModel
    let messages: [Message]

    var body: some View {
        let count = selection.selected(in: messages).count
        let canForward = selection.canForward(in: messages)
        let canDelete = selection.deleteOptions(in: messages).canDelete
        OrbitleGlassGroup(spacing: 8) {
            HStack(spacing: 0) {
                action("Копировать", systemImage: "doc.on.doc", enabled: count > 0) {
                    selection.copy(in: messages) { UIPasteboard.general.string = $0 }
                }
                action("Переслать", systemImage: "arrowshape.turn.up.right", enabled: canForward) {
                    selection.requestForward(in: messages)
                }
                action("Удалить", systemImage: "trash", role: .destructive, enabled: canDelete) {
                    Task { await selection.requestDelete(in: messages) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .orbitleGlassCapsule()
        }
        .padding(.horizontal, OrbitleTheme.pad)
        .padding(.vertical, 8)
    }

    private func action(_ title: String, systemImage: String, role: ButtonRole? = nil, enabled: Bool, run: @escaping () -> Void) -> some View {
        Button(role: role, action: run) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.red : Color.orbitleAccent)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Подтверждение удаления выбранного: переключатель «Удалить у всех» — только если правила
/// разрешают его для каждого выбранного сообщения; включён сразу.
struct MessageSelectionDeleteSheet: View {
    let request: MessageSelectionModel.DeleteRequest
    let chatType: ChatType
    let onDelete: (Bool) -> Void
    let onCancel: () -> Void
    @State private var forEveryone: Bool

    init(request: MessageSelectionModel.DeleteRequest, chatType: ChatType, onDelete: @escaping (Bool) -> Void, onCancel: @escaping () -> Void) {
        self.request = request
        self.chatType = chatType
        self.onDelete = onDelete
        self.onCancel = onCancel
        _forEveryone = State(initialValue: request.options.forEveryoneByDefault)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(request.title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if request.options.forcesForEveryone {
                Text("Сообщения удалятся у всех подписчиков. Восстановить их не получится.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if request.options.showsForEveryone {
                Toggle(chatType == .private ? "Удалить у всех (и у собеседника)" : "Удалить у всех", isOn: $forEveryone)
                    .tint(.orbitleAccent)
            }
            VStack(spacing: 8) {
                Button(role: .destructive) {
                    onDelete(forEveryone)
                } label: {
                    Text("Удалить").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                Button("Отмена", role: .cancel, action: onCancel)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .presentationDetents([.height(request.options.showsForEveryone || request.options.forcesForEveryone ? 270 : 220)])
        .presentationDragIndicator(.visible)
    }
}
