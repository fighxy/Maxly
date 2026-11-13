import Foundation
import MaxlyPresentation
import MaxlyUI

/// Звуки открытого приложения (`InAppSound`): настройка, звонок и частота решаются здесь,
/// звучит `InAppSoundPlayer`.
@MainActor
final class InAppSoundCenter {
    private let player = InAppSoundPlayer()
    private var throttle = SoundThrottle()
    /// Идёт звонок: звуки сообщений молчат, чтобы не попасть в разговор.
    var inCall: @MainActor () -> Bool = { false }

    func play(_ sound: InAppSound) {
        guard InAppSoundSettings.isEnabled(sound), !inCall(),
              throttle.allows(sound, at: ProcessInfo.processInfo.systemUptime) else { return }
        player.play(sound)
    }
}
