import Foundation
import Testing
@testable import MaxlyPresentation

@Suite("Просмотр фото и видео: правила")
struct MediaViewerRulesTests {
    @Test func chromeHidesOnlyWhilePlaying() {
        var chrome = MediaViewerChrome()
        #expect(chrome.visible)
        #expect(chrome.shouldAutoHide(playing: true, scrubbing: false, menuOpen: false))
        #expect(!chrome.shouldAutoHide(playing: false, scrubbing: false, menuOpen: false))
        #expect(!chrome.shouldAutoHide(playing: true, scrubbing: true, menuOpen: false))
        #expect(!chrome.shouldAutoHide(playing: true, scrubbing: false, menuOpen: true))
        chrome.toggle()
        #expect(!chrome.visible)
        #expect(!chrome.shouldAutoHide(playing: true, scrubbing: false, menuOpen: false))
        chrome.playbackStopped()
        #expect(chrome.visible)
    }

    @Test func doubleTapsAddUpAndClamp() {
        var taps = SeekTapAccumulator()
        #expect(SeekTapAccumulator.side(x: 10, width: 300) == false)
        #expect(SeekTapAccumulator.side(x: 290, width: 300) == true)
        #expect(SeekTapAccumulator.side(x: 150, width: 300) == nil)
        let first = taps.tap(forward: true, at: 0, position: 30, duration: 100)
        #expect(first == .init(target: 40, total: 10, forward: true))
        let second = taps.tap(forward: true, at: 0.5, position: 40, duration: 100)
        #expect(second.total == 20 && second.target == 50)
        // Пауза дольше окна — серия заново.
        let later = taps.tap(forward: true, at: 2, position: 50, duration: 100)
        #expect(later.total == 10)
        // Смена стороны — тоже заново; назад не уходит меньше нуля.
        let back = taps.tap(forward: false, at: 2.3, position: 4, duration: 100)
        #expect(back == .init(target: 0, total: 10, forward: false))
        // Вперёд не дальше конца.
        #expect(taps.tap(forward: true, at: 5, position: 95, duration: 100).target == 100)
        #expect(taps.isActive(at: 5.5) && !taps.isActive(at: 6))
    }

    @Test func dismissByDistanceOrFlick() {
        #expect(!MediaDismissRule.shouldClose(offset: 80, velocity: 100, height: 800))
        #expect(MediaDismissRule.shouldClose(offset: 130, velocity: 0, height: 800))
        #expect(MediaDismissRule.shouldClose(offset: -130, velocity: 0, height: 800))
        #expect(MediaDismissRule.shouldClose(offset: 60, velocity: 1200, height: 800))
        // Бросок против направления увода кадр возвращает.
        #expect(!MediaDismissRule.shouldClose(offset: 60, velocity: -1200, height: 800))
        #expect(MediaDismissRule.backgroundOpacity(offset: 0, height: 800) == 1)
        #expect(MediaDismissRule.backgroundOpacity(offset: 800, height: 800) == 0.2)
    }

    @Test func labels() {
        #expect(PlaybackSpeed.label(1) == "1×")
        #expect(PlaybackSpeed.label(1.5) == "1,5×")
        #expect(PlaybackSpeed.label(1.25) == "1,25×")
        #expect(MediaTimeText.clock(7) == "0:07")
        #expect(MediaTimeText.clock(765) == "12:45")
        #expect(MediaTimeText.clock(3723) == "1:02:03")
        #expect(MediaTimeText.remaining(position: 20, duration: 62) == "-0:42")
        #expect(MediaTimeText.download(fraction: 0.37) == "37 %")
        #expect(MediaTimeText.download(fraction: 0.25, totalBytes: 50 * 1_048_576) == "12,5 из 50,0 МБ")
    }
}

@Suite struct MediaHeroGeometryTests {
    @Test func fitsWideAndTallFramesIntoScreen() {
        let screen = CGRect(x: 0, y: 0, width: 400, height: 800)
        #expect(MediaHeroGeometry.fit(aspect: 2, in: screen) == CGRect(x: 0, y: 300, width: 400, height: 200))
        #expect(MediaHeroGeometry.fit(aspect: 0.25, in: screen) == CGRect(x: 100, y: 0, width: 200, height: 800))
    }

    @Test func interpolatesBetweenTileAndScreen() {
        let tile = CGRect(x: 100, y: 500, width: 100, height: 100)
        let full = CGRect(x: 0, y: 200, width: 400, height: 400)
        #expect(MediaHeroGeometry.interpolate(from: tile, to: full, progress: 0) == tile)
        #expect(MediaHeroGeometry.interpolate(from: tile, to: full, progress: 1) == full)
        #expect(MediaHeroGeometry.interpolate(from: tile, to: full, progress: 0.5) == CGRect(x: 50, y: 350, width: 250, height: 250))
    }

    @Test func returnsOnlyIntoVisibleTile() {
        let screen = CGRect(x: 0, y: 0, width: 400, height: 800)
        #expect(MediaHeroGeometry.canReturn(to: CGRect(x: 10, y: 100, width: 200, height: 200), screen: screen))
        #expect(!MediaHeroGeometry.canReturn(to: CGRect(x: 10, y: 750, width: 200, height: 200), screen: screen))
        #expect(!MediaHeroGeometry.canReturn(to: CGRect(x: 10, y: 900, width: 200, height: 200), screen: screen))
    }
}
