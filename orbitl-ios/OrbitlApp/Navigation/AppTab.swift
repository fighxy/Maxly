import Foundation

/// Вкладки нижней панели.
enum AppTab: String, CaseIterable, Hashable {
    case contacts
    case calls
    case chats
    case settings

    /// Порядок вкладок слева направо. Меняется только здесь.
    static let order: [AppTab] = [.contacts, .calls, .chats, .settings]

    var title: String {
        switch self {
        case .contacts: "Контакты"
        case .calls: "Звонки"
        case .chats: "Чаты"
        case .settings: "Настройки"
        }
    }

    var systemImage: String {
        switch self {
        case .contacts: "person.crop.circle.fill"
        case .calls: "phone.fill"
        case .chats: "bubble.left.and.bubble.right.fill"
        case .settings: "gearshape.fill"
        }
    }
}
