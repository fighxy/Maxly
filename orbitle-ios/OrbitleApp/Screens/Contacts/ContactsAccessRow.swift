import SwiftUI
import Contacts
import ContactsUI
import UIKit
import OrbitleDomain

/// Доступ к адресной книге телефона.
///
/// При первом открытии вкладки система спрашивает разрешение; на iOS 18 в том же окне можно
/// дать доступ только к выбранным контактам. Строка над списком объясняет текущий выбор и
/// ведёт в настройки. Адресная книга не уходит на сервер: схема синхронизации контактов Max
/// ещё не известна, поэтому разрешение пока только готовит устройство к ней.
struct ContactsAccessRow: View {
    let status: CNAuthorizationStatus
    let onPickMore: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch Access(status) {
        case .undetermined, .full:
            EmptyView()
        case .limited:
            row(
                systemImage: "person.crop.circle.badge.checkmark",
                title: "Доступ к части контактов",
                detail: "Orbitle видит только выбранные вами контакты телефона.",
                action: "Выбрать ещё",
                perform: onPickMore
            )
        case .denied:
            row(
                systemImage: "person.crop.circle.badge.xmark",
                title: "Нет доступа к контактам",
                detail: "Разрешите доступ в настройках, чтобы найти знакомых в Max.",
                action: "Открыть настройки",
                perform: openSettings
            )
        }
    }

    private func row(systemImage: String, title: String, detail: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
                Button(action, action: perform)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

extension View {
    /// Спрашивает доступ к контактам при первом показе экрана и следит за ним: `status`
    /// обновляется после ответа, после возврата из настроек и после выбора контактов.
    func contactsAccess(status: Binding<CNAuthorizationStatus>, isPickingMore: Binding<Bool>) -> some View {
        modifier(ContactsAccessRequest(status: status, isPicking: isPickingMore))
    }
}

private struct ContactsAccessRequest: ViewModifier {
    @Binding var status: CNAuthorizationStatus
    @Binding var isPicking: Bool
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { await requestIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                // Вернулись из настроек: выбор мог измениться.
                if phase == .active { refresh() }
            }
            .modifier(LimitedPicker(isPresented: $isPicking, onDone: refresh))
    }

    private func requestIfNeeded() async {
        refresh()
        guard status == .notDetermined else { return }
        Log.info(.contacts, "Запрос доступа к контактам телефона")
        do {
            _ = try await CNContactStore().requestAccess(for: .contacts)
        } catch {
            Log.warning(.contacts, "Запрос доступа к контактам: \(error)")
        }
        refresh()
    }

    private func refresh() {
        let next = CNContactStore.authorizationStatus(for: .contacts)
        if next != status {
            Log.info(.contacts, "Доступ к контактам: \(Access(next))")
        }
        status = next
    }
}

/// Вид доступа без `@unknown default` в каждом месте.
private enum Access: CustomStringConvertible {
    case undetermined, full, limited, denied

    init(_ status: CNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .undetermined
        case .authorized: self = .full
        case .denied, .restricted: self = .denied
        default:
            // `.limited` появился в iOS 18.
            self = .limited
        }
    }

    var description: String {
        switch self {
        case .undetermined: "не спрашивали"
        case .full: "полный"
        case .limited: "частичный"
        case .denied: "запрещён"
        }
    }
}

/// Системный выбор дополнительных контактов при частичном доступе (iOS 18).
private struct LimitedPicker: ViewModifier {
    @Binding var isPresented: Bool
    let onDone: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.contactAccessPicker(isPresented: $isPresented) { _ in onDone() }
        } else {
            content
        }
    }
}
