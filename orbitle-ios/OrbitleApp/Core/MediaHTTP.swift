import Foundation

/// HTTP-параметры медиа вне протокола Max.
@MainActor
enum MediaHTTP {
    /// User-Agent Android-профиля ядра для CDN (`OKMessages/…`). `nil` — ядро его не дало.
    static var userAgent: String?
}
