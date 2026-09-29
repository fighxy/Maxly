import Foundation

/// Маршруты приложения для NavigationStack.
// TODO: architecture.md, «iOS-клиент», пункт 4; «Диплинки».
enum Route: Hashable, Codable {
    case chat(id: String)
}
