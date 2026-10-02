import Foundation
import OrbitleDomain

/// Карточки профилей на диске (`Caches/ChatProfiles/<id>.json`): профиль и статус в шапке чата
/// видны сразу, без сети, а сервер их потом обновляет. Стирается при выходе из аккаунта.
public actor ChatProfileCache {
    private let directory: URL
    private var memory: [String: ChatProfile] = [:]

    public init(directory: URL) {
        self.directory = directory
    }

    public static func standard() -> ChatProfileCache {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return ChatProfileCache(directory: caches.appendingPathComponent("ChatProfiles", isDirectory: true))
    }

    public func profile(chatId: String) -> ChatProfile? {
        if let known = memory[chatId] { return known }
        guard let data = try? Data(contentsOf: file(chatId)),
              let stored = try? JSONDecoder().decode(ChatProfile.self, from: data) else { return nil }
        let profile = Self.restored(stored)
        memory[chatId] = profile
        return profile
    }

    public func save(_ profile: ChatProfile) {
        memory[profile.chatId] = Self.restored(profile)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(profile).write(to: file(profile.chatId), options: .atomic)
        } catch {
            Log.warning(.chats, "Карточка чата \(profile.chatId) не сохранилась: \(error)")
        }
    }

    public func removeAll() {
        memory = [:]
        try? FileManager.default.removeItem(at: directory)
    }

    /// Сохранённое «в сети» давно устарело: из кэша это «был(а) недавно», пока сервер не скажет.
    static func restored(_ profile: ChatProfile) -> ChatProfile {
        var profile = profile
        if profile.presence == .online { profile.presence = .recently }
        return profile
    }

    private func file(_ chatId: String) -> URL {
        let safe = chatId.map { $0.isLetter || $0.isNumber || $0 == "-" ? String($0) : "_" }.joined()
        return directory.appendingPathComponent(safe + ".json")
    }
}
