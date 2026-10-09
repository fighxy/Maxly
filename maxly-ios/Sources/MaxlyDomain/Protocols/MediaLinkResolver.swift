import Foundation

/// Вид вложения, чей прямой адрес выдаёт сервер по запросу.
public enum MediaLinkKind: String, Sendable {
    case video
    case file
}

/// Прямой адрес видео или файла сообщения. У таких вложений сервер присылает только id,
/// ссылку на сам ролик или файл нужно запросить отдельно.
public protocol MediaLinkResolver: Sendable {
    func link(chatId: String, messageId: String, kind: MediaLinkKind, attachmentId: String) async throws(MaxlyError) -> URL
}
