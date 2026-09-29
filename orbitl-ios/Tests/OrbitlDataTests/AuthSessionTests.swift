import Foundation
import Testing
import OrbitlDomain
@testable import OrbitlData

/// Ошибка вызова сервиса. `nil`, если вызов прошёл. Замыкания в Swift 6.0 не выводят
/// типизированный `throws` из контекста, поэтому здесь обычный `throws`.
func failure(_ body: () async throws -> Void) async -> OrbitlError? {
    do {
        try await body()
        return nil
    } catch let error as OrbitlError {
        return error
    } catch {
        Issue.record("не OrbitlError: \(error)")
        return .unknown
    }
}

@Suite("Ошибки входа")
struct AuthErrorsTests {
    @Test("Один и тот же вид ошибки ядра по-разному читается на разных шагах")
    func contextual() {
        let server = CoreFailure(kind: "SERVER", key: "error.wrong")
        #expect(AuthErrors.map(server, during: .requestCode) == .rejected("Не удалось отправить код. Проверьте номер телефона"))
        #expect(AuthErrors.map(server, during: .verifyCode) == .rejected("Неверный код"))
        #expect(AuthErrors.map(CoreFailure(kind: "SERVER", key: "code.expired"), during: .verifyCode) == .rejected("Код устарел. Запросите новый"))
        #expect(AuthErrors.map(CoreFailure(kind: "AUTH", key: nil), during: .password) == .rejected("Неверный пароль"))
        #expect(AuthErrors.map(server, during: .register) == .rejected("Не удалось создать аккаунт. Проверьте имя и попробуйте снова"))
        #expect(AuthErrors.map(CoreFailure(kind: "SESSION_EXPIRED", key: nil), during: .verifyCode) == .rejected("Код устарел. Запросите новый"))
        #expect(AuthErrors.map(CoreFailure(kind: "SESSION_EXPIRED", key: nil), during: .password) == .rejected("Попытка входа устарела. Начните заново"))
    }

    @Test("Лимит попыток, сеть, отмена и сбои без категории")
    func generic() {
        #expect(AuthErrors.map(CoreFailure(kind: "SERVER", key: "limit.violate"), during: .requestCode) == .rejected(AuthErrors.tooManyAttempts))
        #expect(AuthErrors.map(CoreFailure(kind: "SERVER", key: "too.many.requests"), during: .verifyCode) == .rejected(AuthErrors.tooManyAttempts))
        #expect(AuthErrors.map(CoreFailure(kind: "NETWORK", key: nil), during: .verifyCode) == .networkUnavailable)
        #expect(AuthErrors.map(CoreFailure(kind: "TIMEOUT", key: nil), during: .password) == .networkUnavailable)
        #expect(AuthErrors.map(CoreFailure(kind: "CANCELLED", key: nil), during: .password) == .cancelled)
        #expect(AuthErrors.map(CoreFailure(kind: "UNKNOWN", key: nil), during: .register) == .unknown)
        #expect(AuthErrors.map(CancellationError(), during: .requestCode) == .cancelled)
        #expect(AuthErrors.map(OrbitlError.storageError, during: .requestCode) == .storageError)
    }
}

@Suite("Сессия: вход")
struct SessionLoginTests {
    @Test("Пустой ввод отклоняется без вызова ядра")
    func emptyInput() async throws {
        try await withSession { parts in
            #expect(await failure { try await parts.session.requestCode(phone: "  ") } == .rejected("Введите номер телефона"))
            #expect(await parts.core.requestedPhones.isEmpty)
            try await parts.session.requestCode(phone: " +79990001122 ")
            #expect(await parts.core.requestedPhones == ["+79990001122"])
            #expect(await failure { try await parts.session.verifyCode(" ") } == .rejected("Введите код из SMS"))
            #expect(await parts.core.verifiedCodes.isEmpty)
            await parts.core.setAuthStep(.password(trackId: "t", hint: nil))
            try await parts.session.verifyCode("12 34")
            #expect(await parts.core.verifiedCodes == ["1234"])
            #expect(await failure { try await parts.session.submitPassword("") } == .rejected("Введите пароль"))
        }
    }

    @Test("Шаги без предыдущего шага дают invalidRequest")
    func outOfOrder() async throws {
        try await withSession { parts in
            #expect(await failure { try await parts.session.verifyCode("1234") } == .invalidRequest)
            #expect(await failure { try await parts.session.submitPassword("secret") } == .invalidRequest)
            #expect(await failure { try await parts.session.register(firstName: "Иван", lastName: "") } == .invalidRequest)
            #expect(await failure { try await parts.session.resendCode() } == .invalidRequest)
        }
    }

    @Test("Повтор кода идёт на тот же номер и снова публикует шаг кода")
    func resend() async throws {
        try await withSession { parts in
            try await parts.session.requestCode(phone: "+79990001122")
            await parts.core.setCode(CoreCode(token: "second", codeLength: 5))
            try await parts.session.resendCode()
            #expect(await parts.core.resendCount == 1)
            #expect(await parts.core.requestedPhones == ["+79990001122", "+79990001122"])
            #expect(await parts.session.currentPhase == .codeSent(codeLength: 5))
        }
    }

    @Test("Неверный код и неверный пароль приходят с русским текстом, шаг не меняется")
    func wrongInput() async throws {
        try await withSession { parts in
            try await parts.session.requestCode(phone: "+79990001122")
            await parts.core.setAuthError(CoreFailure(kind: "SERVER", key: "error.code"))
            #expect(await failure { try await parts.session.verifyCode("0000") } == .rejected("Неверный код"))
            #expect(await parts.session.currentPhase == .codeSent(codeLength: 6))

            await parts.core.setAuthError(nil)
            await parts.core.setAuthStep(.password(trackId: "t", hint: "кот"))
            try await parts.session.verifyCode("1111")
            await parts.core.setAuthError(CoreFailure(kind: "AUTH", key: nil))
            #expect(await failure { try await parts.session.submitPassword("wrong") } == .rejected("Неверный пароль"))
            #expect(await parts.session.currentPhase == .password(hint: "кот"))
        }
    }

    @Test("Регистрация обрезает пробелы и требует имя")
    func registration() async throws {
        try await withSession { parts in
            try await parts.session.requestCode(phone: "+79990001122")
            await parts.core.setAuthStep(.register(token: "reg"))
            try await parts.session.verifyCode("1234")
            #expect(await failure { try await parts.session.register(firstName: "  ", lastName: "К") } == .rejected("Введите имя"))
            await parts.core.setAuthStep(.loggedIn(userId: "9"))
            try await parts.session.register(firstName: " Иван ", lastName: " К ")
            #expect(await parts.core.registeredNames == ["Иван|К"])
            #expect(await parts.session.currentPhase == .signedIn(userId: "9"))
        }
    }

    @Test("Устаревший код сразу заменяется новым на тот же номер")
    func expiredCodeRenews() async throws {
        try await withSession { parts in
            try await parts.session.requestCode(phone: "+79990001122")
            await parts.core.setVerifyError(CoreFailure(kind: "SERVER", key: "verify.code.expired"))
            await parts.core.setCode(CoreCode(token: "fresh", codeLength: 4))
            #expect(await failure { try await parts.session.verifyCode("111111") } == .codeRenewed)
            #expect(await parts.core.requestedPhones == ["+79990001122", "+79990001122"])
            #expect(await parts.session.currentPhase == .codeSent(codeLength: 4))

            await parts.core.setVerifyError(nil)
            await parts.core.setAuthStep(.loggedIn(userId: "3"))
            try await parts.session.verifyCode("2222")
            #expect(await parts.session.currentPhase == .signedIn(userId: "3"))
        }
    }

    @Test("Если новый код не получить, остаётся текст «запросите новый»")
    func expiredCodeRenewalFails() async throws {
        try await withSession { parts in
            try await parts.session.requestCode(phone: "+79990001122")
            await parts.core.setAuthError(CoreFailure(kind: "SESSION_EXPIRED", key: nil))
            #expect(await failure { try await parts.session.verifyCode("111111") } == .rejected("Код устарел. Запросите новый"))
            #expect(await parts.session.currentPhase == .codeSent(codeLength: 6))
        }
    }

    @Test("Назад к номеру забывает попытку")
    func cancelLogin() async throws {
        try await withSession { parts in
            try await parts.session.requestCode(phone: "+79990001122")
            await parts.session.cancelLogin()
            #expect(await parts.session.currentPhase == .signedOut)
            #expect(await failure { try await parts.session.verifyCode("1234") } == .invalidRequest)
            #expect(await failure { try await parts.session.resendCode() } == .invalidRequest)
        }
    }

    @Test("Поздний ответ на код после «назад» не меняет шаг")
    func staleReply() async throws {
        try await withSession { parts in
            try await parts.session.requestCode(phone: "+79990001122")
            let gate = Gate()
            await parts.core.setVerifyGate(gate)
            await parts.core.setAuthStep(.password(trackId: "t", hint: nil))
            let session = parts.session
            let verify = Task { await failure { try await session.verifyCode("1234") } }
            #expect(await eventually { await gate.arrivals == 1 })
            await session.cancelLogin()
            await gate.open()
            #expect(await verify.value == .cancelled)
            #expect(await session.currentPhase == .signedOut)
        }
    }

    @Test("Поздний успешный вход всё равно входит: токен уже у ядра")
    func staleLoginStillEnters() async throws {
        try await withSession { parts in
            try await parts.session.requestCode(phone: "+79990001122")
            let gate = Gate()
            await parts.core.setVerifyGate(gate)
            await parts.core.setAuthStep(.loggedIn(userId: "5"))
            let session = parts.session
            let verify = Task { await failure { try await session.verifyCode("1234") } }
            #expect(await eventually { await gate.arrivals == 1 })
            await session.cancelLogin()
            await gate.open()
            #expect(await verify.value == nil)
            #expect(await session.currentPhase == .signedIn(userId: "5"))
        }
    }

    @Test("Пустой user id при входе берётся из ядра")
    func userIdFallback() async throws {
        try await withSession { parts in
            try await parts.session.requestCode(phone: "+79990001122")
            await parts.core.setAuthStep(.loggedIn(userId: ""))
            await parts.core.setUser("77")
            try await parts.session.verifyCode("1234")
            #expect(await parts.session.currentPhase == .signedIn(userId: "77"))
            #expect(await parts.messages.currentUser() == "77")
            #expect(parts.defaults.string(forKey: SessionManager.userDefaultsKey) == "77")
        }
    }

    @Test("Запрос кода после входа отклоняется")
    func codeWhileSignedIn() async throws {
        try await withSession { parts in
            await parts.core.setUser("1")
            await parts.session.restoreSession()
            #expect(await failure { try await parts.session.requestCode(phone: "+79990001122") } == .invalidRequest)
            await parts.session.cancelLogin()
            #expect(await parts.session.currentPhase == .signedIn(userId: "1"))
        }
    }
}

@Suite("Сессия: фазы ядра")
struct SessionCoreTests {
    @Test("Отказ токена во время работы открывает вход и не стирает базу")
    func tokenRejectedWhileSignedIn() async throws {
        try await withSession { parts in
            await parts.core.setUser("1")
            await parts.api.setChats([makeChat(id: "keep")])
            await parts.session.restoreSession()
            await parts.session.observe(.tokenRejected)
            #expect(await parts.session.currentPhase == .expired)
            #expect(await snapshot(parts.chats).contains(where: { $0.id == "keep" }))
            #expect(await parts.media.clearCount == 0)
        }
    }

    @Test("Старый отказ токена не сбрасывает шаг кода")
    func tokenRejectedDuringLogin() async throws {
        try await withSession { parts in
            await parts.core.setStartPhase(.awaitingAuth)
            await parts.session.restoreSession()
            try await parts.session.requestCode(phone: "+79990001122")
            await parts.session.observe(.tokenRejected)
            #expect(await parts.session.currentPhase == .codeSent(codeLength: 6))
        }
    }

    @Test("Кэш показан без id, после подключения id берётся из ядра")
    func cacheThenReady() async throws {
        try await withSession { parts in
            await parts.core.setStoredToken(true)
            await parts.core.setStartPhase(.connecting)
            await parts.session.restoreSession()
            #expect(await parts.session.currentPhase == .signedIn(userId: ""))
            await parts.core.setUser("33")
            await parts.session.observe(.ready)
            #expect(await parts.session.currentPhase == .signedIn(userId: "33"))
            #expect(await parts.messages.currentUser() == "33")
        }
    }

    @Test("Кэш под одним id, а ядро вошло другим: чужой кэш стирается")
    func cacheOfOtherAccount() async throws {
        try await withSession { parts in
            parts.defaults.set("a", forKey: SessionManager.userDefaultsKey)
            try await parts.chats.upsert([makeChat(id: "old")])
            await parts.core.setStoredToken(true)
            await parts.core.setStartPhase(.connecting)
            await parts.session.restoreSession()
            #expect(await parts.session.currentPhase == .signedIn(userId: "a"))
            await parts.core.setUser("b")
            await parts.api.setChats([makeChat(id: "new")])
            await parts.session.observe(.ready)
            #expect(await parts.session.currentPhase == .signedIn(userId: "b"))
            let chats = await snapshot(parts.chats)
            #expect(chats.map(\.id) == ["new"])
            #expect(await parts.media.clearCount == 1)
        }
    }

    @Test("Состояние соединения идёт за фазой ядра")
    func connectionStates() async throws {
        try await withSession { parts in
            var states = parts.session.connectionStates().makeAsyncIterator()
            #expect(await states.next() == .connecting)
            await parts.session.observe(.ready)
            #expect(await states.next() == .online)
            await parts.session.observe(.reconnecting)
            #expect(await states.next() == .connecting)
            await parts.session.observe(.failed)
            #expect(await states.next() == .offline)
            // Повтор того же состояния не публикуется.
            await parts.session.observe(.idle)
            await parts.session.observe(.ready)
            #expect(await states.next() == .online)
        }
    }

    @Test("Ошибка старта без токена открывает вход и показывает офлайн")
    func startErrorWithoutToken() async throws {
        try await withSession { parts in
            await parts.core.setStartError(CoreFailure(kind: "NETWORK", key: nil))
            await parts.session.restoreSession()
            #expect(await parts.session.currentPhase == .signedOut)
            var states = parts.session.connectionStates().makeAsyncIterator()
            #expect(await states.next() == .offline)
        }
    }
}

@Suite("Сессия: выход")
struct SessionLogoutTests {
    @Test("Выход стирает базу, даже если ядро не достучалось до сервера")
    func logoutOffline() async throws {
        try await withSession { parts in
            await parts.core.setUser("1")
            await parts.api.setChats([makeChat()])
            await parts.session.restoreSession()
            await parts.core.setLogoutError(CoreFailure(kind: "NETWORK", key: nil))
            await parts.session.logout()
            #expect(await parts.session.currentPhase == .signedOut)
            #expect(await snapshot(parts.chats).isEmpty)
            #expect(await parts.messages.currentUser() == "")
        }
    }

    @Test("Выход забывает открытые чаты и попытку входа")
    func logoutResets() async throws {
        try await withSession { parts in
            await parts.core.setUser("1")
            await parts.session.restoreSession()
            await parts.sync.focus("c1")
            #expect(await parts.sync.watched == ["c1"])
            await parts.session.logout()
            #expect(await parts.sync.watched.isEmpty)
            #expect(await failure { try await parts.session.verifyCode("1234") } == .invalidRequest)
        }
    }

    @Test("Вход после выхода тем же номером проходит заново")
    func loginAfterLogout() async throws {
        try await withSession { parts in
            await parts.core.setUser("1")
            await parts.session.restoreSession()
            await parts.session.logout()
            try await parts.session.requestCode(phone: "+79990001122")
            await parts.core.setAuthStep(.loggedIn(userId: "1"))
            try await parts.session.verifyCode("1234")
            #expect(await parts.session.currentPhase == .signedIn(userId: "1"))
            #expect(parts.defaults.string(forKey: SessionManager.userDefaultsKey) == "1")
        }
    }
}
