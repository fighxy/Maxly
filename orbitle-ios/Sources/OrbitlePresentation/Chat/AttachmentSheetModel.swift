import Foundation
import Observation
import OrbitleDomain

/// Лист вложений: вкладки, выбор фото и видео с номерами по порядку, подпись и поиск
/// контакта. Сам медиатеку не читает: элементы и файлы готовит экран (PhotoKit, импорт).
@MainActor
@Observable
public final class AttachmentSheetModel {
    public enum Tab: String, CaseIterable, Identifiable, Sendable {
        case gallery, file, location, poll, contact

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .gallery: "Галерея"
            case .file: "Файл"
            case .location: "Геопозиция"
            case .poll: "Опрос"
            case .contact: "Контакт"
            }
        }

        public var systemImage: String {
            switch self {
            case .gallery: "photo.on.rectangle"
            case .file: "doc"
            case .location: "location"
            case .poll: "chart.bar.xaxis"
            case .contact: "person.crop.circle"
            }
        }

        /// Вкладки, которых пока нет: экран показывает «Скоро».
        public var isAvailable: Bool {
            switch self {
            case .gallery, .file, .contact: true
            case .location, .poll: false
            }
        }
    }

    /// Больше за раз не выбрать: иначе сообщений выйдет слишком много.
    public static let selectionLimit = 30

    public var tab: Tab = .gallery
    public var caption = ""
    public var contactQuery = ""
    /// Выбранные элементы галереи по порядку выбора (id ассетов).
    public private(set) var selection: [String] = []
    public private(set) var contacts: [Contact] = []
    /// Нажали на элемент сверх лимита: экран коротко об этом говорит.
    public private(set) var limitReached = false

    public init(contacts: [Contact] = []) {
        self.contacts = contacts
    }

    public func setContacts(_ list: [Contact]) {
        contacts = list
    }

    /// Номер выбранного элемента (с 1) или `nil`.
    public func number(of id: String) -> Int? {
        selection.firstIndex(of: id).map { $0 + 1 }
    }

    public func toggle(_ id: String) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
            limitReached = false
            return
        }
        guard selection.count < Self.selectionLimit else {
            limitReached = true
            return
        }
        selection.append(id)
    }

    public func clearSelection() {
        selection = []
        caption = ""
        limitReached = false
    }

    public var hasSelection: Bool { !selection.isEmpty }

    /// Надпись на кнопке отправки.
    public var sendTitle: String {
        selection.count > 1 ? "Отправить (\(selection.count))" : "Отправить"
    }

    /// Контакты по запросу: имя или номер, без учёта регистра, «ё» как «е».
    public var filteredContacts: [Contact] {
        let query = Self.normalize(contactQuery)
        let sorted = contacts.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        guard !query.isEmpty else { return sorted }
        let digits = contactQuery.filter(\.isNumber)
        return sorted.filter { contact in
            if Self.normalize(contact.displayName).contains(query) { return true }
            guard !digits.isEmpty, let phone = contact.phone else { return false }
            return phone.filter(\.isNumber).contains(digits)
        }
    }

    public func contactDraft(_ contact: Contact) -> AttachmentDraft {
        .contact(id: contact.id, name: contact.displayName, phone: contact.phone ?? "")
    }

    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
    }
}
