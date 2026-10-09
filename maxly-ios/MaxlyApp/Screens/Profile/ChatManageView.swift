import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation

/// Управление группой или каналом.
struct ChatManageView: View {
    @Bindable var model: ChatManageModel
    let contacts: [ChatAdminPerson]
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Карточка") {
                    TextField("Название", text: $model.title)
                    TextField("Описание", text: $model.about, axis: .vertical)
                    Button("Сохранить") { Task { await model.save() } }
                }
                Section("Ссылка-приглашение") {
                    if let link = model.link {
                        Text(link).textSelection(.enabled)
                        if let image = QRCode.image(for: Self.address(link)) {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .frame(width: 160, height: 160)
                        }
                    } else {
                        Text("Сервер не прислал ссылку. Её можно перевыпустить.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Перевыпустить ссылку") { Task { await model.revokeLink() } }
                }
                if model.isChannel, let comments = model.commentsEnabled {
                    Section("Канал") {
                        Toggle("Комментарии", isOn: Binding(get: { comments }, set: { value in Task { await model.setComments(value) } }))
                    }
                }
                Section("Права") {
                    toggle("Только владелец меняет название и фото", model.onlyOwnerRenames) { await model.setOption(.onlyOwnerRenames, $0) }
                    toggle("Все могут закреплять", model.allCanPin) { await model.setOption(.allCanPin, $0) }
                    toggle("Участников добавляет только админ", model.onlyAdminAdds) { await model.setOption(.onlyAdminAdds, $0) }
                    toggle("Звонить может только админ", model.onlyAdminCalls) { await model.setOption(.onlyAdminCalls, $0) }
                    toggle("Участники видят ссылку", model.membersSeeLink) { await model.setOption(.membersSeeLink, $0) }
                }
                Section(model.isChannel ? "Подписчики" : "Участники") {
                    Button("Добавить") { picking = true }
                    ForEach(model.members) { person in
                        VStack(alignment: .leading) {
                            Text(person.name)
                            Text(role(person)).font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            if person.role != .owner {
                                Button("Удалить", role: .destructive) { Task { await model.remove(person.id) } }
                                Button(person.role == .admin ? "Снять" : "Админ") { Task { await model.setAdmin(person.id, admin: person.role != .admin) } }
                            }
                        }
                    }
                }
                if !model.requests.isEmpty {
                    Section("Заявки") {
                        ForEach(model.requests) { person in
                            HStack {
                                Text(person.name)
                                Spacer()
                                Button("Принять") { Task { await model.decide(person.id, accept: true) } }
                                Button("Отклонить") { Task { await model.decide(person.id, accept: false) } }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Управление")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .task { await model.load() }
            .alert("Управление", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                Button("OK", role: .cancel) { model.message = nil }
            } message: {
                Text(model.message ?? "")
            }
            .sheet(isPresented: $picking) { contactPicker }
        }
    }

    private var contactPicker: some View {
        let taken = Set(model.members.map(\.id))
        let choices = contacts.filter { !taken.contains($0.id) }
        return NavigationStack {
            List(choices) { person in
                Button(person.name) {
                    picking = false
                    Task { await model.add(person.id) }
                }
            }
            .navigationTitle("Добавить")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { picking = false } } }
            .overlay { if choices.isEmpty { ContentUnavailableView("Некого добавить", systemImage: "person.crop.circle.badge.plus") } }
        }
    }

    private func toggle(_ title: String, _ value: Bool, _ change: @escaping (Bool) async -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { value }, set: { newValue in Task { await change(newValue) } }))
    }

    private static func address(_ link: String) -> String {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        return "https://max.ru/" + trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func role(_ person: ChatAdminPerson) -> String {
        switch person.role {
        case .owner: "владелец"
        case .admin: "админ"
        case .member: ""
        }
    }
}
