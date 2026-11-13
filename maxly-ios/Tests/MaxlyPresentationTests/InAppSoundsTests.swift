import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Звуки в приложении")
struct InAppSoundsTests {
    private func notice(muted: Bool = false) -> IncomingMessageNotice {
        IncomingMessageNotice(
            chatId: "1", messageId: "2", chatTitle: "Чат", chatType: .private,
            authorName: "Оля", text: "Привет", media: nil, isMuted: muted
        )
    }

    @Test func incomingOnlyWhileOpenAndNotMuted() {
        #expect(InAppSoundRules.playsIncoming(notice(), appActive: true))
        // В фоне звучит уведомление, а не звук приложения.
        #expect(!InAppSoundRules.playsIncoming(notice(), appActive: false))
        #expect(!InAppSoundRules.playsIncoming(notice(muted: true), appActive: true))
    }

    @Test func settingsDefaultOnAndSeparate() throws {
        let defaults = try #require(UserDefaults(suiteName: "InAppSoundsTests-\(UUID().uuidString)"))
        #expect(InAppSoundSettings.isEnabled(.sent, defaults: defaults))
        #expect(InAppSoundSettings.isEnabled(.incoming, defaults: defaults))
        defaults.set(false, forKey: InAppSoundSettings.sentKey)
        #expect(!InAppSoundSettings.isEnabled(.sent, defaults: defaults))
        #expect(InAppSoundSettings.isEnabled(.incoming, defaults: defaults))
    }

    @Test func burstPlaysOnce() {
        var throttle = SoundThrottle()
        #expect(throttle.allows(.incoming, at: 10))
        #expect(!throttle.allows(.incoming, at: 10.3))
        // Другой звук не ждёт.
        #expect(throttle.allows(.sent, at: 10.3))
        #expect(throttle.allows(.incoming, at: 10 + SoundThrottle.interval))
    }
}
