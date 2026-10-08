import Foundation
import OrbitleData
import OrbitleDomain
import MaxIos

/// Реакции на сообщения через `MaxIosClient` (docs/reactions.md).
extension MaxIosCore {
    func setReaction(chatId: String, messageId: String, postId: String, emoji: String) async throws -> String {
        try await call("setReaction") { done in
            self.client.setReaction(chatId: chatId, messageId: messageId, postId: postId, reaction: emoji) { json, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(json ?? ""))
                }
            }
        }
    }

    func loadReactions(chatId: String, messageIds: [String]) async throws -> [String: String] {
        try await call("loadReactions") { done in
            self.client.loadReactions(chatId: chatId, messageIds: messageIds) { list, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    var reactions: [String: String] = [:]
                    for item in list { reactions[item.messageId] = item.json }
                    done(.success(reactions))
                }
            }
        }
    }

    func loadReactionCatalog() async throws -> [String] {
        try await call("loadReactionCatalog") { done in
            self.client.loadReactionCatalog { emoji, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(emoji))
                }
            }
        }
    }

    func transcribeVoice(chatId: String, messageId: String, audioId: String) async throws -> CoreTranscription {
        try await call("transcribeVoice") { done in
            self.client.transcribeVoice(chatId: chatId, messageId: messageId, audioId: audioId) { result, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(CoreTranscription(status: Int(result.status), text: result.text)))
                }
            }
        }
    }

    func loadReactionUsers(chatId: String, messageId: String) async throws -> [ReactionUser] {
        try await call("loadReactionUsers") { done in
            self.client.loadReactionUsers(chatId: chatId, messageId: messageId) { users, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(users.map {
                        ReactionUser(
                            userId: $0.userId,
                            name: $0.name,
                            avatarURL: URL(string: $0.avatarUrl).flatMap { $0.scheme == nil ? nil : $0 },
                            emoji: $0.reaction
                        )
                    }))
                }
            }
        }
    }

    /// «Кем прочитано» (docs/readers.md). `readMark` `0` у моста — в списке только из-за реакции.
    func loadMessageReaders(chatId: String, messageId: String) async throws -> [MessageReader] {
        try await call("loadMessageReaders") { done in
            self.client.loadMessageReaders(chatId: chatId, messageId: messageId) { readers, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(readers.map {
                        MessageReader(
                            userId: $0.userId,
                            reaction: $0.reaction.flatMap { $0.isEmpty ? nil : $0 },
                            readMark: $0.readMark > 0 ? $0.readMark : nil,
                            name: $0.name ?? ""
                        )
                    }))
                }
            }
        }
    }

    func isReadersAvailable(chatId: String) -> Bool {
        client.isReadersAvailable(chatId: chatId)
    }
}
