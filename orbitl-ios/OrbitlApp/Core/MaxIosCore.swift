import Foundation
import OrbitlData
import MaxIos

/// Живой мост к `MaxIosClient`. Колбэки ядра приходят не с главного потока.
final class MaxIosCore: MaxCore, @unchecked Sendable {
    private let client = MaxIosClient(namespace: "default")

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
        try await call { done in
            client.start { phase, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(CorePhase(raw: phase ?? "failed")))
                }
            }
        }
    }

    func requestCode(phone: String, resend: Bool) async throws -> CoreCode {
        try await call { done in
            client.requestCode(phone: phone, resend: resend) { code, kind, key in
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
        try await call { done in
            client.verifyCode(token: token, code: code) { step, kind, key in
                done(Self.step(step, kind: kind, key: key))
            }
        }
    }

    func checkPassword(trackId: String, password: String) async throws -> CoreAuthStep {
        try await call { done in
            client.checkPassword(trackId: trackId, password: password) { step, kind, key in
                done(Self.step(step, kind: kind, key: key))
            }
        }
    }

    func register(token: String, firstName: String, lastName: String) async throws -> CoreAuthStep {
        try await call { done in
            client.register(registerToken: token, firstName: firstName, lastName: lastName) { step, kind, key in
                done(Self.step(step, kind: kind, key: key))
            }
        }
    }

    func logout() async throws {
        try await call { done in
            client.logout { kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(()))
                }
            }
        }
    }

    func loadChats() async throws -> [CoreChat] {
        try await call { done in
            client.loadChats { chats, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(chats.map(Self.chat)))
                }
            }
        }
    }

    func loadChat(id: String) async throws -> CoreChat {
        try await call { done in
            client.loadChat(chatId: id) { chat, kind, key in
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
        try await call { done in
            client.loadHistory(chatId: chatId, beforeMs: beforeMs, limit: Int32(limit)) { messages, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(messages.map(Self.message)))
                }
            }
        }
    }

    func sendText(chatId: String, text: String) async throws -> CoreMessage {
        try await call { done in
            client.sendText(chatId: chatId, text: text) { message, kind, key in
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

    func markRead(chatId: String, messageId: String) async throws {
        try await call { done in
            client.markRead(chatId: chatId, messageId: messageId) { kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(()))
                }
            }
        }
    }

    func phases() -> AsyncStream<CorePhase> {
        AsyncStream { continuation in
            continuation.yield(CorePhase(raw: client.phaseName()))
            let watch = client.watchState { name in
                continuation.yield(CorePhase(raw: name))
            }
            continuation.onTermination = { _ in watch.cancel() }
        }
    }

    func events() -> AsyncStream<CoreEvent> {
        AsyncStream { continuation in
            let watch = client.watchEvents { event in
                if let mapped = Self.event(event) {
                    continuation.yield(mapped)
                }
            }
            continuation.onTermination = { _ in watch.cancel() }
        }
    }

    private func call<T: Sendable>(_ start: @escaping (@escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate()
            start { result in
                gate.run {
                    continuation.resume(with: result)
                }
            }
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
            unread: Int(chat.unread)
        )
    }

    private static func message(_ message: IosMessage) -> CoreMessage {
        CoreMessage(
            id: message.id,
            chatId: message.chatId,
            authorId: message.authorId,
            text: message.text,
            timeMs: message.timeMs
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
            unread: Int(event.unread)
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
