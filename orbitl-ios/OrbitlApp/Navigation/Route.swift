import Foundation

/// Маршрут открытого чата. На iPhone его показывает `NavigationSplitView`, на iPad — колонка detail.
enum Route: Hashable, Codable {
    case chat(id: String)
}
