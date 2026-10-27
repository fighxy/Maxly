import Testing
@testable import MaxlyPresentation

@Suite("Положение ленты чата")
struct TranscriptPositionTests {
    private typealias Feed = TranscriptPosition.Feed

    private func opened(_ feed: Feed = Feed(lastRowId: "9")) throws -> TranscriptPosition {
        var position = TranscriptPosition()
        _ = position.open(feed)
        let request = try #require(position.request)
        position.scrollFinished(request.token, confirmed: true)
        return position
    }

    private func change(_ position: inout TranscriptPosition, _ change: CollectionChange, fromPaging: Bool = false,
                        place: TranscriptPosition.Place? = nil, feed: Feed = Feed(lastRowId: "10"),
                        outgoing: Bool = false) -> TranscriptPosition.Opening {
        position.feedChanged(change, fromPaging: fromPaging, place: place, feed: feed) { _ in outgoing }
    }

    @Test("Открытие на первом непрочитанном: в верхней части экрана, низ не держится")
    func opensAtUnread() throws {
        var position = TranscriptPosition()
        let feed = Feed(lastRowId: "9", unreadAnchorId: "5", restoredPlace: "3")
        #expect(position.reveal(feed) == .init(id: "5", anchor: TranscriptPosition.unreadAnchor, latest: false))
        let opening = position.open(feed)
        #expect(opening == .unread("5"))
        let request = try #require(position.request)
        #expect(request.id == "5" && !request.latest)
        #expect(!position.bottom.followsLatest)
        #expect(!position.stickToBottom(isJumped: false))
        #expect(!position.isSettled)
        let finished = position.scrollFinished(request.token, confirmed: true)
        #expect(finished)
        #expect(position.isSettled)
    }

    @Test("Открытие на сохранённом месте, иначе внизу")
    func opensAtRestoredPlaceOrBottom() throws {
        var restored = TranscriptPosition()
        let opening = restored.open(Feed(lastRowId: "9", restoredPlace: "3"))
        #expect(opening == .restored("3"))
        #expect(restored.request?.anchor == 0)

        var latest = TranscriptPosition()
        let opening2 = latest.open(Feed(lastRowId: "9"))
        #expect(opening2 == .latest)
        #expect(latest.request?.latest == true)
        #expect(latest.bottom.followsLatest)
        #expect(!latest.stickToBottom(isJumped: false))
        let request = try #require(latest.request)
        latest.scrollFinished(request.token, confirmed: true)
        #expect(latest.stickToBottom(isJumped: false))
        #expect(!latest.stickToBottom(isJumped: true))
    }

    @Test("Цель открытия выбирается один раз: поздний ответ сервера её не заменяет")
    func openingTargetChosenOnce() {
        var position = TranscriptPosition()
        let opening = position.open(Feed(lastRowId: nil))
        #expect(opening == .none)
        let opening2 = position.open(Feed(lastRowId: "9", hasPendingOpen: true))
        #expect(opening2 == .waitForWindow)
        #expect(position.reveal(Feed(lastRowId: "9", hasPendingOpen: true)) == nil)
        let opening3 = position.open(Feed(lastRowId: "9", restoredPlace: "3"))
        #expect(opening3 == .restored("3"))
        let opening4 = position.open(Feed(lastRowId: "9", unreadAnchorId: "5"))
        #expect(opening4 == .none)
        #expect(position.request?.id == "3")
    }

    @Test("Пока лента открывается, изменение ленты — ещё одна попытка открыть")
    func changeWhileOpeningOpens() {
        var position = TranscriptPosition()
        let opening = change(&position, .initial, feed: Feed(lastRowId: nil))
        #expect(opening == .none)
        let opening2 = change(&position, .initial, feed: Feed(lastRowId: "10", unreadAnchorId: "7"))
        #expect(opening2 == .unread("7"))
    }

    @Test("Новое сообщение у низа ведёт вниз, в истории — нет")
    func newMessageFollowsOnlyAtBottom() throws {
        var atBottom = try opened()
        _ = change(&atBottom, .appended(1))
        #expect(atBottom.request?.id == "10" && atBottom.request?.latest == true)

        var reading = try opened(Feed(lastRowId: "9", unreadAnchorId: "5"))
        _ = change(&reading, .appended(1))
        #expect(reading.request == nil)
    }

    @Test("Своё сообщение из истории ведёт вниз, но не из окна перехода")
    func ownMessageFromHistory() throws {
        var reading = try opened(Feed(lastRowId: "9", unreadAnchorId: "5"))
        _ = change(&reading, .appended(1), outgoing: true)
        #expect(reading.request?.latest == true)

        var jumped = try opened(Feed(lastRowId: "9", unreadAnchorId: "5"))
        _ = change(&jumped, .appended(1), feed: Feed(lastRowId: "10", isJumped: true), outgoing: true)
        #expect(jumped.request == nil)
    }

    @Test("Страница сверху: снимок коллекции держит место сам, страница перехода — командой")
    func pagingKeepsPlace() throws {
        var prepended = try opened(Feed(lastRowId: "9", unreadAnchorId: "5"))
        _ = change(&prepended, .prepended(30), fromPaging: true, place: .init(id: "5", anchor: 0.3))
        #expect(prepended.request == nil)

        var paged = try opened(Feed(lastRowId: "9", unreadAnchorId: "5"))
        _ = change(&paged, .appended(30), fromPaging: true, place: .init(id: "5", anchor: 0.3))
        #expect(paged.request?.id == "5" && paged.request?.anchor == 0.3)

        var following = try opened()
        _ = change(&following, .appended(30), fromPaging: true, place: .init(id: "5", anchor: 0.3))
        #expect(following.request?.latest == true)

        var gone = try opened(Feed(lastRowId: "9", unreadAnchorId: "5"))
        _ = change(&gone, .appended(30), fromPaging: true, place: nil)
        #expect(gone.request == nil)
    }

    @Test("Палец отменяет команду и открытие")
    func fingerCancelsCommand() throws {
        var position = TranscriptPosition()
        _ = position.open(Feed(lastRowId: "9"))
        let pending = try #require(position.request)
        position.userScroll(moving: true, takeover: true)
        #expect(position.request == nil)
        #expect(!position.isOpening && position.openingTargetChosen)
        #expect(!position.bottom.followsLatest)
        let finished = position.scrollFinished(pending.token, confirmed: true)
        #expect(!finished)
        let opening = position.open(Feed(lastRowId: "9", unreadAnchorId: "5"))
        #expect(opening == .none)
    }

    @Test("«Вниз» и переход к сообщению — команды, новая заменяет прежнюю")
    func commands() throws {
        var position = try opened(Feed(lastRowId: "9", unreadAnchorId: "5"))
        position.perform(.message("2", highlight: true), lastRowId: "9")
        let jump = try #require(position.request)
        #expect(jump.id == "2" && jump.anchor == 0.5)
        position.goDown(lastRowId: "9")
        let down = try #require(position.request)
        #expect(down.latest && down.token != jump.token)
        let finished = position.scrollFinished(jump.token, confirmed: true)
        #expect(!finished)
        #expect(position.reveal(Feed(lastRowId: "9")) == .init(id: "9", anchor: 1, latest: true))
        position.perform(.bottom, lastRowId: nil)
        #expect(position.request == down)
    }

    @Test("Невыполненная команда не включает слежение за низом")
    func unconfirmedCommandReadsHistory() throws {
        var position = TranscriptPosition()
        _ = position.open(Feed(lastRowId: "9"))
        let request = try #require(position.request)
        position.scrollFinished(request.token, confirmed: false)
        #expect(!position.bottom.followsLatest && !position.isOpening)
    }

    @Test("Во время инерции клавиатура и рост строк не тянут ленту вниз")
    func momentumKeepsFinger() throws {
        var position = try opened()
        position.userScroll(moving: true, takeover: false)
        #expect(!position.stickToBottom(isJumped: false))
        position.chromeMoved(lastRowId: "9")
        position.viewportResized(lastRowId: "9")
        position.rowsResized(lastRowId: "9")
        #expect(position.request == nil)
        position.userScroll(moving: false, takeover: false)
        position.chromeMoved(lastRowId: "9")
        #expect(position.request?.latest == true)
    }

    @Test("Высота ленты держит низ и поверх команды, поле ввода — нет")
    func resizeOverridesCommand() throws {
        var position = try opened()
        position.goDown(lastRowId: "9")
        let pending = try #require(position.request)
        position.chromeMoved(lastRowId: "9")
        #expect(position.request == pending)
        position.viewportResized(lastRowId: "9")
        #expect(position.request != pending)
    }

    @Test("Рост строк у самого низа ничего не делает, ниже низа — ведёт к нему")
    func rowsResize() throws {
        var position = try opened()
        position.measuredLastRow(minY: 200, maxY: 760, viewportMin: 101, viewportMax: 766, contentFits: false, buttonMin: nil)
        position.rowsResized(lastRowId: "9")
        #expect(position.request == nil)
        position.measuredLastRow(minY: 200, maxY: 1200, viewportMin: 101, viewportMax: 766, contentFits: false, buttonMin: nil)
        position.rowsResized(lastRowId: "9")
        #expect(position.request?.latest == true)
    }

    @Test("Короткий чат стоит у низа без зазора")
    func shortChat() throws {
        var position = try opened()
        position.measuredLastRow(minY: 140, maxY: 200, viewportMin: 101, viewportMax: 766, contentFits: true, buttonMin: nil)
        #expect(position.bottom.atBottom)
        #expect(!position.bottom.showsButton(hasMessages: true))
    }

    @Test("Уход с экрана: при следующем показе лента открывается заново")
    func disappearResets() throws {
        var position = try opened()
        position.goDown(lastRowId: "9")
        position.disappeared()
        #expect(position.request == nil && position.isOpening && !position.openingTargetChosen)
        let opening = position.open(Feed(lastRowId: "9", restoredPlace: "4"))
        #expect(opening == .restored("4"))
    }
}
