import SwiftUI
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Новое сообщение: контакт, номер, группа, канал или ссылка.
struct NewChatSheet: View {
    @Bindable var model: NewChatModel
    var onOpened: (NewChatOpened) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // Ветки прямо в `List`: вынесенный `some View` склеивает строки в одну ячейку.
            List {
                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .listRowSeparator(.hidden)
                }
                if let notice = model.notice {
                    Text(notice)
                        .foregroundStyle(Color.orbitleAccent)
                        .listRowSeparator(.hidden)
                }
                switch model.step {
                case .menu:
                    menuRow("Написать контакту", "Выбрать из списка") { model.open(.contact) }
                    menuRow("Написать новому", "Найти по номеру телефона") { model.open(.phone) }
                    menuRow("Создать группу", "Название и участники") { model.open(.group) }
                    menuRow("Создать канал", "Только название") { model.open(.channel) }
                    menuRow("Открыть по ссылке", "Приглашение в группу или канал") { model.open(.link) }
                case .contact:
                    queryField
                    if model.shownPeople.isEmpty {
                        emptyPeople
                    } else {
                        ForEach(model.shownPeople) { person in
                            personRow(person) {
                                model.writeTo(personId: person.id, title: person.displayName)
                            }
                        }
                    }
                case .phone:
                    TextField("Номер телефона", text: $model.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    Button("Найти") { model.lookup() }
                        .disabled(model.busy)
                    if let person = model.found {
                        VStack(alignment: .leading, spacing: 4) {
                            PrivateText(person.title, placeholder: PrivateModeMask.contactTitle)
                            Text(person.phone)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        TextField("Имя в контактах", text: $model.contactName)
                        Text("Можно оставить пустым")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Написать") { model.writeFound() }
                            .disabled(model.busy)
                        if person.added {
                            Text("В контактах")
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Добавить в контакты") { model.addFound() }
                                .disabled(model.busy)
                        }
                    }
                case .group:
                    titleField
                    queryField
                    Text("Участников можно не выбирать.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                    if model.shownPeople.isEmpty {
                        emptyPeople
                    } else {
                        ForEach(model.shownPeople) { person in
                            personRow(person) {
                                model.toggleMember(person.id)
                            }
                        }
                    }
                    Button("Создать группу") { model.createGroup() }
                        .disabled(model.busy)
                case .channel:
                    titleField
                    Button("Создать канал") { model.createChannel() }
                        .disabled(model.busy)
                case .link:
                    TextField("Ссылка или код приглашения", text: $model.link)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Открыть") { model.joinLink() }
                        .disabled(model.busy)
                }
            }
            .listStyle(.plain)
            .navigationTitle(model.stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model.step == .menu {
                        Button("Отмена") { dismiss() }
                    } else {
                        Button("Назад") { model.back() }
                    }
                }
                if model.busy {
                    ToolbarItem(placement: .confirmationAction) {
                        ProgressView()
                    }
                }
            }
        }
        .tint(Color.orbitleAccent)
        .presentationDetents([.medium, .large])
        .onChange(of: model.opened?.id) { _, id in
            guard let id, let opened = model.opened, opened.id == id else { return }
            onOpened(opened)
        }
    }

    private func menuRow(_ title: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var queryField: some View {
        TextField("Имя или номер", text: $model.query)
            .textInputAutocapitalization(.never)
    }

    private var titleField: some View {
        TextField("Название", text: $model.title)
    }

    private var emptyPeople: some View {
        Text(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Контактов пока нет" : "Никого не нашлось")
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
    }

    private func personRow(_ person: Contact, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    PrivateText(person.displayName, placeholder: PrivateModeMask.contactTitle)
                    if let phone = person.phone, !phone.isEmpty {
                        Text(phone)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if model.step == .group, model.selected.contains(person.id) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.orbitleAccent)
                }
            }
        }
    }
}
