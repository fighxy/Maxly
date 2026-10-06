import Foundation
import MaxIos
import OrbitleData

/// Звонки через фасад ядра: начать (78), войти по ссылке (166), создать ссылку (76/84), описание
/// ссылки (89), удалить из журнала (164) и входящие (пуш 137). Сокет ws2 и WebRTC — в приложении.
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
                    done(.failure(CoreFailure(kind: kind, key: key)))
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
                    done(.failure(CoreFailure(kind: kind, key: key)))
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
                    done(.failure(CoreFailure(kind: kind, key: key)))
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

    private static func started(_ start: IosCallStart?, _ kind: String?, _ key: String?) -> Result<CoreCallStart, Error> {
        if let kind { return .failure(CoreFailure(kind: kind, key: key)) }
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
