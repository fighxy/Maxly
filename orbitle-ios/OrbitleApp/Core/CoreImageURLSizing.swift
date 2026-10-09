import Foundation
import MaxlyCore
import OrbitleDomain

/// Размеры картинок считает ядро. Приложение только передаёт сторону в пикселях.
struct CoreImageURLSizing: ImageURLSizing {
    func sizedURL(_ url: String, shape: ImageURLShape, neededPixels: Int) -> String {
        IosImageSize.shared.sizedUrl(url: url, shape: shape.rawValue, neededPixels: Int32(neededPixels))
    }

    func isExpired(_ url: String, nowMillis: Int64) -> Bool {
        IosImageSize.shared.expired(url: url, nowMillis: nowMillis)
    }
}
