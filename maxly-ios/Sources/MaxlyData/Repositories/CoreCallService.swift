import Foundation
import MaxlyDomain

/// Звонки через ядро: начать (78), войти по ссылке (166), создать ссылку (76/84), описание
/// ссылки (89), отклонить входящий (167), входящие (пуш 137) и звонящие без данных для ответа (103 и `calls` входа).
public struct CoreCallService: CallService {
    private let core: any MaxCore

    public init(core: any MaxCore) {
        self.core = core
    }

    public func startCall(peerId: String, isVideo: Bool) async throws(MaxlyError) -> CallConnection {
        let start = try await run("Звонок \(peerId)") { try await core.startCall(calleeId: peerId, isVideo: isVideo) }
        return try Self.connection(start)
    }

    public func join(link: String, isVideo: Bool) async throws(MaxlyError) -> CallConnection {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .invalidRequest }
        let start = try await run("Вход в звонок") { try await core.joinCall(link: trimmed, isVideo: isVideo) }
        return try Self.connection(start)
    }

    public func createLink() async throws(MaxlyError) -> CallLink {
        let link = try await run("Ссылка на звонок") { try await core.createCallLink() }
        guard let url = URL(string: link.url) else { throw .invalidRequest }
        return CallLink(url: url, name: link.name.isEmpty ? nil : link.name)
    }

    public func preview(link: String) async throws(MaxlyError) -> CallLinkPreview? {
        guard let info = try await run("Ссылка \(link)", { try await core.callLinkInfo(link: link) }),
              let url = URL(string: info.url)
        else { return nil }
        return CallLinkPreview(url: url, name: info.name.isEmpty ? nil : info.name, participants: info.participants, isVideo: info.isVideo)
    }

    public func reject(conversationId: String, peerId: String) async throws(MaxlyError) {
        guard !conversationId.isEmpty else { throw .invalidRequest }
        try await run("Отклонить \(conversationId)") {
            try await core.rejectIncomingCall(conversationId: conversationId, peerId: peerId, reason: "")
        }
        Log.info(.calls, "Входящий \(conversationId) отклонён")
    }

    public func incomingCalls() -> AsyncStream<IncomingCall> {
        let source = core.incomingCalls()
        return AsyncStream { continuation in
            let task = Task {
                for await call in source {
                    if let incoming = Self.incoming(call) {
                        Log.info(.calls, "Входящий звонок \(call.conversationId) от \(call.callerId)")
                        continuation.yield(incoming)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Форма ответа 103 пишется в журнал без пользовательских данных.
    public func ringingCalls() async throws(MaxlyError) -> [RingingCall] {
        let reply = try await run("Опрос входящих") { try await core.probeInboundCalls() }
        let calls = reply.calls.compactMap(Self.ringing)
        Log.info(.calls, "Опрос входящих (103): звонят \(calls.count); ответ \(reply.shape)")
        DiagnosticEvent.event("calls.inbound_probe", ["result": "ok", "source": "103", "found": String(calls.count), "shape": reply.shape], snapshot: true)
        return calls
    }

    public func callsAtLogin(maxAge: Duration) async -> [RingingCall] {
        guard let reply = try? await core.loginInboundCalls(maxAgeMs: Int64(maxAge / .milliseconds(1))) else { return [] }
        let calls = reply.calls.compactMap(Self.ringing)
        Log.info(.calls, "Звонки при входе: \(calls.count); calls \(reply.shape)")
        DiagnosticEvent.event("calls.inbound_probe", ["result": "ok", "source": "login", "found": String(calls.count), "shape": reply.shape], snapshot: true)
        return calls
    }

    static func ringing(_ call: CoreInboundCall) -> RingingCall? {
        guard !call.conversationId.isEmpty, !call.callerId.isEmpty else { return nil }
        return RingingCall(
            conversationId: call.conversationId,
            callerId: call.callerId,
            callerName: call.callerName,
            callerAvatarURL: call.callerAvatarURL.isEmpty ? nil : URL(string: call.callerAvatarURL),
            chatId: call.chatId.isEmpty ? nil : call.chatId,
            isVideo: call.isVideo
        )
    }

    static func connection(_ start: CoreCallStart) throws(MaxlyError) -> CallConnection {
        guard let url = URL(string: start.ws2Url), url.scheme?.hasPrefix("ws") == true else {
            Log.warning(.calls, "Сервер дал адрес звонка не ws")
            throw .invalidRequest
        }
        return CallConnection(
            conversationId: start.conversationId,
            signalingURL: url,
            selfId: start.callsUserId,
            isVideo: start.isVideo,
            joinLink: start.joinLink.isEmpty ? nil : URL(string: start.joinLink)
        )
    }

    static func incoming(_ call: CoreIncomingCall) -> IncomingCall? {
        guard let url = URL(string: call.ws2Url), !call.conversationId.isEmpty else { return nil }
        var servers: [CallIceServer] = []
        if !call.stunUrls.isEmpty { servers.append(CallIceServer(urls: call.stunUrls)) }
        if !call.turnUrls.isEmpty {
            servers.append(CallIceServer(
                urls: call.turnUrls,
                username: call.turnUsername.isEmpty ? nil : call.turnUsername,
                credential: call.turnPassword.isEmpty ? nil : call.turnPassword
            ))
        }
        return IncomingCall(
            conversationId: call.conversationId,
            callerId: call.callerId,
            callerName: call.callerName,
            callerAvatarURL: call.callerAvatarURL.isEmpty ? nil : URL(string: call.callerAvatarURL),
            chatId: call.chatId.isEmpty ? nil : call.chatId,
            isVideo: call.isVideo,
            connection: CallConnection(
                conversationId: call.conversationId,
                signalingURL: url,
                selfId: call.callsUserId,
                iceServers: servers,
                isVideo: call.isVideo
            ),
            expiresAt: call.expiresAtMs > 0 ? Date(timeIntervalSince1970: TimeInterval(call.expiresAtMs) / 1000) : nil
        )
    }

    private func run<T: Sendable>(_ what: String, _ body: () async throws -> T) async throws(MaxlyError) -> T {
        do {
            return try await body()
        } catch {
            Log.warning(.calls, "\(what): \(error)")
            throw CoreMapping.apiError(error).maxlyError
        }
    }
}
