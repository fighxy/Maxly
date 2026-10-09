import SwiftUI
import UIKit
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// «Переименовать»: своё имя и фамилия контакта, каждое до 64 символов. Видно только вам.
struct ContactRenameSheet: View {
    @Bindable var viewModel: ContactsViewModel
    let contactId: String
    @Environment(\.dismiss) private var dismiss
    @State private var firstName: String
    @State private var lastName: String
    @State private var isSaving = false

    init(viewModel: ContactsViewModel, contact: Contact) {
        self.viewModel = viewModel
        self.contactId = contact.id
        _firstName = State(initialValue: contact.firstName)
        _lastName = State(initialValue: contact.lastName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Имя", text: $firstName, content: .givenName)
                    field("Фамилия", text: $lastName, content: .familyName)
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(.red)
                    } else if let error = viewModel.errorMessage {
                        Text(error).foregroundStyle(.red)
                    } else if firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? "Без имени и фамилии вернутся имена, которые человек указал сам"
                             : "Без имени будет видно имя, которое человек указал сам")
                    } else {
                        Text("Имя видно только вам")
                    }
                }
            }
            .navigationTitle("Переименовать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        viewModel.dismissError()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        Task {
                            isSaving = true
                            let saved = await viewModel.rename(id: contactId, firstName: firstName, lastName: lastName)
                            isSaving = false
                            if saved { dismiss() }
                        }
                    }
                    .disabled(problem != nil || isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Длиннее 64 — «Готово» неактивно. Пустое имя можно.
    private var problem: String? {
        ContactNameRules.problem(firstName: firstName, lastName: lastName)
    }

    private func field(_ title: String, text: Binding<String>, content: UITextContentType) -> some View {
        HStack {
            TextField(title, text: text)
                .textContentType(content)
            let count = text.wrappedValue.count
            if count > ContactNameRules.limit - 10 {
                Text("\(count)/\(ContactNameRules.limit)")
                    .font(.caption.monospacedDigit())
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
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Отменить", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.orbitleAccent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .orbitleGlassCapsule(interactive: false)
        .padding(.horizontal, OrbitleTheme.pad)
        .padding(.bottom, 8)
        .task(id: removed.id) {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { onTimeout() }
        }
        .accessibilityElement(children: .contain)
    }
}
