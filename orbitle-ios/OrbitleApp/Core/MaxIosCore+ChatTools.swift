import Foundation
import OrbitleData
import OrbitleDomain
import MaxIos

extension MaxIosCore {
    func sendRichText(chatId: String, text: String, replyTo: String, animoji: [CoreAnimojiMark], mentions: [CoreMentionMark]) async throws -> CoreMessage {
        let emoji = animoji.map {
            IosAnimojiMark(from: Int32($0.from), length: Int32($0.length), animojiId: $0.animojiId, lottieUrl: $0.lottieURL)
        }
        let marks = mentions.map {
            IosMentionMark(from: Int32($0.from), length: Int32($0.length), userId: $0.userId)
        }
        return try await call("sendRichText") { done in
            self.client.sendRichText(chatId: chatId, text: text, replyTo: replyTo, animoji: emoji, mentions: marks) { message, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else if let message {
                    done(.success(Self.message(message)))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func pinMessage(chatId: String, messageId: String) async throws {
        let _: Void = try await call("pinMessage") { done in
            self.client.pinMessage(chatId: chatId, messageId: messageId) { kind, key in
                if let kind { done(.failure(Self.failed(kind: kind, key: key))) } else { done(.success(())) }
            }
        }
    }

    func scheduleMessage(chatId: String, text: String, sendAtMs: Int64) async throws {
        let _: Void = try await call("scheduleMessage") { done in
            self.client.scheduleMessage(chatId: chatId, text: text, sendAt: sendAtMs) { _, kind, key in
                if let kind { done(.failure(Self.failed(kind: kind, key: key))) } else { done(.success(())) }
            }
        }
    }

    func scheduledMessages(chatId: String) async throws -> [CoreFoundMessage] {
        try await call("scheduledMessages") { done in
            self.client.scheduledMessages(chatId: chatId) { messages, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success((messages ?? []).map(Self.scheduled)))
                }
            }
        }
    }

    func sendPoll(chatId: String, title: String, answers: [String]) async throws -> CoreMessage {
        try await call("sendPoll") { done in
            self.client.sendPoll(chatId: chatId, title: title, answers: answers) { message, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else if let message {
                    done(.success(Self.message(message)))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func votePoll(chatId: String, messageId: String, pollId: String, answerId: String) async throws {
        let _: Void = try await call("votePoll") { done in
            self.client.votePoll(chatId: chatId, messageId: messageId, pollId: pollId, answerId: answerId) { _, kind, key in
                if let kind { done(.failure(Self.failed(kind: kind, key: key))) } else { done(.success(())) }
            }
        }
    }

    func searchInChat(chatId: String, query: String) async throws -> [CoreFoundMessage] {
        try await call("searchInChat") { done in
            self.client.searchInChat(chatId: chatId, query: query) { messages, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success(messages.map(Self.found)))
                }
            }
        }
    }

    func chatMembers(chatId: String) async throws -> [CoreChatMember] {
        try await call("chatMembers") { done in
            self.client.chatMembers(chatId: chatId) { members, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success(members.map {
                        CoreChatMember(id: $0.id, name: $0.name, avatarURL: $0.avatarUrl.isEmpty ? nil : URL(string: $0.avatarUrl))
                    }))
                }
            }
        }
    }

    func botCommands(botId: String) async throws -> [CoreBotCommand] {
        try await call("botCommands") { done in
            self.client.botCommands(botId: botId) { commands, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success(commands.map { CoreBotCommand(name: $0.name, summary: $0.description_) }))
                }
            }
        }
    }

    func pressButton(chatId: String, messageId: String, callbackId: String, payload: String) async throws -> CoreButtonAnswer {
        try await call("pressButton") { done in
            self.client.pressButton(chatId: chatId, messageId: messageId, callbackId: callbackId, payload: payload) { answer, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success(CoreButtonAnswer(text: answer?.text ?? "", url: answer?.url ?? "")))
                }
            }
        }
    }


    /// Отложенное сообщение в том же виде, что поиск: время — когда оно уйдёт.
    private static func scheduled(_ message: IosScheduledMessage) -> CoreFoundMessage {
        CoreFoundMessage(
            chatId: message.chatId, messageId: message.messageId, senderId: message.senderId,
            text: message.text, timeMs: message.sendAt
        )
    }

    private static func found(_ message: IosFoundMessage) -> CoreFoundMessage {
        CoreFoundMessage(
            chatId: message.chatId,
            messageId: message.messageId,
            senderId: message.senderId,
            text: message.text,
            timeMs: message.timeMs
        )
    }
}
