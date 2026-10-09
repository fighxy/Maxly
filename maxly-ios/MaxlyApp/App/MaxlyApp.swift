import SwiftUI
import MaxlyUI

@main
struct MaxlyApp: App {
    @State private var container = AppContainer()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView(container: container, router: router)
                // Системные кнопки, ссылки и переключатели — в синий цвет акцента.
                .tint(Color.maxlyAccent)
        }
    }
}
