import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Строка приватности MAX: название и выбранный вариант, открывает список вариантов.
/// Заблокированная строка не открывается, причина — под секцией.
struct PrivacyRowLink: View {
    let row: PrivacyRow
    @Bindable var model: PrivacySettingsModel

    var body: some View {
        NavigationLink {
            PrivacyChoiceView(row: row, model: model)
        } label: {
            LabeledContent(row.title) {
                if model.settings.isKnown {
                    Text(model.selected(row).title)
                } else {
                    ProgressView()
                }
            }
        }
        .disabled(!model.canChange(row))
    }
}

/// Список вариантов с галочкой, подзаголовок — вопрос настройки («Кто может мне звонить»).
struct PrivacyChoiceView: View {
    let row: PrivacyRow
    @Bindable var model: PrivacySettingsModel
    @State private var confirmOption: PrivacyOption?
    @State private var confirming = false

    var body: some View {
        List {
            Section {
                ForEach(row.options) { option in
                    Button {
                        pick(option)
                    } label: {
                        HStack {
                            Text(option.title)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if model.selected(row) == option {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.orbitleAccent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(!model.canChange(row))
                    .accessibilityAddTraits(model.selected(row) == option ? .isSelected : [])
                }
            } header: {
                Text(row.subtitle)
                    .textCase(nil)
            } footer: {
                if let reason = model.lockReason(row) {
                    Text(reason)
                } else if let error = model.choiceError {
                    Text(error).foregroundStyle(.red)
                } else if let footer = row.footer {
                    Text(footer)
                }
            }
        }
        .navigationTitle(row.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.choiceError = nil }
        .confirmationDialog("Скрыть статус «в сети»?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Скрыть от всех") {
                if let option = confirmOption { Task { await model.choose(option, for: row) } }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вы тоже перестанете видеть, кто в сети.")
        }
    }

    private func pick(_ option: PrivacyOption) {
        guard model.selected(row) != option else { return }
        if row.needsConfirmation(option) {
            confirmOption = option
            confirming = true
        } else {
            Task { await model.choose(option, for: row) }
        }
    }
}

/// Заголовок части «Конфиденциальность» над блоком «Дополнительно».
struct PrivacyPartHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Конфиденциальность")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primary)
                .textCase(nil)
            Text("Дополнительно")
        }
        .padding(.top, 8)
    }
}

/// Свой статус под номером в шапке настроек: «в сети» или «был(а) …», как видит сервер.
/// Нет строки, если «Показывать мой онлайн» выключено или статус ещё неизвестен.
struct OwnPresenceLine: View {
    @Bindable var model: GhostSettingsModel

    var body: some View {
        TimelineView(.everyMinute) { context in
            if let text = model.ownPresenceText(now: context.date) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.isOwnPresenceOnline ? Color.green : Color.secondary)
                        .frame(width: 7, height: 7)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(model.isOwnPresenceOnline ? Color.orbitleAccent : Color.secondary)
                        .contentTransition(.opacity)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Ваш статус: \(text)")
            }
        }
    }
}
