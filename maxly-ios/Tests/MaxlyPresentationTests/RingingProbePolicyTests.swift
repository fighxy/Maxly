import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Опрос звонящих")
struct RingingProbePolicyTests {
    @Test("Спрашивает один раз после запуска и после каждого возврата из фона")
    func oncePerReturn() {
        var policy = RingingProbePolicy(disabled: false)
        #expect(policy.shouldProbe(foreground: true, online: true, signedIn: true))
        #expect(!policy.shouldProbe(foreground: false, online: true, signedIn: true))
        #expect(!policy.shouldProbe(foreground: true, online: false, signedIn: true))
        #expect(!policy.shouldProbe(foreground: true, online: true, signedIn: false))

        policy.started()
        #expect(policy.finished(.nobody, droppedSoon: false) == .done)
        #expect(!policy.shouldProbe(foreground: true, online: true, signedIn: true))

        policy.wentToBackground()
        #expect(policy.shouldProbe(foreground: true, online: true, signedIn: true))
    }

    @Test("Без связи и при паузе сервера — повтор при следующем подключении")
    func retry() {
        var policy = RingingProbePolicy(disabled: false)
        for error: MaxlyError in [.networkUnavailable, .cancelled, .server(code: MaxlyError.rateLimitCode, text: nil)] {
            policy.started()
            #expect(policy.finished(.failed(error), droppedSoon: false) == .retry)
            #expect(policy.shouldProbe(foreground: true, online: true, signedIn: true))
        }
    }

    @Test("Ошибка сервера или обрыв сразу после запроса выключают опрос навсегда")
    func disable() {
        var policy = RingingProbePolicy(disabled: false)
        policy.started()
        #expect(policy.finished(.failed(.server(code: "proto.payload", text: nil)), droppedSoon: false) == .disable(reason: "server:proto.payload"))
        policy.wentToBackground()
        #expect(!policy.shouldProbe(foreground: true, online: true, signedIn: true))

        var dropped = RingingProbePolicy(disabled: false)
        dropped.started()
        #expect(dropped.finished(.failed(.networkUnavailable), droppedSoon: true) == .disable(reason: "drop"))
        #expect(dropped.isDisabled)

        #expect(!RingingProbePolicy(disabled: true).shouldProbe(foreground: true, online: true, signedIn: true))
    }
}
