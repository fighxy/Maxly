import UIKit
import MaxlyUI

/// Заголовки навигации выбранным шрифтом («Оформление → Шрифт»). UIKit применяет вид к новым
/// панелям: открытые экраны получают шрифт после перехода.
@MainActor
enum NavigationBarFonts {
    static func apply(_ typography: Typography = .shared) {
        let bar = UINavigationBar.appearance()
        guard let title = typography.platformFont(.headline),
              let large = typography.platformFont(.largeTitle, weight: .bold)
        else {
            bar.titleTextAttributes = nil
            bar.largeTitleTextAttributes = nil
            return
        }
        bar.titleTextAttributes = [.font: title as UIFont]
        bar.largeTitleTextAttributes = [.font: large as UIFont]
    }
}
