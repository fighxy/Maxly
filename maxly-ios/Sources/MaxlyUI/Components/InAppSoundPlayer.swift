#if canImport(AudioToolbox)
import AudioToolbox
import Foundation
import MaxlyPresentation

/// Короткие звуки интерфейса (`InAppSound`) из ресурсов MaxlyUI.
///
/// Играют как системные звуки: молчат при беззвучном режиме, громкость — как у звонка,
/// музыку и голосовые не прерывают. Звук загружается один раз и держится до конца работы.
@MainActor
public final class InAppSoundPlayer {
    private var loaded: [InAppSound: SystemSoundID] = [:]

    public init() {}

    public func play(_ sound: InAppSound) {
        guard let id = soundID(sound) else { return }
        AudioServicesPlaySystemSound(id)
    }

    private func soundID(_ sound: InAppSound) -> SystemSoundID? {
        if let id = loaded[sound] { return id }
        guard let url = Bundle.module.url(forResource: sound.rawValue, withExtension: "wav") else { return nil }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else { return nil }
        loaded[sound] = id
        return id
    }
}
#endif
