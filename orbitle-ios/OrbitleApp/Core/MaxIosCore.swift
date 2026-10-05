import Foundation
import OrbitleData
import OrbitleDomain
import MaxIos

/// Живой мост к `MaxIosClient`. Колбэки ядра приходят не с главного потока.
final class MaxIosCore: MaxCore, @unchecked Sendable {
    let client = MaxIosClient(namespace: "default")

    /// Необработанное исключение ядра Kotlin попадает в аварийный журнал до завершения процесса.
    static func installCrashHandler() {
        IosDiagnostics.shared.installCrashHandler { text in
            CrashReporter.record(text)
        }
        // Колбэки ядра несут только вид ошибки; причину (исключение и его стек) ядро пишет сюда.
        IosDiagnostics.shared.installErrorLogger { text in
            Log.warning(.core, "Причина: \(text)")
        }
    }

    func phaseName() async -> CorePhase {
        CorePhase(raw: client.phaseName())
    }

    func currentUserId() async -> String {
        client.currentUserId()
    }

    func hasStoredToken() async -> Bool {
        client.hasStoredToken()
    }

    func start() async throws -> CorePhase {
        try await call("start") { done in
            self.client.start { phase, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(CorePhase(raw: phase ?? "failed")))
                }
            }
        }
    }

    func requestCode(phone: String, resend: Bool) async throws -> CoreCode {
        try await call("requestCode") { done in
            self.client.requestCode(phone: phone, resend: resend) { code, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else if let code {
                    let length = code.codeLength > 0 ? Int(code.codeLength) : nil
                    done(.success(CoreCode(token: code.token, codeLength: length)))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func verifyCode(token: String, code: String) async throws -> CoreAuthStep {
        try await call("verifyCode") { done in
            self.client.verifyCode(token: token, code: code) { step, kind, key in
                done(Self.step(step, kind: kind, key: key))
            }
        }
    }

    func checkPassword(trackId: String, password: String) async throws -> CoreAuthStep {
        try await call("checkPassword") { done in
            self.client.checkPassword(trackId: trackId, password: password) { step, kind, key in
                done(Self.step(step, kind: kind, key: key))
            }
        }
    }

    func register(token: String, firstName: String, lastName: String) async throws -> CoreAuthStep {
        try await call("register") { done in
            self.client.register(registerToken: token, firstName: firstName, lastName: lastName) { step, kind, key in
                done(Self.step(step, kind: kind, key: key))
            }
        }
    }

    func logout() async throws {
        let _: Void = try await call("logout") { done in
            self.client.logout { kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(()))
                }
            }
        }
    }

    func loadChats() async throws -> [CoreChat] {
        try await call("loadChats") { done in
            self.client.loadChats { chats, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(chats.map(Self.chat)))
                }
            }
        }
    }

    func loadChat(id: String) async throws -> CoreChat {
        try await call("loadChat") { done in
            self.client.loadChat(chatId: id) { chat, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else if let chat {
                    done(.success(Self.chat(chat)))
                } else {
                    done(.failure(CoreFailure(kind: "NOT_FOUND", key: nil)))
                }
            }
        }
    }

    func loadHistory(chatId: String, beforeMs: Int64, limit: Int) async throws -> [CoreMessage] {
        try await call("loadHistory") { done in
            self.client.loadHistory(chatId: chatId, beforeMs: beforeMs, limit: Int32(limit)) { messages, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(messages.map(Self.message)))
                }
            }
        }
    }

    func searchPublic(query: String, from: Int, count: Int) async throws -> [CoreSearchChat] {
        try await call("searchPublic") { done in
            self.client.searchPublic(query: query, from: Int32(from), count: Int32(count)) { chats, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(chats.map { chat in
                        CoreSearchChat(
                            id: chat.id, type: chat.type, title: chat.title, subtitle: chat.subtitle,
                            avatarURL: chat.avatarUrl, participantsCount: Int(chat.participantsCount)
                        )
                    }))
                }
            }
        }
    }

    func searchMessages(query: String, count: Int) async throws -> [CoreFoundMessage] {
        try await call("searchMessages") { done in
            self.client.searchMessages(query: query, count: Int32(count)) { messages, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(messages.map { message in
                        CoreFoundMessage(
                            chatId: message.chatId, messageId: message.messageId, senderId: message.senderId,
                            text: message.text, timeMs: message.timeMs
                        )
                    }))
                }
            }
        }
    }

    func loadSharedMedia(chatId: String, anchorId: String, attachTypes: [String], forward: Int, backward: Int) async throws -> [CoreMessage] {
        try await call("loadSharedMedia") { done in
            self.client.loadSharedMedia(
                chatId: chatId, anchorId: anchorId, attachTypes: attachTypes,
                forward: Int32(forward), backward: Int32(backward)
            ) { messages, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(messages.map(Self.message)))
                }
            }
        }
    }

    func sendText(chatId: String, text: String) async throws -> CoreMessage {
        try await call("sendText") { done in
            self.client.sendText(chatId: chatId, text: text) { message, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else if let message {
                    done(.success(Self.message(message)))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func sendText(chatId: String, text: String, replyTo: String) async throws -> CoreMessage {
        try await call("sendReply") { done in
            self.client.sendText(chatId: chatId, text: text, replyTo: replyTo) { message, kind, key in
                done(Self.single(message, kind: kind, key: key))
            }
        }
    }

    func loadComments(chatId: String, postId: String, beforeMs: Int64, limit: Int) async throws -> [CoreMessage] {
        try await call("loadComments") { done in
            self.client.loadComments(chatId: chatId, postId: postId, beforeMs: beforeMs, limit: Int32(limit)) { list, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(list.map(Self.message)))
                }
            }
        }
    }

    func sendComment(chatId: String, postId: String, text: String) async throws -> CoreMessage {
        try await call("sendComment") { done in
            self.client.sendComment(chatId: chatId, postId: postId, text: text, replyTo: "") { message, kind, key in
                done(Self.single(message, kind: kind, key: key))
            }
        }
    }

    func editMessage(chatId: String, messageId: String, text: String) async throws -> CoreMessage {
        try await call("editMessage") { done in
            self.client.editMessage(chatId: chatId, messageId: messageId, text: text) { message, kind, key in
                done(Self.single(message, kind: kind, key: key))
            }
        }
    }

    func deleteMessages(chatId: String, messageIds: [String], forEveryone: Bool) async throws {
        let _: Void = try await call("deleteMessages") { done in
            self.client.deleteMessages(chatId: chatId, messageIds: messageIds, forEveryone: forEveryone) { kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(()))
                }
            }
        }
    }

    func forwardMessage(toChatId: String, fromChatId: String, messageId: String) async throws -> CoreMessage {
        try await call("forwardMessage") { done in
            self.client.forwardMessage(toChatId: toChatId, fromChatId: fromChatId, messageId: messageId) { message, kind, key in
                done(Self.single(message, kind: kind, key: key))
            }
        }
    }

    func loadCommentCounts(chatId: String, postIds: [String]) async throws -> [String: Int] {
        try await call("loadCommentCounts") { done in
            self.client.loadCommentCounts(chatId: chatId, postIds: postIds) { list, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    var counts: [String: Int] = [:]
                    for item in list { counts[item.postId] = Int(item.count) }
                    done(.success(counts))
                }
            }
        }
    }

    private static func single(_ message: IosMessage?, kind: String?, key: String?) -> Result<CoreMessage, Error> {
        if let kind { return .failure(CoreFailure(kind: kind, key: key)) }
        guard let message else { return .failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)) }
        return .success(Self.message(message))
    }

    func setChatMuted(chatId: String, muted: Bool) async throws {
        let _: Void = try await call("setChatMuted") { done in
            self.client.setChatMuted(chatId: chatId, muted: muted) { kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(()))
                }
            }
        }
    }

    func mediaUserAgent() -> String? {
        let agent = client.mediaUserAgent()
        return agent.isEmpty ? nil : agent
    }

    func markRead(chatId: String, messageId: String) async throws {
        let _: Void = try await call("markRead") { done in
            self.client.markRead(chatId: chatId, messageId: messageId) { kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(()))
                }
            }
        }
    }

    func markUnread(chatId: String, mark: Int64) async throws -> Int {
        try await call("markUnread") { done in
            self.client.markUnread(chatId: chatId, mark: mark) { unread, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(Int(unread.int32Value)))
                }
            }
        }
    }

    func loadContacts() async throws -> [CoreContact] {
        try await call("loadContacts") { done in
            self.client.loadContacts { contacts, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(contacts.map(Self.contact)))
                }
            }
        }
    }

    func findByPhone(phone: String) async throws -> CoreContact {
        try await call("findByPhone") { done in
            self.client.findByPhone(phone: phone) { contact, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else if let contact {
                    done(.success(Self.contact(contact)))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func addContact(userId: String, firstName: String) async throws -> CoreContact {
        try await call("addContact") { done in
            self.client.addContact(userId: userId, firstName: firstName) { contact, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else if let contact {
                    done(.success(Self.contact(contact)))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func createGroup(title: String, memberIds: [String]) async throws -> CoreChat? {
        try await call("createGroup") { done in
            self.client.createGroup(title: title, userIds: memberIds) { chat, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(chat.map(Self.chat)))
                }
            }
        }
    }

    func createChannel(title: String) async throws -> CoreChat? {
        try await call("createChannel") { done in
            self.client.createChannel(title: title) { chat, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(chat.map(Self.chat)))
                }
            }
        }
    }

    func deleteChat(chatId: String, lastEventTimeMs: Int64, forEveryone: Bool) async throws {
        let _: Void = try await call("deleteChat") { done in
            self.client.deleteChat(chatId: chatId, lastEventTimeMs: lastEventTimeMs, forAll: forEveryone) { kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(()))
                }
            }
        }
    }

    func clearHistory(chatId: String, lastEventTimeMs: Int64, forEveryone: Bool) async throws {
        let _: Void = try await call("clearHistory") { done in
            self.client.clearHistory(chatId: chatId, lastEventTimeMs: lastEventTimeMs, forAll: forEveryone) { kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(()))
                }
            }
        }
    }

    func joinByLink(_ link: String) async throws -> CoreChat {
        try await call("joinByLink") { done in
            self.client.joinByLink(link: link) { chat, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else if let chat {
                    done(.success(Self.chat(chat)))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func loadCallHistory() async throws -> [CoreCall] {
        try await call("loadCallHistory") { done in
            self.client.loadCallHistory { calls, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(calls.map(Self.callRecord)))
                }
            }
        }
    }

    func loadProfile(chatId: String) async throws -> CoreProfile {
        try await call("loadProfile") { done in
            self.client.loadProfile(chatId: chatId) { profile, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else if let profile {
                    done(.success(Self.profile(profile)))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func mediaLink(chatId: String, messageId: String, kind: String, attachmentId: String) async throws -> String {
        try await call("mediaLink") { done in
            self.client.mediaLink(chatId: chatId, messageId: messageId, kind: kind, attachmentId: attachmentId) { url, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else if let url, !url.isEmpty {
                    done(.success(url))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func setPinnedChats(_ chatIds: [String]) async throws -> [String] {
        try await call("setPinnedChats") { done in
            self.client.setPinnedChats(chatIds: chatIds) { ids, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(ids))
                }
            }
        }
    }

    func pinnedChats() -> AsyncStream<[String]> {
        AsyncStream { continuation in
            let watch = WatchBox(client.watchPinnedChats { ids in
                continuation.yield(ids)
            })
            continuation.onTermination = { _ in watch.cancel() }
        }
    }

    func phases() -> AsyncStream<CorePhase> {
        AsyncStream { continuation in
            continuation.yield(CorePhase(raw: client.phaseName()))
            let watch = WatchBox(client.watchState { name in
                continuation.yield(CorePhase(raw: name))
            })
            continuation.onTermination = { _ in watch.cancel() }
        }
    }

    func events() -> AsyncStream<CoreEvent> {
        AsyncStream { continuation in
            let watch = WatchBox(client.watchEvents { event in
                if let mapped = Self.event(event) {
                    continuation.yield(mapped)
                }
            })
            continuation.onTermination = { _ in watch.cancel() }
        }
    }

    /// Чтения, которые ждут паузы после `too.many.requests` (`ServerRateLimit`). Отправка,
    /// отметки, вход и действия пользователя с немедленным ответом сюда не входят.
    ///
    /// Комментарии тоже не входят: их открыл пользователь, и фоновый отказ (опрос, общие медиа)
    /// не должен сразу показывать ему ошибку. Ядро пускает их раньше фоновых чтений, а отказ
    /// самого сервера окно комментариев повторяет один раз после паузы. Отказ им всё равно
    /// продлевает паузу для фоновых чтений.
    private static let pacedCalls: Set<String> = [
        "loadHistory", "loadCommentCounts", "loadSharedMedia", "loadProfile",
        "loadChat", "loadChats", "loadReactions", "loadCallHistory", "loadAnimojis",
    ]
    /// Чтения, отказ которым включает паузу, хотя сами они её не ждут.
    private static let limitAwareCalls: Set<String> = pacedCalls.union(["loadComments"])

    /// Вызов ядра с колбэком. Неудача пишется в журнал видом ошибки и ключом сервера.
    /// Во время паузы сервера чтения из `pacedCalls` сразу получают тот же отказ.
    func call<T: Sendable>(_ name: String, _ start: @escaping (@escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        let paced = Self.pacedCalls.contains(name)
        let limitAware = Self.limitAwareCalls.contains(name)
        if paced, let left = await ServerRateLimit.shared.remaining() {
            Log.debug(.core, "\(name): пауза после too.many.requests, ещё \(Int(left.rounded(.up))) с")
            throw CoreFailure(kind: "SERVER", key: ServerRateLimit.key)
        }
        do {
            let value: T = try await withCheckedThrowingContinuation { continuation in
                let gate = ResumeGate()
                start { result in
                    gate.run {
                        if case .failure(let error) = result {
                            if let failure = error as? CoreFailure {
                                let level: Log.Level = failure.kind == "CANCELLED" ? .debug : .warning
                                Log.write(level, .core, "\(name): \(failure.kind)\(failure.key.map { " (\($0))" } ?? "")")
                            } else {
                                Log.warning(.core, "\(name): \(error)")
                            }
                        }
                        continuation.resume(with: result)
                    }
                }
            }
            if limitAware { await ServerRateLimit.shared.noteSuccess() }
            return value
        } catch let failure as CoreFailure where ServerRateLimit.isLimit(failure.key) {
            if limitAware { await ServerRateLimit.shared.noteLimited() }
            throw failure
        }
    }

    private static func step(_ step: IosAuthStep?, kind: String?, key: String?) -> Result<CoreAuthStep, Error> {
        if let kind { return .failure(CoreFailure(kind: kind, key: key)) }
        guard let step else { return .failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)) }
        switch step.kind {
        case "password":
            return .success(.password(trackId: step.trackId, hint: step.hint.isEmpty ? nil : step.hint))
        case "register":
            return .success(.register(token: step.registerToken))
        default:
            return .success(.loggedIn(userId: step.userId))
        }
    }

    private static func chat(_ chat: IosChat) -> CoreChat {
        CoreChat(
            id: chat.id,
            title: chat.title,
            type: chat.type,
            lastMessageId: chat.lastMessageId,
            lastText: chat.lastText,
            updatedAtMs: chat.updatedAtMs,
            unread: Int(chat.unread),
            avatarURL: chat.avatarUrl,
            lastAuthorId: chat.lastAuthorId,
            lastMedia: chat.lastMedia,
            lastThumbURL: chat.lastThumbUrl,
            comments: Int(chat.comments),
            canWrite: Int(chat.canWrite),
            muted: Int(chat.muted),
            lastAuthorName: chat.lastAuthorName,
            lastFromMe: Int(chat.lastFromMe),
            lastForwarded: chat.lastForwarded == 1,
            peerReadMs: chat.peerReadMs
        )
    }

    static func contact(_ contact: IosContact) -> CoreContact {
        CoreContact(
            id: contact.id,
            firstName: contact.firstName,
            lastName: contact.lastName,
            phone: contact.phone,
            avatarURL: contact.avatarUrl,
            lastSeenMs: contact.lastSeenMs,
            online: contact.online,
            accountStatus: Int(contact.accountStatus),
            isBot: contact.isBot,
            isOfficial: contact.isOfficial,
            isServiceAccount: contact.isServiceAccount
        )
    }

    private static func profile(_ profile: IosProfile) -> CoreProfile {
        CoreProfile(
            kind: profile.kind,
            chatId: profile.chatId,
            peerId: profile.peerId,
            title: profile.title,
            avatarURL: profile.avatarUrl,
            description: profile.description_,
            link: profile.link,
            phone: profile.phone,
            participants: Int(profile.participants),
            lastSeenMs: profile.lastSeenMs,
            online: profile.online,
            official: profile.official,
            isPublic: profile.isPublic,
            commands: profile.commands.map { CoreProfile.Command(name: $0.name, description: $0.description_) }
        )
    }

    private static func callRecord(_ call: IosCall) -> CoreCall {
        CoreCall(
            id: call.id,
            chatId: call.chatId,
            peerId: call.peerId,
            title: call.title,
            avatarURL: call.avatarUrl,
            isGroup: call.isGroup,
            outgoing: call.outgoing,
            missed: call.missed,
            video: call.video,
            hangupType: call.hangupType,
            duration: call.duration,
            timeMs: call.timeMs
        )
    }

    static func message(_ message: IosMessage) -> CoreMessage {
        CoreMessage(
            id: message.id,
            chatId: message.chatId,
            authorId: message.authorId,
            text: message.text,
            timeMs: message.timeMs,
            contentJSON: message.contentJson,
            authorName: message.authorName,
            authorAvatarURL: message.authorAvatarUrl,
            reactionsJSON: message.reactionsJson
        )
    }

    private static func event(_ event: IosEvent) -> CoreEvent? {
        guard let kind = CoreEvent.Kind(rawValue: event.kind) else { return nil }
        return CoreEvent(
            kind: kind,
            chatId: event.chatId,
            messageId: event.messageId,
            authorId: event.authorId,
            text: event.text,
            title: event.title,
            chatType: event.chatType,
            timeMs: event.timeMs,
            unread: Int(event.unread),
            contentJSON: event.contentJson,
            authorName: event.authorName,
            authorAvatarURL: event.authorAvatarUrl,
            reactionsJSON: event.reactionsJson
        )
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func run(_ body: () -> Void) {
        lock.lock()
        if fired {
            lock.unlock()
            return
        }
        fired = true
        lock.unlock()
        body()
    }
}

/// `IosWatch` из ядра не помечен Sendable. Отмена в ядре потокобезопасна,
/// поэтому подписку можно отменить из `onTermination` с любого потока.
final class WatchBox: @unchecked Sendable {
    private let watch: IosWatch
    init(_ watch: IosWatch) { self.watch = watch }
    func cancel() { watch.cancel() }
}
