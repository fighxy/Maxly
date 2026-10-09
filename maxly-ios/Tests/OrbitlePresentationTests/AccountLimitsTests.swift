import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Ограничения аккаунта после входа")
@MainActor
struct AccountLimitsTests {
    private let calendar = ChatListFormatter.defaultCalendar(timeZone: TimeZone(secondsFromGMT: 3 * 3600)!)
    private var text: AccountLimitsText { AccountLimitsText(calendar: calendar) }
    private let hour: TimeInterval = 3600

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test("Ограничения входа действуют около суток, панель не всплывает после срока")
    func loginLasts() {
        let granted = at(4, 14, 30)
        let limits = AccountLimits(entry: .login, grantedAt: granted)
        #expect(limits.liftsAt == granted.addingTimeInterval(24 * hour))
        #expect(limits.isActive(now: granted.addingTimeInterval(23 * hour)))
        #expect(!limits.isActive(now: granted.addingTimeInterval(24 * hour)))
        #expect(limits.needsNotice(now: granted.addingTimeInterval(hour)))
        #expect(!AccountLimits(entry: .login, grantedAt: granted, isShown: true).needsNotice(now: granted))
        #expect(!limits.needsNotice(now: granted.addingTimeInterval(25 * hour)))
    }

    @Test("У регистрации срока нет: панель до показа, строки в настройках нет")
    func registration() {
        let limits = AccountLimits(entry: .registration, grantedAt: at(4, 10))
        #expect(limits.liftsAt == nil)
        #expect(!limits.isActive(now: at(4, 11)))
        #expect(limits.needsNotice(now: at(9, 11)))
        #expect(text.row(limits, now: at(4, 11)) == nil)
    }

    @Test("Способ входа берётся из шага перед входом")
    func freshEntry() {
        #expect(AuthPhase.codeSent(codeLength: 6).freshEntry == .login)
        #expect(AuthPhase.password(hint: nil).freshEntry == .login)
        #expect(AuthPhase.registration.freshEntry == .registration)
        #expect(AuthPhase.restoring.freshEntry == nil)
        #expect(AuthPhase.signedOut.freshEntry == nil)
        #expect(AuthPhase.expired.freshEntry == nil)
        #expect(AuthPhase.signedIn(userId: "1").freshEntry == nil)
    }

    @Test("Отметка сохраняется, панель закрывается раз, выход стирает отметку")
    func settings() {
        let store = InMemoryAccountLimitsStore()
        var now = at(4, 14, 30)
        let settings = AccountLimitsSettings(store: store) { now }
        #expect(settings.limits == nil)
        #expect(settings.pendingNotice(now: now) == nil)

        settings.grant(.login)
        #expect(store.saved == AccountLimits(entry: .login, grantedAt: at(4, 14, 30)))
        #expect(settings.pendingNotice(now: now) != nil)
        #expect(AccountLimitsSettings(store: store).limits == settings.limits)

        now = at(4, 15)
        settings.markShown()
        #expect(store.saved?.isShown == true)
        #expect(store.saved?.grantedAt == at(4, 14, 30))
        #expect(settings.pendingNotice(now: now) == nil)

        settings.grant(.registration)
        #expect(store.saved == AccountLimits(entry: .registration, grantedAt: at(4, 15)))

        settings.clear()
        #expect(settings.limits == nil)
        #expect(store.saved == nil)
    }

    @Test("Вход: срок в пояснении, два ограничения")
    func loginContent() {
        let limits = AccountLimits(entry: .login, grantedAt: at(4, 14, 30))
        let content = text.content(limits, now: at(4, 14, 31))
        #expect(content.title == "Аккаунт временно ограничен")
        #expect(content.message.hasSuffix("Ограничения снимутся примерно завтра в 14:30."))
        #expect(content.items.map(\.icon) == [.password, .sessions])
        #expect(text.content(limits, now: at(5, 15)).message.hasSuffix("Ограничения уже должны были сняться."))
    }

    @Test("Регистрация: сообщения, группы и остальное")
    func registrationContent() {
        let content = text.content(AccountLimits(entry: .registration, grantedAt: at(4, 10)), now: at(4, 10))
        #expect(content.title == "Аккаунт может быть ограничен")
        #expect(content.items.map(\.icon) == [.messages, .groups, .other])
    }

    @Test("Строка в настройках видна, пока ограничения входа действуют")
    func row() {
        let limits = AccountLimits(entry: .login, grantedAt: at(4, 14, 30), isShown: true)
        #expect(text.row(limits, now: at(4, 20)) == AccountLimitsRow(title: "Аккаунт временно ограничен", subtitle: "Снимутся примерно завтра в 14:30"))
        #expect(text.row(limits, now: at(5, 8))?.subtitle == "Снимутся примерно сегодня в 14:30")
        #expect(text.row(limits, now: at(5, 14, 30)) == nil)
        #expect(text.row(nil, now: at(4, 11)) == nil)
    }

    @Test("Далёкий срок — с датой")
    func moment() {
        #expect(text.moment(at(4, 9, 5), now: at(4, 1)) == "сегодня в 09:05")
        #expect(text.moment(at(6, 10), now: at(4, 1)) == "6 октября в 10:00")
    }
}
