import Foundation
import Testing
import OrbitlDomain
@testable import OrbitlPresentation

@MainActor
func makeAuth() -> (AuthViewModel, FakeAuthService, TestClock) {
    let service = FakeAuthService()
    let clock = TestClock()
    let model = AuthViewModel(auth: service, resendInterval: 60, now: { clock.now })
    model.activate()
    return (model, service, clock)
}

/// Проводит экран до шага кода.
@MainActor
func reachCode(_ model: AuthViewModel) async {
    model.phone = "89991234567"
    await model.requestCode()
    _ = await eventually { model.step == .code(length: 6) }
}

@Suite("Вход: номер")
@MainActor
struct AuthPhoneTests {
    @Test("Поле номера держит маску, кнопка доступна только для полного номера")
    func phoneMask() {
        let (model, _, _) = makeAuth()
        #expect(model.step == .phone)
        #expect(!model.canRequestCode)
        model.phone = "8999123"
        #expect(model.phone == "+7 999 123")
        #expect(!model.canRequestCode)
        model.phone = "89991234567"
        #expect(model.phone == "+7 999 123-45-67")
        #expect(model.normalizedPhone == "+79991234567")
        #expect(model.canRequestCode)
        #expect(model.phoneHint == nil)
    }

    @Test("Неверный номер получает подсказку и не уходит в сервис")
    func invalidPhone() async {
        let (model, service, _) = makeAuth()
        model.phone = "+7 199 123-45-67"
        #expect(model.phoneHint == "Проверьте номер: например, +7 900 000-00-00")
        await model.requestCode()
        #expect(model.errorMessage == "Введите номер в формате +7 900 000-00-00")
        #expect(await service.calls.isEmpty)
        model.phone = "+7 999 123-45-67"
        #expect(model.error == nil)
    }

    @Test("Код уходит на нормализованный номер, шаг и таймер повтора включаются")
    func requestCode() async {
        let (model, service, clock) = makeAuth()
        await reachCode(model)
        #expect(await service.calls == ["code +79991234567"])
        #expect(model.step == .code(length: 6))
        #expect(model.sentTo == "+79991234567")
        #expect(model.codePrompt == "Мы отправили код из 6 цифр на +7 999 123-45-67")
        #expect(model.title == "Код из SMS")
        #expect(model.resendSecondsLeft(at: clock.now) == 60)
        #expect(!model.canResend(at: clock.now))
        #expect(model.resendTitle(at: clock.now) == "Отправить ещё раз через 1:00")
        #expect(!model.isBusy)
    }

    @Test("Ошибка сети показывается по-русски, шаг не меняется")
    func networkError() async {
        let (model, service, _) = makeAuth()
        await service.set(requestError: .networkUnavailable)
        model.phone = "9991234567"
        await model.requestCode()
        #expect(model.step == .phone)
        #expect(model.errorMessage == "Нет соединения с сервером")
        #expect(!model.isBusy)
        #expect(model.canRequestCode)
    }

    @Test("Истёкшая сессия объясняется до нового кода")
    func expired() async {
        let (model, service, _) = makeAuth()
        service.publish(.expired)
        #expect(await eventually { model.sessionExpired })
        #expect(model.step == .phone)
        await reachCode(model)
        #expect(!model.sessionExpired)
    }
}

@Suite("Вход: код")
@MainActor
struct AuthCodeTests {
    @Test("Таймер повтора считает секунды, повтор до срока не уходит")
    func resendCountdown() async {
        let (model, service, clock) = makeAuth()
        await reachCode(model)
        clock.advance(30)
        #expect(model.resendSecondsLeft(at: clock.now) == 30)
        #expect(model.resendTitle(at: clock.now) == "Отправить ещё раз через 0:30")
        await model.resendCode()
        #expect(await service.calls == ["code +79991234567"])

        clock.advance(29.5)
        #expect(model.resendSecondsLeft(at: clock.now) == 1)
        clock.advance(0.5)
        #expect(model.canResend(at: clock.now))
        #expect(model.resendTitle(at: clock.now) == "Отправить код ещё раз")
        await model.resendCode()
        #expect(await service.calls == ["code +79991234567", "resend"])
        // После повтора таймер начинается заново.
        #expect(model.resendSecondsLeft(at: clock.now) == 60)
    }

    @Test("Код принимает только цифры и не длиннее ожидаемого, полный код уходит сам")
    func autoSubmit() async {
        let (model, service, _) = makeAuth()
        await reachCode(model)
        model.code = "12a3 4"
        #expect(model.code == "1234")
        #expect(!model.canVerify)
        model.code = "12345678"
        #expect(model.code == "123456")
        #expect(await eventually { await service.calls.contains("verify 123456") })
    }

    @Test("Без длины от сервера код отправляется кнопкой")
    func unknownLength() async {
        let (model, service, _) = makeAuth()
        await service.set(codeLength: nil)
        model.phone = "89991234567"
        await model.requestCode()
        #expect(await eventually { model.step == .code(length: nil) })
        #expect(model.codePrompt == "Мы отправили код на +7 999 123-45-67")
        model.code = "123"
        #expect(!model.canVerify)
        model.code = "12345"
        #expect(model.canVerify)
        await model.verify()
        #expect(await service.calls.last == "verify 12345")
    }

    @Test("Неверный код показывает ошибку и стирает поле")
    func wrongCode() async {
        let (model, service, _) = makeAuth()
        await reachCode(model)
        await service.set(verifyError: .rejected("Неверный код"))
        model.code = "000000"
        #expect(await eventually { model.errorMessage == "Неверный код" })
        #expect(model.code == "")
        #expect(model.step == .code(length: 6))
        model.code = "1"
        #expect(model.error == nil)
    }

    @Test("Пока идёт проверка, экран занят и повтор недоступен")
    func busy() async {
        let (model, service, clock) = makeAuth()
        await reachCode(model)
        let gate = Gate()
        await service.set(gate: gate)
        await service.set(afterVerify: .password(hint: nil))
        model.code = "123456"
        #expect(await eventually { await gate.arrivals == 1 })
        #expect(model.isBusy)
        #expect(!model.canVerify)
        clock.advance(120)
        #expect(!model.canResend(at: clock.now))
        await gate.open()
        #expect(await eventually { model.step == .password(hint: nil) })
        #expect(!model.isBusy)
    }

    @Test("Назад во время проверки сразу возвращает к номеру, поздний ответ не показывается")
    func backDuringVerify() async {
        let (model, service, _) = makeAuth()
        await reachCode(model)
        let gate = Gate()
        await service.set(gate: gate)
        await service.set(afterVerify: .password(hint: nil))
        model.code = "123456"
        let submit = model.pendingAutoSubmit
        #expect(submit != nil)
        #expect(await eventually { await gate.arrivals == 1 })
        await model.goBack()
        #expect(model.step == .phone)
        #expect(!model.isBusy)
        #expect(model.code == "")
        #expect(model.phone == "+7 999 123-45-67")
        #expect(await service.calls.contains("cancel"))
        await gate.open()
        await submit?.value
        #expect(model.step == .phone)
        #expect(model.error == nil)
    }

    @Test("Устаревший код: сервис выслал новый, таймер и поле начинаются заново")
    func codeRenewed() async {
        let (model, service, clock) = makeAuth()
        await reachCode(model)
        clock.advance(45)
        await service.set(verifyError: .codeRenewed)
        model.code = "123456"
        #expect(await eventually { model.errorMessage == "Код устарел — выслали новый" })
        #expect(model.code == "")
        #expect(model.resendSecondsLeft(at: clock.now) == 60)
    }

    @Test("По умолчанию повтор кода через 30 секунд, как в официальном клиенте")
    func defaultInterval() {
        #expect(AuthViewModel.defaultResendInterval == 30)
    }

    @Test("Отмена не показывается как ошибка")
    func cancelledHidden() async {
        let (model, service, _) = makeAuth()
        await reachCode(model)
        await service.set(verifyError: .cancelled)
        model.code = "123456"
        await model.pendingAutoSubmit?.value
        #expect(await service.calls.contains("verify 123456"))
        #expect(model.error == nil)
        #expect(model.errorMessage == nil)
    }
}

@Suite("Вход: пароль и регистрация")
@MainActor
struct AuthPasswordTests {
    @Test("Пароль: подсказка, пустой пароль, неверный пароль")
    func password() async {
        let (model, service, _) = makeAuth()
        await reachCode(model)
        await service.set(afterVerify: .password(hint: "кот"))
        model.code = "123456"
        #expect(await eventually { model.step == .password(hint: "кот") })
        #expect(model.passwordPrompt == "Аккаунт защищён облачным паролем. Подсказка: кот")
        #expect(model.title == "Пароль")
        #expect(!model.canSubmitPassword)
        await service.set(passwordError: .rejected("Неверный пароль"))
        model.password = "secret"
        #expect(model.canSubmitPassword)
        await model.submitPassword()
        #expect(model.errorMessage == "Неверный пароль")
        #expect(model.password == "")
        #expect(await service.calls.last == "password secret")
    }

    @Test("Регистрация требует имя и обрезает пробелы")
    func registration() async {
        let (model, service, _) = makeAuth()
        await reachCode(model)
        await service.set(afterVerify: .registration)
        model.code = "123456"
        // Полный код уходит сам: ждём, пока автоотправка закончится, иначе шаг ещё занят.
        await model.pendingAutoSubmit?.value
        #expect(await eventually { model.step == .registration && !model.isBusy })
        #expect(model.title == "Новый аккаунт")
        #expect(!model.canRegister)
        model.firstName = "   "
        #expect(!model.canRegister)
        await model.register()
        #expect(model.errorMessage == "Введите имя")
        model.firstName = " Иван "
        model.lastName = " К "
        #expect(model.canRegister)
        await model.register()
        #expect(await service.calls.last == "register Иван|К")
    }

    @Test("Слишком длинное имя не уходит на сервер")
    func longName() async {
        let (model, service, _) = makeAuth()
        await reachCode(model)
        await service.set(afterVerify: .registration)
        model.code = "123456"
        // Полный код уходит сам: ждём, пока автоотправка закончится, иначе шаг ещё занят.
        await model.pendingAutoSubmit?.value
        #expect(await eventually { model.step == .registration && !model.isBusy })
        model.firstName = String(repeating: "а", count: 61)
        #expect(!model.canRegister)
        await model.register()
        #expect(model.errorMessage == "Имя и фамилия не длиннее 60 символов")
        #expect(await service.calls.contains { $0.hasPrefix("register") } == false)
    }

    @Test("С пароля и регистрации «назад» ведёт к номеру")
    func backFromPassword() async {
        let (model, service, _) = makeAuth()
        await reachCode(model)
        await service.set(afterVerify: .password(hint: nil))
        model.code = "123456"
        await model.pendingAutoSubmit?.value
        #expect(await eventually { model.step == .password(hint: nil) && !model.isBusy })
        model.password = "p"
        #expect(model.canGoBack)
        await model.goBack()
        #expect(model.step == .phone)
        #expect(model.password == "")
        #expect(!model.canGoBack)
        #expect(model.resendAvailableAt == nil)
    }

    @Test("Вход стирает введённые секреты")
    func signedInClears() async {
        let (model, service, _) = makeAuth()
        await reachCode(model)
        await service.set(afterVerify: .password(hint: nil))
        model.code = "123456"
        await model.pendingAutoSubmit?.value
        #expect(await eventually { model.step == .password(hint: nil) && !model.isBusy })
        model.password = "secret"
        await model.submitPassword()
        #expect(await eventually { model.password.isEmpty })
        #expect(model.error == nil)
    }
}
