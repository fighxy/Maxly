import Foundation

/// Пользователь: контакт или участник чата.
public struct User: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var avatarUrl: URL?

    public init(id: String, name: String, avatarUrl: URL? = nil) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
    }
}
