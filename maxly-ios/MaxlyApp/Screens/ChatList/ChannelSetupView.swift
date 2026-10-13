import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Настройка нового канала, как в Max: «Приватный канал создан» (тип, ссылка-приглашение,
/// «Скопировать ссылку», «Отправить в MAX», «Продолжить»), затем «Выберите подписчиков».
struct ChannelSetupView: View {
    @Bindable var model: ChannelSetupModel
    let shareTargets: () -> [ChatListItem]
    let onDone: () -> Void
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.step {
                case .type: typeStep
                case .subscribers: subscribers
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) { banner }
            .animation(.snappy, value: model.notice)
        }
        .tint(Color.maxlyAccent)
        .task { await model.start() }
        .onChange(of: model.done) { _, done in if done { onDone() } }
        .alert(
            model.publicNotice?.title ?? "",
            isPresented: Binding(get: { model.publicNotice != nil }, set: { if !$0 { model.publicNotice = nil } }),
            presenting: model.publicNotice
        ) { _ in
            Button("Понятно", role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
        .sheet(isPresented: $sending) {
            ForwardPickerView(
                targets: shareTargets().filter { $0.id != model.chatId },
                onPick: { id in
                    sending = false
                    Task { await model.sendLink(to: id) }
                },
                onCancel: { sending = false },
                heading: "Отправить в MAX"
            )
        }
    }

    private var typeStep: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "party.popper.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.maxlyAccent)
                    Text("Приватный канал создан")
                        .font(.title2.weight(.semibold))
                    Text("Теперь его можно настроить")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            Section {
                typeRow("Приватный", "Канал доступен только по ссылке", selected: true) {}
                typeRow("Публичный", "Канал можно найти в поиске", selected: false) { model.askPublic(.public) }
                HStack {
                    Text(model.shortLink ?? "Ссылка появится через секунду…")
                        .foregroundStyle(model.link == nil ? .secondary : Color.maxlyAccent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Menu {
                        Button("Скопировать ссылку", systemImage: "doc.on.doc", action: copy)
                            .disabled(model.link == nil)
                        Button("Сбросить ссылку", systemImage: "arrow.clockwise") {
                            Task { await model.revokeLink() }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 32, height: 32)
                    }
                }
            } footer: {
                Text("Ссылка-приглашение в ваш канал")
            }
            Section {
                Button { model.askPublic(.business) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "briefcase")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Публичный для бизнеса").foregroundStyle(.primary)
                            Text("Для юрлиц, ИП, самозанятых и госорганизаций")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Section {
                Button("Скопировать ссылку", systemImage: "doc.on.doc", action: copy)
                    .disabled(model.link == nil)
                Button("Отправить в MAX", systemImage: "paperplane") { sending = true }
                    .disabled(model.link == nil || model.busy)
            }
        }
        .navigationTitle("Тип канала и ссылка")
        .safeAreaInset(edge: .bottom) {
            Button { model.next() } label: {
                Text("Продолжить").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, MaxlyTheme.pad)
            .padding(.bottom, 8)
        }
    }

    private var subscribers: some View {
        let now = Date()
        let rows = model.shown.map { ContactsViewModel.row(for: $0, now: now) }
        return List {
            if rows.isEmpty {
                Text(model.query.trimmingCharacters(in: .whitespaces).isEmpty ? "Контактов пока нет" : "Никого не нашлось")
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                Button { model.toggle(row.id) } label: {
                    HStack {
                        ContactRowView(row: row)
                        Spacer(minLength: 8)
                        Image(systemName: model.selected.contains(row.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(model.selected.contains(row.id) ? Color.maxlyAccent : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Найти по имени")
        .navigationTitle("Выберите подписчиков")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button {
                    Task { await model.addSubscribers() }
                } label: {
                    Text(model.selected.isEmpty ? "Добавить" : "Добавить (\(model.selected.count))").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selected.isEmpty || model.busy)
                Button { model.skip() } label: {
                    Text("Отменить").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.horizontal, MaxlyTheme.pad)
            .padding(.bottom, 8)
        }
    }

    private func typeRow(_ title: String, _ subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.maxlyAccent)
                    .opacity(selected ? 1 : 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func copy() {
        guard let link = model.link else { return }
        UIPasteboard.general.string = link
        model.linkCopied()
    }

    @ViewBuilder
    private var banner: some View {
        if let text = model.notice {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 72)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: text) {
                    try? await Task.sleep(for: .seconds(2.5))
                    if model.notice == text { model.notice = nil }
                }
        }
    }
}
