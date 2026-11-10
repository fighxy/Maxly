import Foundation
import MaxlyDomain

/// Адреса картинок строки списка чатов. Одни и те же у строки и у предзагрузки: кэш картинок
/// ищет по адресу.
public enum ChatListImages {
    /// Сторона миниатюры последнего сообщения, точки.
    public static let thumbnailSide: Double = 18

    /// Аватар строки: квадрат сервера (`sqr_N`) под сторону `size` точек.
    public static func avatarURL(_ url: URL, size: Double, scale: Double, sizing: any ImageURLSizing) -> URL {
        ImageURLRequests.url(
            url, shape: .square, pointSize: CGFloat(size), scale: CGFloat(scale), fullScreen: false, sizing: sizing
        ) ?? url
    }

    /// Миниатюра последнего сообщения. Фото берётся уменьшенным (`w_N`): без размера сервер
    /// отдаёт оригинал, а в строке он 18 точек. Обложка видео и стикер — как есть.
    public static func thumbnailURL(_ url: URL, media: MessageMediaKind?, scale: Double, sizing: any ImageURLSizing) -> URL {
        guard media == .photo else { return url }
        return ImageURLRequests.url(
            url, shape: .width, pointSize: CGFloat(thumbnailSide), scale: CGFloat(scale), fullScreen: false, sizing: sizing
        ) ?? url
    }
}
