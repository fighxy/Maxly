import Foundation
import OrbitleDomain

/// Ссылки на видео (`VIDEO_PLAY`) и файлы (`FILE_DOWNLOAD`) через ядро.
///
/// Ссылка живёт недолго, поэтому кэш держит её `lifetime`, а не до выхода из чата.
public actor CoreMediaLinkResolver: MediaLinkResolver {
    private let core: any MaxCore
    private let lifetime: TimeInterval
    private var cache: [String: (url: URL, until: Date)] = [:]

    public init(core: any MaxCore, lifetime: TimeInterval = 10 * 60) {
        self.core = core
        self.lifetime = lifetime
    }

    public func link(chatId: String, messageId: String, kind: MediaLinkKind, attachmentId: String) async throws(OrbitleError) -> URL {
        let key = "\(kind.rawValue):\(chatId):\(messageId):\(attachmentId)"
        if let hit = cache[key], hit.until > Date() { return hit.url }
        let text: String
        do {
            text = try await core.mediaLink(chatId: chatId, messageId: messageId, kind: kind.rawValue, attachmentId: attachmentId)
        } catch {
            Log.warning(.media, "Ссылка на \(kind.rawValue) не получена: \(error)")
            throw CoreMapping.apiError(error).orbitleError
        }
        guard let url = URL(string: text), url.scheme != nil else {
            Log.warning(.media, "Сервер прислал неверную ссылку на \(kind.rawValue)")
            throw .rejected("Сервер не отдал ссылку на вложение")
        }
        cache[key] = (url, Date().addingTimeInterval(lifetime))
        return url
    }

    public func reset() {
        cache = [:]
    }
}
