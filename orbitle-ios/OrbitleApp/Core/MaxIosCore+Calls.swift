import Foundation
import MaxlyCore
import OrbitleDomain
import OrbitleData

/// Звонки через фасад ядра: начать (78), войти по ссылке (166), создать ссылку (76/84), описание
/// ссылки (89), журнал по курсору (163), удалить из журнала (164), отклонить входящий (167)
/// и входящие (пуш 137). Сокет ws2 и WebRTC — в приложении.
extension MaxIosCore {
    func startCall(calleeId: String, isVideo: Bool) async throws -> CoreCallStart {
        try await call("startCall") { done in
            self.client.startCall(calleeId: calleeId, isVideo: isVideo) { start, kind, key in
                done(Self.started(start, kind, key))
            }
        }
    }

    func joinCall(link: String, isVideo: Bool) async throws -> CoreCallStart {
        try await call("joinCall") { done in
            self.client.joinCall(link: link, isVideo: isVideo) { start, kind, key in
                done(Self.started(start, kind, key))
            }
        }
    }

    func createCallLink() async throws -> CoreCallLink {
        try await call("createCallLink") { done in
            self.client.createCallLink { link, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else if let link {
                    done(.success(CoreCallLink(conversationId: link.conversationId, url: link.url, name: link.name)))
                } else {
                    done(.failure(CoreFailure(kind: "UNKNOWN", key: nil)))
                }
            }
        }
    }

    func callLinkInfo(link: String) async throws -> CoreCallLinkInfo? {
        try await call("callLinkInfo") { done in
            self.client.callLinkInfo(link: link) { info, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success(info.map {
                        CoreCallLinkInfo(url: $0.url, name: $0.name, participants: Int($0.participants), isVideo: $0.isVideo)
                    }))
                }
            }
        }
    }

    func deleteCallHistory(ids: [String]) async throws {
        let _: Void = try await call("deleteCallHistory") { done in
            self.client.deleteCallHistory(ids: ids) { kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success(()))
                }
            }
        }
    }

    func callHistory(sync: String) async throws -> CallLogPage {
        try await call("callHistory") { done in
            self.client.callHistory(sync: sync) { history, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else if let history {
                    done(.success(CallLogPage(
                        sync: history.sync,
                        reset: history.reset,
                        items: history.items.map(Self.callLogItem)
                    )))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func rejectIncomingCall(conversationId: String, peerId: String, reason: String) async throws {
        let _: Void = try await call("rejectIncomingCall") { done in
            self.client.rejectIncomingCall(conversationId: conversationId, peerId: peerId, reason: reason) { kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success(()))
                }
            }
        }
    }

    func incomingCalls() -> AsyncStream<CoreIncomingCall> {
        AsyncStream { continuation in
            let watch = WatchBox(client.watchIncomingCalls { call in
                continuation.yield(CoreIncomingCall(
                    conversationId: call.conversationId,
                    callerId: call.callerId,
                    callerName: call.callerName,
                    callerAvatarURL: call.callerAvatarUrl,
                    chatId: call.chatId,
                    isVideo: call.isVideo,
                    ws2Url: call.ws2Url,
                    callsUserId: call.callsUserId,
                    stunUrls: call.stunUrls,
                    turnUrls: call.turnUrls,
                    turnUsername: call.turnUsername,
                    turnPassword: call.turnPassword,
                    expiresAtMs: call.expiresAtMs
                ))
            })
            continuation.onTermination = { _ in watch.cancel() }
        }
    }

    private static func callLogItem(_ record: IosCallRecord) -> CallLogItem {
        CallLogItem(
            historyId: record.historyId,
            callId: record.callId,
            callName: record.callName,
            callerId: record.callerId,
            messageId: record.messageId,
            chatId: record.chatId,
            isVideo: record.callType == "VIDEO",
            hangupType: record.hangupType,
            joinLink: record.joinLink,
            timeMs: record.timeMs,
            durationMs: record.durationMs,
            groupCallType: record.groupCallType
        )
    }

    private static func started(_ start: IosCallStart?, _ kind: String?, _ key: String?) -> Result<CoreCallStart, Error> {
        if let kind { return .failure(Self.failed(kind: kind, key: key)) }
        guard let start else { return .failure(CoreFailure(kind: "UNKNOWN", key: nil)) }
        return .success(CoreCallStart(
            conversationId: start.conversationId,
            ws2Url: start.ws2Url,
            callsUserId: start.callsUserId,
            joinLink: start.joinLink,
            isVideo: start.isVideo
        ))
    }
}
