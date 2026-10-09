import Foundation

/// Сервер ICE для WebRTC: STUN или TURN с логином и паролем.
public struct CallIceServer: Hashable, Sendable {
    public var urls: [String]
    public var username: String?
    public var credential: String?

    public init(urls: [String], username: String? = nil, credential: String? = nil) {
        self.urls = urls
        self.username = username
        self.credential = credential
    }
}

/// Куда подключаться к звонку: сигнальный сокет ws2 сервера звонков и свой номер в звонке.
///
/// Номера участников в звонке (`selfId`, id в уведомлениях ws2) — внутренние номера сервера
/// звонков, не id пользователей Max. Id пользователя Max участник несёт в `externalId`.
public struct CallConnection: Hashable, Sendable {
    public var conversationId: String
    /// Адрес ws2 со всеми параметрами запроса, в нём же токен.
    public var signalingURL: URL
    /// Свой номер в звонке.
    public var selfId: Int64
    /// Серверы ICE из пуша входящего звонка. У исходящего пусто: их присылает ws2 в `connection`.
    public var iceServers: [CallIceServer]
    public var isVideo: Bool
    /// Ссылка группового звонка, которой можно поделиться.
    public var joinLink: URL?

    public init(
        conversationId: String,
        signalingURL: URL,
        selfId: Int64,
        iceServers: [CallIceServer] = [],
        isVideo: Bool = false,
        joinLink: URL? = nil
    ) {
        self.conversationId = conversationId
        self.signalingURL = signalingURL
        self.selfId = selfId
        self.iceServers = iceServers
        self.isVideo = isVideo
        self.joinLink = joinLink
    }
}

/// Входящий звонок из пуша сервера.
public struct IncomingCall: Identifiable, Hashable, Sendable {
    public var id: String { conversationId }
    public var conversationId: String
    /// Id пользователя Max, который звонит.
    public var callerId: String
    /// Пусто, если звонящего нет в контактах и его профиль не загрузился.
    public var callerName: String
    public var callerAvatarURL: URL?
    public var chatId: String?
    public var isVideo: Bool
    public var connection: CallConnection
    /// После этого времени звонок уже не принять. `nil` — сервер не сказал.
    public var expiresAt: Date?

    public init(
        conversationId: String,
        callerId: String,
        callerName: String,
        callerAvatarURL: URL? = nil,
        chatId: String? = nil,
        isVideo: Bool,
        connection: CallConnection,
        expiresAt: Date? = nil
    ) {
        self.conversationId = conversationId
        self.callerId = callerId
        self.callerName = callerName
        self.callerAvatarURL = callerAvatarURL
        self.chatId = chatId
        self.isVideo = isVideo
        self.connection = connection
        self.expiresAt = expiresAt
    }
}

/// Созданная ссылка на групповой звонок.
public struct CallLink: Hashable, Sendable {
    public var url: URL
    /// Название звонка; `nil`, если сервер его не дал.
    public var name: String?

    public init(url: URL, name: String? = nil) {
        self.url = url
        self.name = name
    }
}

/// Что за звонок стоит за ссылкой, до входа в него.
public struct CallLinkPreview: Hashable, Sendable {
    public var url: URL
    public var name: String?
    public var participants: Int
    public var isVideo: Bool

    public init(url: URL, name: String? = nil, participants: Int = 0, isVideo: Bool = false) {
        self.url = url
        self.name = name
        self.participants = participants
        self.isVideo = isVideo
    }
}

/// Кто мы в звонке. От роли зависит, кто первым шлёт SDP и с какой причиной кладётся трубка.
public enum CallRole: String, Hashable, Sendable {
    /// Позвонили сами.
    case caller
    /// Ответили на входящий.
    case callee
    /// Вошли в групповой звонок по ссылке.
    case joiner
}

/// Как шёл звук и видео: напрямую между двумя участниками или через сервер (SFU).
public enum CallTopology: String, Hashable, Sendable {
    case direct = "DIRECT"
    case server = "SERVER"
}

/// Почему звонок закончился.
public enum CallEndReason: Hashable, Sendable {
    /// Положили трубку сами.
    case hungUp
    /// Собеседник положил трубку, или сервер закрыл звонок.
    case remoteHungUp
    /// Собеседник отклонил вызов.
    case declined
    /// Собеседник занят другим звонком.
    case busy
    /// Никто не ответил.
    case noAnswer
    /// Входящий звонок отклонили сами.
    case rejected
    /// Входящий звонок сбросил звонящий, пока он звонил.
    case missed
    /// Связь с сервером звонков не восстановилась.
    case connectionLost
    /// Звонок не начался: сервер отказал или нет доступа к микрофону.
    case failed(String)
}

/// Камера телефона.
public enum CallCameraPosition: String, Hashable, Sendable {
    case front, back
}

/// Участник звонка.
public struct CallParticipant: Identifiable, Hashable, Sendable {
    /// Номер в звонке (не id Max).
    public let id: Int64
    /// Id пользователя Max; `nil`, пока сервер его не прислал.
    public var userId: String?
    public var isSelf: Bool
    /// Состояние на сервере звонков: `CALLED`, `ACCEPTED`, `HUNGUP` и т. п.
    public var state: String
    public var audioOn: Bool
    public var videoOn: Bool
    public var screenOn: Bool
    public var handRaised: Bool
    public var speaking: Bool
    public var roles: [String]
    /// Видео камеры и экрана для отрисовки: id дорожек WebRTC.
    public var cameraTrack: String?
    public var screenTrack: String?

    public init(
        id: Int64,
        userId: String? = nil,
        isSelf: Bool = false,
        state: String = "",
        audioOn: Bool = true,
        videoOn: Bool = false,
        screenOn: Bool = false,
        handRaised: Bool = false,
        speaking: Bool = false,
        roles: [String] = [],
        cameraTrack: String? = nil,
        screenTrack: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.isSelf = isSelf
        self.state = state
        self.audioOn = audioOn
        self.videoOn = videoOn
        self.screenOn = screenOn
        self.handRaised = handRaised
        self.speaking = speaking
        self.roles = roles
        self.cameraTrack = cameraTrack
        self.screenTrack = screenTrack
    }

    /// Админ или создатель звонка: может включать запись.
    public var isAdmin: Bool { roles.contains("ADMIN") || roles.contains("CREATOR") }

    /// Видео, которое стоит показать: экран важнее камеры.
    public var visibleTrack: String? {
        if screenOn, let screenTrack { return screenTrack }
        if videoOn, let cameraTrack { return cameraTrack }
        return nil
    }
}

/// Состояние звонка для экрана.
public struct CallState: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        /// Подключаемся к серверу звонков.
        case connecting
        /// Исходящий: у собеседника звонит. Входящий: ждём ответа пользователя.
        case ringing
        /// Разговор идёт.
        case active
        /// Связь пропала, подключаемся заново.
        case reconnecting
        case ended(CallEndReason)
    }

    public var phase: Phase = .connecting
    /// Когда начался разговор: для таймера.
    public var activeSince: Date?
    public var muted = false
    public var cameraOn = false
    public var camera: CallCameraPosition = .front
    public var screenSharing = false
    public var speakerOn = false
    /// Звук и видео уже идут (WebRTC соединился).
    public var mediaConnected = false
    public var topology: CallTopology = .direct
    /// Все участники, свой — с `isSelf`.
    public var participants: [CallParticipant] = []
    /// Своё видео (камера или экран) для превью.
    public var localTrack: String?
    /// Идёт запись звонка.
    public var recording = false
    /// Сообщение для экрана: не включилась камера, не начался показ экрана и т. п.
    public var notice: String?

    public init() {}

    public var isEnded: Bool {
        if case .ended = phase { return true }
        return false
    }

    /// Остальные участники, без себя.
    public var others: [CallParticipant] { participants.filter { !$0.isSelf } }
}
