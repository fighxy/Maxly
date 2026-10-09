import Foundation
import MaxlyData
import MaxlyDomain
import MaxlyCore

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

    func pinnedMessages(chatId: String, from: String, backward: Int) async throws -> [CoreMessage] {
        try await call("pinnedMessages") { done in
            self.client.pinnedMessages(chatId: chatId, from: from, backward: Int32(backward)) { messages, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success((messages ?? []).map(Self.message)))
                }
            }
        }
    }

    func updatePinned(chatId: String, action: String, messageIds: [String], forMe: Bool, notify: Bool) async throws {
        let _: Void = try await call("updatePinned") { done in
            self.client.updatePinned(chatId: chatId, action: action, messageIds: messageIds, forMe: forMe, notify: notify) { state, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else if state != nil {
                    done(.success(()))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
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

    func castPollVotes(chatId: String, messageId: String, pollId: String, answerIds: [String]) async throws -> CorePollCounts {
        try await call("castPollVotes") { done in
            self.client.castPollVotes(chatId: chatId, messageId: messageId, pollId: pollId, answerIds: answerIds) { state, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else if let state {
                    done(.success(Self.counts(pollId: pollId, total: Int(state.total), answers: state.answers, multiple: false)))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func pollUpdates(chatId: String, polls: [CorePollRef]) async throws -> [CorePollCounts] {
        let refs = polls.map { IosPollRef(messageId: $0.messageId, pollId: $0.pollId) }
        return try await call("pollUpdates") { done in
            self.client.pollUpdates(chatId: chatId, polls: refs) { polls, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success((polls ?? []).map {
                        Self.counts(pollId: $0.pollId, total: Int($0.total), answers: $0.answers, multiple: $0.multiple)
                    }))
                }
            }
        }
    }

    func editScheduled(chatId: String, messageId: String, text: String, sendAtMs: Int64) async throws -> CoreFoundMessage {
        try await call("editScheduled") { done in
            self.client.editScheduled(chatId: chatId, messageId: messageId, text: text, sendAt: sendAtMs) { message, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else if let message {
                    done(.success(Self.scheduled(message)))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func cancelScheduled(chatId: String, messageIds: [String]) async throws {
        let _: Void = try await call("cancelScheduled") { done in
            self.client.cancelScheduled(chatId: chatId, messageIds: messageIds) { kind, key in
                if let kind { done(.failure(Self.failed(kind: kind, key: key))) } else { done(.success(())) }
            }
        }
    }

    private static func counts(pollId: String, total: Int, answers: [IosPollAnswer], multiple: Bool) -> CorePollCounts {
        var votes: [String: Int] = [:]
        for answer in answers where !answer.answerId.isEmpty {
            votes[answer.answerId] = Int(answer.votes)
        }
        return CorePollCounts(pollId: pollId, total: total, votes: votes, multiple: multiple)
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
