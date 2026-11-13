import Foundation
import MaxlyDomain

/// Куда ведёт нажатие на карточку контакта в пузыре.
///
/// Контакт с аккаунтом MAX открывает профиль собеседника, как нажатие на автора в группе: оттуда
/// можно написать или позвонить. Без аккаунта (или если это я сам) остаётся номер: позвонить или
/// скопировать. Ни того ни другого — карточка не нажимается.
public enum ContactCardTarget: Equatable, Sendable {
    case profile(DialogDraft)
    /// Номер для показа («+7 999 123-45-67») и ссылка `tel:`.
    case phone(display: String, call: URL?)

    public static func resolve(_ contact: ContactContent, me: String) -> ContactCardTarget? {
        if let dialog = DialogDraft.with(
            peerId: contact.userId, me: me, title: contact.name, avatarURL: contact.avatarURL
        ) {
            return .profile(dialog)
        }
        let digits = contact.phone.filter(\.isASCIIDigit)
        guard !digits.isEmpty else { return nil }
        let normalized = "+" + digits
        return .phone(display: PhoneNumber.display(normalized), call: URL(string: "tel:" + normalized))
    }
}
