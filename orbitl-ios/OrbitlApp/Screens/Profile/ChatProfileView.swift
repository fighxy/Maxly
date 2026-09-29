import SwiftUI
import UIKit
import OrbitlDomain
import OrbitlPresentation
import OrbitlUI

/// Профиль собеседника, бота, группы или канала: системный сгруппированный список.
///
/// Шапка (аватар, имя, статус) видна сразу по данным из списка чатов, остальное
/// подгружается с сервера.
struct ChatProfileView: View {
    @Bindable var viewModel: ChatProfileViewModel
    /// Открыть переписку. `nil`, когда профиль открыт из самого чата: туда ведёт «назад».
    var onWrite: (() -> Void)?

    @Environment(\.openURL) private var openURL
    @State private var copied: String?

    var body: some View {
        List {
            header
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            actions
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            content
        }
        .listStyle(.insetGrouped)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .overlay(alignment: .bottom) {
            if let copied {
                Text(copied)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: copied)
    }

    // MARK: Шапка

    private var header: some View {
        VStack(spacing: 10) {
            AvatarView(
                title: viewModel.title,
                id: viewModel.shown.peerId ?? viewModel.chatId,
                url: viewModel.shown.avatarURL,
                size: 104,
                isOnline: viewModel.isOnline
            )
            .overlay(alignment: .bottomTrailing) {
                if viewModel.shown.kind == .bot {
                    badge(systemImage: "cpu", color: .orbitlAccent)
                } else if viewModel.shown.kind == .channel {
                    badge(systemImage: "megaphone.fill", color: .orange)
                }
            }
            HStack(spacing: 6) {
                Text(viewModel.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                if viewModel.isOfficial {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.orbitlAccent)
                        .accessibilityLabel("Официальный")
                }
            }
            Text(viewModel.subtitle)
                .font(.subheadline)
                .foregroundStyle(viewModel.isOnline ? AnyShapeStyle(Color.orbitlAccent) : AnyShapeStyle(.secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }

    private func badge(systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(color))
            .overlay(Circle().strokeBorder(Color(uiColor: .systemGroupedBackground), lineWidth: 3))
            .offset(x: 2, y: 2)
            .accessibilityHidden(true)
    }

    // MARK: Кнопки

    @ViewBuilder
    private var actions: some View {
        let write = viewModel.canWrite ? onWrite : nil
        if write != nil || viewModel.shareURL != nil {
            HStack(spacing: 10) {
                if let write {
                    actionButton("Написать", systemImage: "message.fill", action: write)
                }
                if let url = viewModel.shareURL {
                    ShareLink(item: url) {
                        actionLabel("Поделиться", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    actionButton("Ссылка", systemImage: "link") {
                        copy(url.absoluteString, message: "Ссылка скопирована")
                    }
                }
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
            Text(title)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(Color.orbitlAccent)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    // MARK: Сведения

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            Section {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        case .failed(let message):
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("Повторить") { Task { await viewModel.load() } }
                }
                .padding(.vertical, 4)
            }
        case .loaded:
            let rows = viewModel.infoRows
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        infoRow(row)
                    }
                }
            }
            let commands = viewModel.commands
            if !commands.isEmpty {
                Section("Команды") {
                    ForEach(commands) { command in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(command.command)
                                .font(.body.monospaced())
                                .foregroundStyle(Color.orbitlAccent)
                            if let description = command.description {
                                Text(description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            Button("Скопировать", systemImage: "doc.on.doc") {
                                copy(command.command, message: "Команда скопирована")
                            }
                        }
                    }
                }
            }
            if rows.isEmpty, commands.isEmpty {
                Section {
                    Text("Других сведений нет")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func infoRow(_ row: ChatProfileViewModel.InfoRow) -> some View {
        Button {
            perform(row)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(row.value)
                    .font(.body)
                    .foregroundStyle(isLink(row) ? AnyShapeStyle(Color.orbitlAccent) : AnyShapeStyle(.primary))
                    .lineLimit(row.isMultiline ? nil : 1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: row.isMultiline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Скопировать", systemImage: "doc.on.doc") {
                copy(row.value, message: "Скопировано")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func isLink(_ row: ChatProfileViewModel.InfoRow) -> Bool {
        switch row.action {
        case .call, .open: true
        case .copy, nil: false
        }
    }

    private func perform(_ row: ChatProfileViewModel.InfoRow) {
        switch row.action {
        case .call(let url), .open(let url):
            openURL(url)
        case .copy:
            copy(row.value, message: "Скопировано")
        case nil:
            break
        }
    }

    private func copy(_ text: String, message: String) {
        UIPasteboard.general.string = text
        copied = message
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if copied == message { copied = nil }
        }
    }
}

/// Профиль, модель которого создаётся один раз при переходе, а не при каждой перерисовке
/// экрана, откуда перешли: иначе загруженная карточка терялась бы.
struct ProfileDestination: View {
    let make: () -> ChatProfileViewModel?
    var onWrite: (() -> Void)?
    @State private var model: ChatProfileViewModel?

    var body: some View {
        Group {
            if let model {
                ChatProfileView(viewModel: model, onWrite: onWrite)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if model == nil { model = make() }
        }
    }
}
