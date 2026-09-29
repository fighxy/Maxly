import SwiftUI
import UIKit
import OrbitlePresentation
import OrbitleUI

/// Вкладка «Звонки»: переключатель «Все» / «Пропущенные» в панели навигации
/// (на iOS 26 — на стекле), строки «Создать звонок» и «Присоединиться», история.
struct CallsView: View {
    @Bindable var viewModel: CallsViewModel
    /// Открыть чат собеседника.
    let onOpenChat: (String) -> Void

    @State private var showsCallsUnavailable = false
    @State private var isJoining = false
    @State private var joinLink = ""

    var body: some View {
        List {
            Section {
                actionRow("Создать звонок", systemImage: "link") {
                    if viewModel.canCreateCall {
                        Task { await viewModel.createCallLink() }
                    } else {
                        showsCallsUnavailable = true
                    }
                }
                actionRow("Присоединиться", systemImage: "person.badge.plus") {
                    if viewModel.canJoin {
                        joinLink = ""
                        isJoining = true
                    } else {
                        showsCallsUnavailable = true
                    }
                }
            }
            history
        }
        .listStyle(.plain)
        .navigationTitle("Звонки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Звонки", selection: $viewModel.filter) {
                    ForEach(CallsViewModel.Filter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
        }
        .animation(.default, value: viewModel.filter)
        .task { viewModel.activate() }
        .alert("Звонки пока недоступны", isPresented: $showsCallsUnavailable) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Эта версия Orbitle ещё не умеет начинать звонки и подключаться к ним.")
        }
        .alert("Присоединиться к звонку", isPresented: $isJoining) {
            TextField("Ссылка на звонок", text: $joinLink)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            Button("Отмена", role: .cancel) {}
            Button("Войти") {
                Task { await viewModel.join(link: joinLink) }
            }
        }
        .alert("Не получилось", isPresented: errorShown) {
            Button("Понятно", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(item: createdLink) { link in
            CallLinkSheet(link: link.url)
        }
    }

    @ViewBuilder
    private var history: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .listRowSeparator(.hidden)
        case .unavailable:
            placeholder(
                "История звонков недоступна",
                systemImage: "phone",
                description: "Звонки появятся, когда Orbitle научится получать их с сервера."
            )
        case .empty:
            if viewModel.filter == .missed {
                placeholder("Нет пропущенных звонков", systemImage: "phone.arrow.down.left", description: nil)
            } else {
                placeholder("Звонков пока нет", systemImage: "phone", description: "Здесь появится история ваших звонков.")
            }
        case .ready:
            Section {
                ForEach(viewModel.rows) { row in
                    Button {
                        if let chatId = row.chatId { onOpenChat(chatId) }
                    } label: {
                        CallRowView(row: row)
                    }
                    .accessibilityLabel(row.accessibilityLabel)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await viewModel.delete(row) }
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    /// Строка действия: значок в колонке аватаров, текст акцентным цветом.
    private func actionRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: OrbitleTheme.smallAvatar)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.orbitleAccent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    private func placeholder(_ title: String, systemImage: String, description: String?) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: description.map { Text($0) })
            .padding(.top, 40)
            .listRowSeparator(.hidden)
    }

    private var errorShown: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil && !isJoining },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }

    private var createdLink: Binding<CreatedLink?> {
        Binding(
            get: { viewModel.createdLink.map(CreatedLink.init) },
            set: { if $0 == nil { viewModel.createdLink = nil } }
        )
    }
}

/// Обёртка ссылки для `.sheet(item:)`.
struct CreatedLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Созданная ссылка на звонок: поделиться или скопировать.
struct CallLinkSheet: View {
    let link: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(link.absoluteString)
                        .textSelection(.enabled)
                } footer: {
                    Text("Отправьте ссылку тем, кого хотите позвать в звонок.")
                }
                Section {
                    ShareLink(item: link) {
                        Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.url = link
                    } label: {
                        Label("Скопировать", systemImage: "doc.on.doc")
                    }
                }
            }
            .navigationTitle("Новый звонок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .tint(Color.orbitleAccent)
        .presentationDetents([.medium])
    }
}

/// Строка истории: аватар или значок группового звонка, имя со счётчиком,
/// направление и статус, дата справа. Пропущенные — красным.
struct CallRowView: View {
    let row: CallRow

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body)
                    .foregroundStyle(row.isMissed ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: row.directionSymbol)
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text(row.status)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .foregroundStyle(row.isMissed ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 8)
            Text(row.dateText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var avatar: some View {
        if row.isGroup {
            Image(systemName: "person.2.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.orbitleAccent)
                .frame(width: OrbitleTheme.smallAvatar, height: OrbitleTheme.smallAvatar)
                .background(Color.orbitleAccent.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
        } else {
            AvatarView(title: row.name, id: row.peerId, url: row.avatarURL, size: OrbitleTheme.smallAvatar)
        }
    }
}
