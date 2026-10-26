import Foundation
import Testing
@testable import MaxlyPresentation

/// Живая лента у низа; тест меняет нужное.
private func input(
    _ change: CollectionChange,
    _ edit: (inout FeedMotionPlan.Input) -> Void = { _ in }
) -> FeedMotionPlan.Input {
    var value = FeedMotionPlan.Input(
        live: true,
        settled: true,
        interacting: false,
        commanded: false,
        change: change,
        followsBottom: true,
        atBottom: true,
        nearBottom: true,
        removedVisible: true,
        resizedVisible: true
    )
    edit(&value)
    return value
}

@Suite("Движение ленты на UICollectionView")
struct FeedMotionPlanTests {
    @Test("Открытие, история и догонка — сразу")
    func instantWhenNotLive() {
        #expect(FeedMotionPlan.motion(input(.appended(1)) { $0.live = false }) == .instant)
        #expect(FeedMotionPlan.motion(input(.appended(1)) { $0.settled = false }) == .instant)
        #expect(FeedMotionPlan.motion(input(.initial)) == .instant)
        #expect(FeedMotionPlan.motion(input(.prepended(30))) == .instant)
        #expect(FeedMotionPlan.motion(input(.trimmed(5))) == .instant)
        #expect(FeedMotionPlan.motion(input(.reload)) == .instant)
        #expect(FeedMotionPlan.motion(input(.updated(2))) == .instant)
    }

    @Test("Новое у низа въезжает; далеко в истории — сразу")
    func appear() {
        #expect(FeedMotionPlan.motion(input(.appended(1))) == .appear)
        // Отправил, читая недалеко от низа: лента прилипает к низу и едет к своему сообщению.
        #expect(FeedMotionPlan.motion(input(.appended(1)) { $0.atBottom = false }) == .appear)
        #expect(FeedMotionPlan.motion(input(.appended(1)) { $0.atBottom = false; $0.nearBottom = false }) == .instant)
        #expect(FeedMotionPlan.motion(input(.appended(1)) { $0.followsBottom = false }) == .instant)
    }

    @Test("Удалённое на экране сжимается; вне экрана — сразу")
    func disappear() {
        #expect(FeedMotionPlan.motion(input(.removed(1))) == .disappear)
        // Не у низа: строки ниже удалённой подтягиваются, место чтения то же.
        #expect(FeedMotionPlan.motion(input(.removed(2)) { $0.atBottom = false }) == .disappear)
        #expect(FeedMotionPlan.motion(input(.removed(1)) { $0.removedVisible = false }) == .instant)
    }

    @Test("Больше десяти изменений за раз — сразу")
    func limit() {
        #expect(FeedMotionPlan.motion(input(.appended(CollectionChange.animationLimit))) == .appear)
        #expect(FeedMotionPlan.motion(input(.appended(CollectionChange.animationLimit + 1))) == .instant)
        #expect(FeedMotionPlan.motion(input(.removed(CollectionChange.animationLimit + 1))) == .instant)
    }

    @Test("Палец на ленте и команда прокрутки — сразу")
    func interactionAndCommands() {
        #expect(FeedMotionPlan.motion(input(.appended(1)) { $0.interacting = true }) == .instant)
        #expect(FeedMotionPlan.motion(input(.removed(1)) { $0.interacting = true }) == .instant)
        #expect(FeedMotionPlan.motion(input(.appended(1)) { $0.commanded = true }) == .instant)
    }

    @Test("Рост пузыря на экране у низа плавный, при чтении истории — сразу")
    func resize() {
        #expect(FeedMotionPlan.motion(input(.none)) == .resize)
        #expect(FeedMotionPlan.motion(input(.none) { $0.atBottom = false }) == .instant)
        #expect(FeedMotionPlan.motion(input(.none) { $0.resizedVisible = false }) == .instant)
    }
}
