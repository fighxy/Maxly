import SwiftUI
import MaxlyUI
import MaxlyDomain

@main
struct MaxlyApp: App {
    @State private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView(container: container, router: router)
                // Системные кнопки, ссылки и переключатели — в синий цвет акцента.
                .tint(Color.maxlyAccent)
                .task(id: scenePhase) {
                    DiagnosticEvent.event("app.lifecycle", ["phase": String(describing: scenePhase)], snapshot: true)
                    guard scenePhase == .active else { return }
                    var previous = ProcessInfo.processInfo.systemUptime
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(5)) } catch { return }
                        let now = ProcessInfo.processInfo.systemUptime
                        DiagnosticEvent.event("performance.heartbeat", ["main_delay_ms": String(Int(max(0, now - previous - 5) * 1000)),
                            "thermal_state": String(ProcessInfo.processInfo.thermalState.rawValue)], snapshot: true)
                        previous = now
                    }
                }
        }
    }
}
