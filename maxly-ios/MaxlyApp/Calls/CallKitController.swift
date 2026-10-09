import AVFoundation
import CallKit
import UIKit
import MaxlyCallMedia
import MaxlyDomain
import MaxlyPresentation

/// Системный экран звонка (CallKit) для центра звонков.
///
/// Входящий звонит системным экраном, в том числе на заблокированном телефоне; ответ, сброс и
/// микрофон с экрана приложения идут через `CXCallController`, чтобы система знала о них. Звук
/// включает система: WebRTC ждёт `didActivate` (`CallAudio`).
///
/// Без VoIP-пушей (их сервер Max шлёт только своему приложению) входящий приходит, пока
/// Maxly запущен: на экране или в фоне с открытым соединением.
@MainActor
final class CallKitController: NSObject, CallSystem {
    weak var delegate: (any CallSystemDelegate)?

    private let provider: CXProvider
    private let controller = CXCallController()
    /// Видео ли звонок: от этого режим аудиосессии.
    private var video: [UUID: Bool] = [:]

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = false
        if let mark = UIImage(named: "MaxlyMark")?.pngData() {
            configuration.iconTemplateImageData = mark
        }
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
        CallAudio.useCallKit()
    }

    // MARK: CallSystem

    func reportIncoming(id: UUID, handle: String, name: String, video: Bool) async throws {
        self.video[id] = video
        try await provider.reportNewIncomingCall(with: id, update: update(handle: handle, name: name, video: video))
    }

    func request(_ action: CallSystemAction) async throws {
        let transaction: CXTransaction
        switch action {
        case .start(let id, let handle, let name, let isVideo):
            video[id] = isVideo
            let start = CXStartCallAction(call: id, handle: CXHandle(type: .generic, value: handle.isEmpty ? id.uuidString : handle))
            start.isVideo = isVideo
            transaction = CXTransaction(action: start)
            do {
                try await controller.request(transaction)
            } catch {
                // Система не взяла звонок: звук включается без неё, иначе разговора не услышать.
                Log.warning(.calls, "CallKit не начал звонок: \(error)")
                CallAudio.configure(video: isVideo)
                CallAudio.activateDirectly()
                throw error
            }
            provider.reportCall(with: id, updated: update(handle: handle, name: name, video: isVideo))
            return
        case .answer(let id):
            transaction = CXTransaction(action: CXAnswerCallAction(call: id))
            do {
                try await controller.request(transaction)
            } catch {
                Log.warning(.calls, "CallKit не ответил на звонок: \(error)")
                CallAudio.configure(video: video[id] ?? false)
                CallAudio.activateDirectly()
                throw error
            }
            return
        case .end(let id):
            transaction = CXTransaction(action: CXEndCallAction(call: id))
        case .mute(let id, let muted):
            transaction = CXTransaction(action: CXSetMutedCallAction(call: id, muted: muted))
        }
        try await controller.request(transaction)
    }

    func reportConnecting(id: UUID) {
        provider.reportOutgoingCall(with: id, startedConnectingAt: Date())
    }

    func reportConnected(id: UUID) {
        provider.reportOutgoingCall(with: id, connectedAt: Date())
    }

    func reportEnded(id: UUID, reason: CallEndReason) {
        video[id] = nil
        provider.reportCall(with: id, endedAt: Date(), reason: Self.reason(reason))
    }

    func reportUpdate(id: UUID, name: String, video: Bool) {
        let update = CXCallUpdate()
        update.localizedCallerName = name
        update.hasVideo = video
        provider.reportCall(with: id, updated: update)
    }

    // MARK: Внутреннее

    private func update(handle: String, name: String, video: Bool) -> CXCallUpdate {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle.isEmpty ? name : handle)
        update.localizedCallerName = name
        update.hasVideo = video
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        return update
    }

    private static func reason(_ reason: CallEndReason) -> CXCallEndedReason {
        switch reason {
        case .hungUp, .remoteHungUp, .declined, .busy: .remoteEnded
        case .noAnswer, .missed: .unanswered
        case .rejected: .declinedElsewhere
        case .connectionLost, .failed: .failed
        }
    }

    fileprivate func started(_ id: UUID, video: Bool) {
        CallAudio.configure(video: video)
        provider.reportOutgoingCall(with: id, startedConnectingAt: nil)
    }

    fileprivate func answered(_ id: UUID) {
        CallAudio.configure(video: video[id] ?? false)
        delegate?.systemAnswered(id)
    }

    fileprivate func ended(_ id: UUID) {
        video[id] = nil
        delegate?.systemEnded(id)
    }

    fileprivate func muted(_ id: UUID, _ muted: Bool) {
        delegate?.systemMuted(id, muted: muted)
    }

    fileprivate func reset() {
        video = [:]
        delegate?.systemReset()
    }
}

/// Делегат CallKit. Очередь делегата — главная (`setDelegate(_:queue: nil)`). На главный актор
/// уходят только id и флаги: сами действия CallKit не `Sendable`, их `fulfill` — здесь.
extension CallKitController: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        MainActor.assumeIsolated { reset() }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        let id = action.callUUID
        let video = action.isVideo
        MainActor.assumeIsolated { started(id, video: video) }
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let id = action.callUUID
        MainActor.assumeIsolated { answered(id) }
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let id = action.callUUID
        MainActor.assumeIsolated { ended(id) }
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        let id = action.callUUID
        let isMuted = action.isMuted
        MainActor.assumeIsolated { muted(id, isMuted) }
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated { CallAudio.activated(audioSession) }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated { CallAudio.deactivated(audioSession) }
    }
}
