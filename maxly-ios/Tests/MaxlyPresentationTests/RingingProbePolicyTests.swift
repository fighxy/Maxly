import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Поиск звонящих")
struct RingingProbePolicyTests {
    @Test("Ищет один раз после запуска и после каждого возврата из фона")
    func oncePerReturn() {
        var policy = RingingProbePolicy(disabled: false)
        #expect(policy.shouldCheck(foreground: true, online: true, signedIn: true))
        #expect(!policy.shouldCheck(foreground: false, online: true, signedIn: true))
        #expect(!policy.shouldCheck(foreground: true, online: false, signedIn: true))
        #expect(!policy.shouldCheck(foreground: true, online: true, signedIn: false))

        policy.started()
        #expect(policy.finished(probed: true, probeError: nil, droppedSoon: false) == .done)
        #expect(!policy.shouldCheck(foreground: true, online: true, signedIn: true))

        policy.wentToBackground()
        #expect(policy.shouldCheck(foreground: true, online: true, signedIn: true))
    }

    @Test("Без связи и при паузе сервера — повтор при следующем подключении")
    func retry() {
        var policy = RingingProbePolicy(disabled: false)
        for error: MaxlyError in [.networkUnavailable, .cancelled, .server(code: MaxlyError.rateLimitCode, text: nil)] {
            policy.started()
            #expect(policy.finished(probed: true, probeError: error, droppedSoon: false) == .retry)
            #expect(policy.shouldCheck(foreground: true, online: true, signedIn: true))
        }
    }

    @Test("Ошибка сервера или обрыв после 103 выключают только опрос 103, звонки входа смотрятся дальше")
    func disable() {
        var policy = RingingProbePolicy(disabled: false)
        policy.started()
        #expect(policy.finished(probed: true, probeError: .server(code: "proto.payload", text: nil), droppedSoon: false) == .disable(reason: "server:proto.payload"))
        #expect(!policy.sendsProbe)
        policy.wentToBackground()
        #expect(policy.shouldCheck(foreground: true, online: true, signedIn: true))

        var dropped = RingingProbePolicy(disabled: false)
        dropped.started()
        #expect(dropped.finished(probed: true, probeError: nil, droppedSoon: true) == .disable(reason: "drop"))
        #expect(dropped.isDisabled)

        // Без 103 обрыв к поиску не относится.
        var off = RingingProbePolicy(disabled: true)
        off.started()
        #expect(off.finished(probed: false, probeError: nil, droppedSoon: true) == .done)
        #expect(!off.sendsProbe)
    }
}
