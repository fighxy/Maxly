import SwiftUI

@main
struct OrbitleApp: App {
    @State private var container = AppContainer()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView(container: container, router: router)
        }
    }
}
