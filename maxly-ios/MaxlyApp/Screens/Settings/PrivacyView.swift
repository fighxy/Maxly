import SwiftUI
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// «Конфиденциальность»: блок «Дополнительно» (режим призрака, отметки о прочтении, свой онлайн),
/// настройки приватности MAX и секция «Информация», имена из адресной книги, чёрный список
/// (docs/privacy.md). Настройки конфига меняются сразу и откатываются при отказе сервера.
/// Безопасный режим, который блокирует четыре строки MAX, — в «Безопасности».
struct PrivacyView: View {
    @Bindable var account: AccountSettingsModel
    @Bindable var model: SecuritySettingsModel
    @Bindable var privacy: PrivacySettingsModel
    @Bindable var ghost: GhostSettingsModel
    /// «Имена из адресной книги» (настройка устройства).
    @Environment(AddressBookNamesSync.self) private var addressBook: AddressBookNamesSync?

    var body: some View {
        List {
            ghostSection
            maxPrivacySection
            informationSection
            addressBookSection

            Section {
                NavigationLink {
                    BlockedUsersView(model: model)
                } label: {
                    SettingsRowLabel("Чёрный список", systemImage: "hand.raised.fill", tint: .red)
                }
            }
        }
        .navigationTitle("Конфиденциальность")
        .navigationBarTitleDisplayMode(.inline)
        .task { privacy.activate() }
        .alert(
            "Не получилось",
            isPresented: Binding(
                get: { account.errorMessage != nil || model.errorMessage != nil || privacy.errorMessage != nil },
                set: { if !$0 { account.errorMessage = nil; model.errorMessage = nil; privacy.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(account.errorMessage ?? model.errorMessage ?? privacy.errorMessage ?? "")
        }
    }

    /// «Дополнительно»: режим призрака, отметки о прочтении, свой онлайн в шапке настроек.
    private var ghostSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { ghost.ghostMode },
                set: { value in Task { await ghost.setGhostMode(value) } }
            )) {
                SettingsRowLabel("Режим призрака", systemImage: "eye.slash.circle.fill", tint: .purple)
            }
            Toggle(isOn: Binding(
                get: { ghost.hideReadReceipts },
                set: { value in Task { await ghost.setHideReadReceipts(value) } }
            )) {
                SettingsRowLabel("Не отправлять отметки о прочтении", systemImage: "text.badge.checkmark", tint: .blue)
            }
            Toggle(isOn: Binding(
                get: { ghost.showsOwnPresence },
                set: { ghost.setShowsOwnPresence($0) }
            )) {
                SettingsRowLabel("Показывать мой онлайн", systemImage: "antenna.radiowaves.left.and.right", tint: .green)
            }
        } header: {
            Text("Дополнительно")
                .textCase(nil)
        } footer: {
            Text("Режим призрака скрывает ваш онлайн и то, что вы печатаете, записываете или отправляете файлы. Отправленные сообщения и реакции видны как обычно. Без отметок о прочтении у собеседника сообщения остаются непрочитанными и после выключения такими и останутся.")
        }
    }

    /// Четыре настройки MAX, в порядке MAX. Пока включён безопасный режим или действует
    /// семейная защита, строки не открываются, причина — под секцией.
    private var maxPrivacySection: some View {
        Section {
            ForEach(PrivacyRow.main) { row in
                PrivacyRowLink(row: row, model: privacy)
            }
        } footer: {
            if let reason = privacy.mainLockReason {
                Text(reason == PrivacySettingsModel.safeModeLock
                    ? "Отключите безопасный режим в «Безопасности», чтобы изменить эту настройку."
                    : reason)
            }
        }
    }

    /// «Информация»: кто видит статус «в сети» и номер.
    private var informationSection: some View {
        Section {
            ForEach(PrivacyRow.information) { row in
                PrivacyRowLink(row: row, model: privacy)
            }
        } header: {
            Text("Информация")
                .textCase(nil)
        }
    }

    /// Имена людей в чатах — как в телефонной книге. Книга не покидает устройство.
    @ViewBuilder
    private var addressBookSection: some View {
        if let addressBook {
            Section {
                Toggle(isOn: Binding(
                    get: { addressBook.isEnabled },
                    set: { value in Task { await addressBook.setEnabled(value) } }
                )) {
                    SettingsRowLabel("Имена из адресной книги", systemImage: "person.crop.rectangle.stack.fill", tint: .orange)
                }
            } footer: {
                Text("Люди в чатах подписаны так, как вы записали их в телефоне. Адресная книга остаётся на этом устройстве и никуда не отправляется. Нужен доступ к контактам.")
            }
        }
    }
}
