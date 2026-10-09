import SwiftUI
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// «Сведения» о сообщении: время отправки и правки, пересылка, прочтение (docs/readers.md).
struct MessageInfoView: View {
    @Bindable var model: MessageInfoViewModel
    /// Касание строки читателя: открыть личный чат с ним. `nil` — строки не нажимаются.
    var onOpenReader: ((MessageReader) -> Void)?
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Отправлено", value: model.sentText, systemImage: "paperplane")
                    if let edited = model.editedText {
                        if edited == MessageInfoViewModel.editedWithoutTime {
                            row("Изменено", value: nil, systemImage: "pencil")
                        } else {
                            row("Изменено", value: edited, systemImage: "pencil")
                        }
                    }
                    if let forwarded = model.forwardedFrom {
                        row("Переслано из", value: forwarded, systemImage: "arrowshape.turn.up.right")
                    }
                    if let status = model.readStatus {
                        row(status.title, value: nil, systemImage: status == .read ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                }
                readers
            }
            .navigationTitle("Сведения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", action: onClose)
                }
            }
            .task { await model.load() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ title: String, value: String?, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.orbitleAccent)
                .frame(width: 24)
            Text(title)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var readers: some View {
        switch model.readers {
        case .hidden:
            EmptyView()
        case .loading:
            Section(MessageInfoViewModel.readersTitle) {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        case .failed(let message):
            Section(MessageInfoViewModel.readersTitle) {
                VStack(spacing: 12) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Повторить") { Task { await model.load() } }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        case .loaded(let list):
            Section(MessageInfoViewModel.readersTitle) {
                if list.isEmpty {
                    Text(MessageInfoViewModel.emptyReaders)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                ForEach(list) { reader in
                    if let onOpenReader {
                        Button { onOpenReader(reader) } label: { readerRow(reader) }
                            .buttonStyle(.plain)
                    } else {
                        readerRow(reader)
                    }
                }
            }
        }
    }

    private func readerRow(_ reader: MessageReader) -> some View {
        HStack(spacing: 12) {
            AvatarView(title: MessageInfoViewModel.name(of: reader), id: reader.userId, url: reader.avatarURL, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(MessageInfoViewModel.name(of: reader))
                    .lineLimit(1)
                if let detail = model.readerDetail(reader) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let reaction = reader.reaction {
                Text(reaction)
                    .font(.title3)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
