import Foundation
import OrbitleDomain

/// Сокет сигнального сервера звонков (ws2): текстовые кадры в обе стороны.
public protocol Ws2Socket: AnyObject, Sendable {
    func send(_ text: String) async throws
    /// Следующий текстовый кадр. Ошибка — сокет закрыт.
    func receive() async throws -> String
    func close()
}

/// Открывает сокет ws2 по полному адресу.
public typealias Ws2Connector = @Sendable (URL) async throws -> any Ws2Socket

public enum Ws2Error: Error, Equatable, Sendable {
    /// Сокет закрыт: ответа уже не будет.
    case closed
    /// Сервер не ответил на команду за отведённое время.
    case timeout(command: String)
    /// Сервер ответил на команду ошибкой, например `conversation-ended`.
    case command(command: String, error: String)
}

/// Сигнальный канал звонка поверх ws2.
///
/// Конверт сообщений (схема Komet `ws2_signaling.dart`, kolibri-net `calls/signaling.rs`):
/// - команда: `{"command": …, …, "sequence": N}`, номера с 1;
/// - ответ: `{"sequence": N, "response": "<команда>", "type": "response"}`;
/// - ошибка: `{"sequence": N, "type": "error", "error": …}` — она же уходит в уведомления;
/// - уведомление: `{"notification": "<имя>", "type": "notification", …}`;
/// - текстовый кадр `ping` — ответ `pong`.
///
/// Кадры уходят строго по порядку: SDP раньше кандидатов, которые после него.
public actor Ws2Signaling {
    /// Уведомления сервера и ошибки команд по порядку прихода. Поток кончается, когда сокет закрыт.
    public nonisolated let notifications: AsyncStream<JSONValue>

    private let socket: any Ws2Socket
    private let timeout: Duration
    private let notify: AsyncStream<JSONValue>.Continuation
    private let outbox: AsyncStream<String>.Continuation
    private let outgoing: AsyncStream<String>
    private var sequence: Int64 = 0
    private var pending: [Int64: (command: String, continuation: CheckedContinuation<JSONValue, any Error>)] = [:]
    private var reader: Task<Void, Never>?
    private var writer: Task<Void, Never>?
    private var closed = false

    public init(socket: any Ws2Socket, timeout: Duration = .seconds(15)) {
        self.socket = socket
        self.timeout = timeout
        (notifications, notify) = AsyncStream.makeStream(of: JSONValue.self)
        (outgoing, outbox) = AsyncStream.makeStream(of: String.self)
    }

    /// Открывает сокет и начинает читать его.
    public static func connect(url: URL, connector: Ws2Connector, timeout: Duration = .seconds(15)) async throws -> Ws2Signaling {
        let signaling = Ws2Signaling(socket: try await connector(url), timeout: timeout)
        await signaling.run()
        return signaling
    }

    /// Запускает чтение и запись. Повторный вызов ничего не делает.
    public func run() {
        guard reader == nil, !closed else { return }
        let socket = self.socket
        let outgoing = self.outgoing
        writer = Task {
            for await text in outgoing {
                do {
                    try await socket.send(text)
                } catch {
                    self.finish()
                    return
                }
            }
        }
        reader = Task {
            while !Task.isCancelled {
                let text: String
                do {
                    text = try await socket.receive()
                } catch {
                    break
                }
                self.route(text)
            }
            self.finish()
        }
    }

    /// Отправляет команду и ждёт ответ. Ответ-ошибка бросает `Ws2Error.command`.
    @discardableResult
    public func send(_ command: String, _ extra: [String: JSONValue] = [:]) async throws -> JSONValue {
        guard !closed else { throw Ws2Error.closed }
        sequence += 1
        let number = sequence
        var body = extra
        body["command"] = .string(command)
        body["sequence"] = .int(number)
        let text = JSONValue.object(body).serialized()
        let response: JSONValue = try await withCheckedThrowingContinuation { continuation in
            pending[number] = (command, continuation)
            outbox.yield(text)
            armTimeout(number)
        }
        if response["type"]?.string == "error" || response["error"].map({ !$0.isNull }) == true {
            throw Ws2Error.command(command: command, error: Self.describe(response["error"]))
        }
        return response
    }

    /// Закрывает сокет. Ждущие ответа команды получают `Ws2Error.closed`.
    public func close() {
        guard !closed else { return }
        socket.close()
        reader?.cancel()
        finish()
    }

    public var isClosed: Bool { closed }

    // MARK: Внутреннее

    func route(_ text: String) {
        if text == "ping" {
            outbox.yield("pong")
            return
        }
        guard let message = JSONValue.parse(text), message.object != nil else { return }
        let type = message["type"]?.string
        if type == "response" || type == "error" {
            if let number = message["sequence"]?.int, let waiter = pending.removeValue(forKey: number) {
                waiter.continuation.resume(returning: message)
            }
            if type == "error" { notify.yield(message) }
            return
        }
        if type == "notification" || message["notification"] != nil {
            notify.yield(message)
        }
    }

    private func armTimeout(_ number: Int64) {
        let timeout = self.timeout
        Task {
            try? await Task.sleep(for: timeout)
            self.expire(number)
        }
    }

    private func expire(_ number: Int64) {
        guard let waiter = pending.removeValue(forKey: number) else { return }
        waiter.continuation.resume(throwing: Ws2Error.timeout(command: waiter.command))
    }

    private func finish() {
        let wasClosed = closed
        closed = true
        let waiting = pending
        pending = [:]
        waiting.values.forEach { $0.continuation.resume(throwing: Ws2Error.closed) }
        guard !wasClosed else { return }
        notify.finish()
        outbox.finish()
        writer?.cancel()
    }

    private static func describe(_ error: JSONValue?) -> String {
        switch error {
        case .string(let text)?: text
        case nil, .null?: "error"
        case let other?: other.serialized()
        }
    }
}

/// Сокет ws2 на `URLSessionWebSocketTask`. Представляется клиентом okhttp, как SDK звонков.
public final class URLSessionWs2Socket: NSObject, Ws2Socket, URLSessionWebSocketDelegate, @unchecked Sendable {
    public static let userAgent = "okhttp/4.12.0"

    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var opening: CheckedContinuation<Void, any Error>?
    private var openResult: Result<Void, any Error>?

    private override init() {
        super.init()
    }

    /// Открывает сокет и ждёт рукопожатия (не дольше 15 с).
    public static func connect(url: URL) async throws -> any Ws2Socket {
        let socket = URLSessionWs2Socket()
        try await socket.open(url)
        return socket
    }

    private func open(_ url: URL) async throws {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 8 << 20
        lock.withLock {
            self.session = session
            self.task = task
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let early: Result<Void, any Error>? = lock.withLock {
                if let openResult { return openResult }
                opening = continuation
                return nil
            }
            if let early {
                continuation.resume(with: early)
            } else {
                task.resume()
            }
        }
    }

    public func send(_ text: String) async throws {
        guard let task = lock.withLock({ task }) else { throw Ws2Error.closed }
        try await task.send(.string(text))
    }

    public func receive() async throws -> String {
        guard let task = lock.withLock({ task }) else { throw Ws2Error.closed }
        while true {
            switch try await task.receive() {
            case .string(let text): return text
            case .data(let data): return String(decoding: data, as: UTF8.self)
            @unknown default: continue
            }
        }
    }

    public func close() {
        let (task, session) = lock.withLock { () -> (URLSessionWebSocketTask?, URLSession?) in
            defer {
                self.task = nil
                self.session = nil
            }
            return (self.task, self.session)
        }
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        settle(.failure(Ws2Error.closed))
    }

    private func settle(_ result: Result<Void, any Error>) {
        let waiter: CheckedContinuation<Void, any Error>? = lock.withLock {
            guard openResult == nil else { return nil }
            openResult = result
            defer { opening = nil }
            return opening
        }
        waiter?.resume(with: result)
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        settle(.success(()))
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        settle(.failure(error ?? Ws2Error.closed))
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        settle(.failure(Ws2Error.closed))
    }
}

/// Тела команд ws2 (схема Komet `ws2_signaling.dart`).
public enum Ws2Command {
    /// `hexCapability` SDK звонков: его же сервер видит в `internalParams`.
    public static let capabilities = "3c02f"

    /// Что сейчас отправляется: звук, камера, экран.
    public static func mediaSettings(audio: Bool, video: Bool, screen: Bool) -> JSONValue {
        [
            "isVideoEnabled": .bool(video),
            "isAudioEnabled": .bool(audio),
            "isScreenSharingEnabled": .bool(screen),
            "isAnimojiEnabled": false,
        ]
    }

    public static func transmit(sdp: SessionDescription, to peer: CallPeerAddress) -> [String: JSONValue] {
        [
            "participantId": .int(peer.id),
            "participantType": .string(peer.type),
            "deviceIdx": .int(peer.deviceIdx),
            "data": ["sdp": ["type": .string(sdp.type.rawValue), "sdp": .string(sdp.sdp)]],
            "capabilities": .string(capabilities),
        ]
    }

    public static func transmit(candidate: IceCandidate, to peer: CallPeerAddress) -> [String: JSONValue] {
        [
            "participantId": .int(peer.id),
            "participantType": .string(peer.type),
            "deviceIdx": .int(peer.deviceIdx),
            "data": [
                "candidate": [
                    "candidate": .string(candidate.sdp),
                    "sdpMid": .string(candidate.sdpMid ?? "0"),
                    "sdpMLineIndex": .int(Int64(candidate.sdpMLineIndex)),
                ],
            ],
        ]
    }

    /// `allocate-consumer`: что клиент умеет принимать от SFU.
    public static let allocateConsumer: [String: JSONValue] = [
        "capabilities": [
            "maxH264Decoders": 10,
            "producerNotificationDataChannelVersion": 7,
            "producerCommandDataChannelVersion": 2,
            "audioMix": true,
            "consumerUpdate": true,
            "onDemandTracks": true,
            "singleSession": true,
            "unifiedPlan": true,
            "fastScreenShare": true,
            "consumerFastScreenShareQualityOnDemand": true,
            "red": true,
            "videoTracksCount": 10,
            "csrcAccessible": true,
        ],
    ]

    /// `record-start` с теми же полями, что шлёт Komet: всё, кроме `streamMovie`, пустое.
    public static let recordStart: [String: JSONValue] = [
        "movieId": nil,
        "name": nil,
        "description": nil,
        "privacy": nil,
        "groupId": nil,
        "albumId": nil,
        "streamMovie": false,
    ]
}

/// Кому слать SDP и кандидатов: номер участника, тип и номер устройства.
public struct CallPeerAddress: Hashable, Sendable {
    public var id: Int64
    public var type: String
    public var deviceIdx: Int64

    public init(id: Int64, type: String = "USER", deviceIdx: Int64 = 0) {
        self.id = id
        self.type = type
        self.deviceIdx = deviceIdx
    }
}
