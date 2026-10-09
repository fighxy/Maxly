import Foundation
import SwiftData

/// Пользователь (контакт или участник чата) в локальной базе.
@Model
final class SDUser {
    @Attribute(.unique) var id: String
    var name: String
    var avatarUrl: String?

    init(id: String, name: String, avatarUrl: String? = nil) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
    }
}
