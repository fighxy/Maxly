import UIKit

/// Повороты экрана: всё приложение стоит в портрете, а просмотр
/// фото и видео поворачивается вслед за телефоном. Info.plist разрешает и альбомную
/// ориентацию, а какие из них доступны сейчас, решает `mask`.
@MainActor
enum OrientationLock {
    private(set) static var mask: UIInterfaceOrientationMask = .portrait

    /// Просмотр открылся: экран поворачивается вслед за телефоном.
    static func allowRotation() {
        guard mask != .allButUpsideDown else { return }
        mask = .allButUpsideDown
        refresh()
    }

    /// Просмотр закрылся: обратно в портрет, даже если телефон лежит боком.
    static func lockPortrait() {
        guard mask != .portrait else { return }
        mask = .portrait
        refresh()
        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
    }

    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    private static func refresh() {
        guard let scene else { return }
        for window in scene.windows {
            var controller = window.rootViewController
            while let presented = controller?.presentedViewController {
                controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = presented
            }
            controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

/// Делегат приложения: только ориентации — остальное живёт в SwiftUI.
final class MaxlyAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        // На iPad приложение поворачивается целиком, как и раньше.
        MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad ? .all : OrientationLock.mask }
    }
}
