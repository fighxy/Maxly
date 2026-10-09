import Foundation
import MaxlyDomain

/// Карточки профилей на диске (`Caches/ChatProfiles/<id>.json`): профиль и статус в шапке чата
/// видны сразу, без сети, а сервер их потом обновляет. Стирается при выходе из аккаунта.
public actor ChatProfileCache {
    private let directory: URL
    private var memory: [String: ChatProfile] = [:]
    /// Карточки, пришедшие с сервера в этом запуске, и когда. Из них отвечают без запроса.
    private var recent: [String: (profile: ChatProfile, at: Date)] = [:]

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

    /// Карточка с сервера моложе `maxAge` секунд, как она пришла. `nil` — пора спросить сервер.
    public func fresh(chatId: String, maxAge: TimeInterval, now: Date = Date()) -> ChatProfile? {
        guard let entry = recent[chatId], now.timeIntervalSince(entry.at) < maxAge else { return nil }
        return entry.profile
    }

    public func save(_ profile: ChatProfile, at date: Date = Date()) {
        recent[profile.chatId] = (profile: profile, at: date)
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
        recent = [:]
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
