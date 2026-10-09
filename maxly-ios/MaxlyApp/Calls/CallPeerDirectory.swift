import Foundation
import MaxlyData
import MaxlyPresentation

/// Имена и аватары для звонка по id пользователя Max: из контактов аккаунта. Список
/// перечитывается не чаще раза в минуту, даже если имя так и не нашлось.
actor CallPeerDirectory {
    private let core: any MaxCore
    private var people: [String: CoreContact] = [:]
    private var loadedAt: Date?

    init(core: any MaxCore) {
        self.core = core
    }

    func peer(_ userId: String) async -> CallCenter.Peer? {
        if people[userId] == nil, loadedAt.map({ Date().timeIntervalSince($0) > 60 }) ?? true {
            loadedAt = Date()
            if let contacts = try? await core.loadContacts() {
                people = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            }
        }
        guard let contact = people[userId] else { return nil }
        let name = [contact.firstName, contact.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        guard !name.isEmpty else { return nil }
        return CallCenter.Peer(id: userId, name: name, avatarURL: contact.avatarURL.isEmpty ? nil : URL(string: contact.avatarURL))
    }
}
