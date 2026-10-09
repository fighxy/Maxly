import Foundation

/// Звонок в ленте: вложение `CALL`, которое сервер кладёт в чат после разговора.
///
/// Сообщение со звонком пишет тот, кто звонил, поэтому направление — это «своё ли
/// сообщение», и исход считается уже с ним (`outcome(outgoing:)`). Длительность сервер
/// присылает в миллисекундах.
public struct CallContent: Hashable, Sendable, Codable {
    /// `callType` вложения.
    public enum CallType: String, Hashable, Sendable, Codable {
        case audio = "AUDIO"
        case video = "VIDEO"
    }

    /// Как закончился звонок: `hangupType` вложения.
    public enum Hangup: String, Hashable, Sendable {
        /// Разговор был и кто-то положил трубку.
        case hungup = "HUNGUP"
        /// Звонивший сбросил до ответа.
        case canceled = "CANCELED"
        /// Вызываемый отклонил.
        case rejected = "REJECTED"
        /// Никто не ответил.
        case missed = "MISSED"
        /// Значение не пришло или незнакомо.
        case unknown = ""
    }

    /// id вложения в пузыре.
    public var id: String
    public var durationMs: Int64
    public var callType: CallType
    /// `hangupType` как его прислал сервер, в верхнем регистре. Незнакомое значение не
    /// теряется при записи в базу.
    public var hangupType: String
    /// id разговора на сервере звонков.
    public var conversationId: String?
    /// Участники звонка.
    public var contactIds: [String]
    /// Ссылка для входа. Есть только у группового звонка.
    public var joinLink: String?

    public init(
        id: String,
        durationMs: Int64 = 0,
        callType: CallType = .audio,
        hangupType: String = "",
        conversationId: String? = nil,
        contactIds: [String] = [],
        joinLink: String? = nil
    ) {
        self.id = id
        self.durationMs = max(0, durationMs)
        self.callType = callType
        self.hangupType = hangupType.uppercased()
        self.conversationId = conversationId?.isEmpty == true ? nil : conversationId
        self.contactIds = contactIds
        self.joinLink = joinLink?.isEmpty == true ? nil : joinLink
    }

    public var hangup: Hangup { Hangup(rawValue: hangupType) ?? .unknown }

    public var isVideo: Bool { callType == .video }

    /// Групповой звонок: у него есть ссылка для входа.
    public var isGroup: Bool { joinLink != nil }

    /// Разговор состоялся. Нулевая длительность или `MISSED`, `REJECTED`, `CANCELED` —
    /// не состоялся, так же решают ядро для истории звонков и другие клиенты MAX.
    public var isConnected: Bool {
        guard durationMs > 0 else { return false }
        switch hangup {
        case .missed, .rejected, .canceled: return false
        case .hungup, .unknown: return true
        }
    }

    /// Исход для того, кто смотрит. Правила те же, что у вкладки «Звонки»: несостоявшийся
    /// входящий — пропущенный, свой — отменённый, а `REJECTED` у своего — собеседник отклонил.
    public func outcome(outgoing: Bool) -> CallRecord.Outcome {
        if isConnected { return .answered }
        guard outgoing else { return .missed }
        return hangup == .rejected ? .declined : .cancelled
    }

    /// Пропущенный звонок: входящий, который не состоялся. Свой несостоявшийся звонок
    /// пропущенным не считается.
    public func isMissed(outgoing: Bool) -> Bool {
        !outgoing && !isConnected
    }
}
