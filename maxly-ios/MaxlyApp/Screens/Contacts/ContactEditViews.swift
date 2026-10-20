import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Тексты подтверждения «Удалить из контактов»: одни и те же в профиле и во вкладке «Контакты».
enum ContactRemoveTexts {
    static func title(_ name: String) -> String { "Удалить «\(name)» из контактов?" }
    static let message = "Переписка сохранится."
    static let confirm = "Удалить"
    static let menuItem = "Удалить из контактов"
}

/// «Изменить контакт»: своё имя и фамилия контакта, каждое до 64 символов. Видно только вам.
/// Оба поля пустые — вернётся имя, которое указал человек.
struct ContactEditSheet: View {
    /// Сохранить; `nil` — сохранено, иначе текст ошибки.
    typealias Save = (_ firstName: String, _ lastName: String) async -> String?

    let placeholder: (firstName: String, lastName: String)
    /// Номер человека: по нему видно, есть ли он в адресной книге.
    let phone: String?
    let save: Save
    @Environment(\.dismiss) private var dismiss
    @Environment(AddressBookNamesSync.self) private var addressBook: AddressBookNamesSync?
    @State private var firstName: String
    @State private var lastName: String
    @State private var isSaving = false
    @State private var error: String?
    @State private var inAddressBook = false

    init(fields: (firstName: String, lastName: String), placeholder: (firstName: String, lastName: String), phone: String?, save: @escaping Save) {
        self.placeholder = placeholder
        self.phone = phone
        self.save = save
        _firstName = State(initialValue: fields.firstName)
        _lastName = State(initialValue: fields.lastName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field(placeholder.firstName, text: $firstName, content: .givenName)
                    field(placeholder.lastName, text: $lastName, content: .familyName)
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        if let problem {
                            Text(problem).foregroundStyle(.red)
                        } else if let error {
                            Text(error).foregroundStyle(.red)
                        }
                        Text("Имя сохранится в вашем аккаунте MAX. Человек его не увидит. Чтобы вернуть имя, которое указал человек, очистите оба поля.")
                        if inAddressBook {
                            Text("Сейчас показывается имя из адресной книги. Это можно изменить в разделе «Конфиденциальность».")
                        }
                    }
                }
            }
            .navigationTitle("Изменить контакт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        Task {
                            isSaving = true
                            error = await save(firstName, lastName)
                            isSaving = false
                            if error == nil { dismiss() }
                        }
                    }
                    .disabled(problem != nil || isSaving)
                }
            }
            .task { inAddressBook = await Self.hasAddressBookName(phone: phone, enabled: addressBook?.isEnabled == true) }
        }
        .presentationDetents([.medium, .large])
    }

    /// Длиннее 64 — «Готово» неактивно. Пустое имя можно.
    private var problem: String? {
        ContactNameRules.problem(firstName: firstName, lastName: lastName)
    }

    /// Настройка «Имена из адресной книги» включена и номер человека есть в книге телефона.
    private static func hasAddressBookName(phone: String?, enabled: Bool) async -> Bool {
        guard enabled, AppContainer.prefersAddressBookNames, let phone else { return false }
        let key = ContactCustomName.phoneKey(phone)
        guard key.count >= 7, let book = await AddressBookReader.read() else { return false }
        return book.contains { ContactCustomName.phoneKey($0.phone) == key && !$0.firstName.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func field(_ title: String, text: Binding<String>, content: UITextContentType) -> some View {
        HStack {
            TextField(title, text: text)
                .textContentType(content)
                .frame(minHeight: 44)
            let count = text.wrappedValue.count
            if count > ContactNameRules.limit - 10 {
                Text("\(count)/\(ContactNameRules.limit)")
                    .font(.app(.caption).monospacedDigit())
                    .foregroundStyle(count > ContactNameRules.limit ? .red : .secondary)
            }
        }
    }
}

/// Плашка после удаления контакта: «Контакт удалён» и «Отменить». Сама уходит через 5 с.
struct ContactRemovedBanner: View {
    let removed: ContactsViewModel.RemovedContact
    let onUndo: () -> Void
    let onTimeout: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.minus")
                .foregroundStyle(.secondary)
            Text("Контакт удалён")
                .font(.app(.subheadline, .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Отменить", action: onUndo)
                .font(.app(.subheadline, .semibold))
                .foregroundStyle(Color.maxlyAccent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .maxlyGlassCapsule(interactive: false)
        .padding(.horizontal, MaxlyTheme.pad)
        .padding(.bottom, 8)
        .task(id: removed.id) {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { onTimeout() }
        }
        .accessibilityElement(children: .contain)
    }
}
