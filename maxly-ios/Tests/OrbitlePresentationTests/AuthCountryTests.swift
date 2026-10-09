import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Вход: страна и маска номера")
@MainActor
struct AuthCountryTests {
    @Test("По умолчанию Россия, номер форматируется по маске страны")
    func defaultRussia() {
        let (model, _, _) = makeAuth()
        #expect(model.country == .russia)
        #expect(model.countryCode == "7")
        #expect(model.countryTitle == "Россия")
        #expect(model.phonePlaceholder == "000 000 0000")
        model.nationalNumber = "999123"
        #expect(model.nationalNumber == "999 123")
        #expect(!model.canRequestCode)
        model.nationalNumber = "99912345678"
        #expect(model.nationalNumber == "999 123 4567")
        #expect(model.normalizedPhone == "+79991234567")
        #expect(model.canRequestCode)
    }

    @Test("Стёртый разделитель убирает цифру перед ним")
    func deleteSeparator() {
        let (model, _, _) = makeAuth()
        model.nationalNumber = "999 123"
        model.nationalNumber = "999123"
        #expect(model.nationalNumber == "999 12")
    }

    @Test("Код страны меняет страну и маску")
    func editCode() {
        let (model, _, _) = makeAuth()
        model.countryCode = "375"
        #expect(model.country?.id == "BY")
        #expect(model.isCountryCodeComplete)
        #expect(model.phonePlaceholder == "00 000 0000")
        model.nationalNumber = "291234567"
        #expect(model.nationalNumber == "29 123 4567")
        #expect(model.normalizedPhone == "+375291234567")
        model.countryCode = "41"
        #expect(model.country == nil)
        #expect(model.countryTitle == "Другая страна")
        #expect(model.normalizedPhone == "+41291234567")
        model.countryCode = "0"
        #expect(model.normalizedPhone == nil)
        model.countryCode = ""
        #expect(model.countryTitle == "Выберите страну")
    }

    @Test("Выбор страны из списка сохраняет её для общего кода")
    func selectCountry() {
        let (model, _, _) = makeAuth()
        let kazakhstan = PhoneCountry.all.first { $0.id == "KZ" }!
        model.selectCountry(kazakhstan)
        #expect(model.country?.id == "KZ")
        #expect(model.countryCode == "7")
        model.nationalNumber = "7011234567"
        #expect(model.country?.id == "KZ")
        // Лишняя цифра после полного номера не сдвигает его, как `8 …` или `7 …` целиком.
        model.nationalNumber = "701 123 45679"
        #expect(model.nationalNumber == "701 123 4567")
        model.nationalNumber = ""
        model.nationalNumber = "87011234567"
        #expect(model.nationalNumber == "701 123 4567")
    }

    @Test("Вставленный целиком номер разбирается на код и номер")
    func pasteFullNumber() {
        let (model, _, _) = makeAuth()
        model.countryCode = "+375 29 123 45 67"
        #expect(model.countryCode == "375")
        #expect(model.nationalNumber == "29 123 4567")
    }

    @Test("Автозаполнение номера целиком в поле номера")
    func autofillNumber() {
        let (model, _, _) = makeAuth()
        model.nationalNumber = "+7 999 123-45-67"
        #expect(model.countryCode == "7")
        #expect(model.nationalNumber == "999 123 4567")
        model.nationalNumber = "89991234567"
        #expect(model.nationalNumber == "999 123 4567")
        model.nationalNumber = "+375291234567"
        #expect(model.country?.id == "BY")
        #expect(model.nationalNumber == "29 123 4567")
    }

    @Test("Системная кнопка «назад» сразу возвращает к номеру")
    func backToPhone() async {
        let (model, service, _) = makeAuth()
        await reachCode(model)
        model.backToPhone()
        #expect(model.step == .phone)
        #expect(model.sentTo == nil)
        _ = await eventually { await service.calls.contains("cancel") }
    }

    @Test("Поиск стран по названию и коду")
    func search() {
        #expect(PhoneCountry.search("казах").map(\.id) == ["KZ"])
        #expect(PhoneCountry.search("+375").map(\.id) == ["BY"])
        #expect(PhoneCountry.search("").count == PhoneCountry.all.count)
        #expect(PhoneCountry.russia.flag == "🇷🇺")
    }

    @Test("Шаг кода знает число ячеек и номер для экрана")
    func codeStep() async {
        let (model, _, _) = makeAuth()
        #expect(model.codeCellCount == 6)
        await reachCode(model)
        #expect(model.codeCellCount == 6)
        #expect(model.sentToDisplay == "+7 999 123-45-67")
    }

    @Test("Фото регистрации забывается при возврате к номеру")
    func photoReset() async {
        let (model, _, _) = makeAuth()
        await reachCode(model)
        model.registrationPhoto = Data([1, 2, 3])
        await model.goBack()
        #expect(model.registrationPhoto == nil)
    }
}
