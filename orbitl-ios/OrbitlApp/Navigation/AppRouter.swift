import SwiftUI
import Observation

/// Роутер: держит путь навигации и разбирает диплинки в маршруты.
// TODO: architecture.md, «iOS-клиент», пункт 4; «Восстановление состояния».
@MainActor
@Observable
final class AppRouter {
    var path = NavigationPath()
}
