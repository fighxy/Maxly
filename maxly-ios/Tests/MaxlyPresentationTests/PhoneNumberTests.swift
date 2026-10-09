import Testing
@testable import MaxlyPresentation

@Suite("Номер телефона")
struct PhoneNumberTests {
    @Test("Российский номер в любом привычном виде становится +7XXXXXXXXXX", arguments: [
        "+7 999 123-45-67",
        "+79991234567",
        "89991234567",
        "8 (999) 123-45-67",
        "79991234567",
        "9991234567",
        " 999 123 45 67 ",
    ])
    func russian(_ input: String) {
        #expect(PhoneNumber.normalized(input) == "+79991234567")
    }

    @Test("Неполный и неверный номер не принимается", arguments: [
        "",
        "+7",
        "+7 999 123-45-6",
        "899912345678",
        "1234567890",
        "0991234567",
        "+0 123 456 789",
        "+123",
        "+٧٩٩٩١٢٣٤٥٦٧",
    ])
    func invalid(_ input: String) {
        #expect(PhoneNumber.normalized(input) == nil)
    }

    @Test("Номер с другим кодом страны принимается как международный")
    func international() {
        #expect(PhoneNumber.normalized("+375 29 123-45-67") == "+375291234567")
        #expect(PhoneNumber.formatted("+375291234567") == "+375291234567")
    }

    @Test("Маска растёт по мере набора")
    func mask() {
        #expect(PhoneNumber.formatted("") == "")
        #expect(PhoneNumber.formatted("+") == "+")
        #expect(PhoneNumber.formatted("8") == "+7")
        #expect(PhoneNumber.formatted("7") == "+7")
        #expect(PhoneNumber.formatted("9") == "+7 9")
        #expect(PhoneNumber.formatted("+7999") == "+7 999")
        #expect(PhoneNumber.formatted("+79991") == "+7 999 1")
        #expect(PhoneNumber.formatted("+7999123") == "+7 999 123")
        #expect(PhoneNumber.formatted("+79991234") == "+7 999 123-4")
        #expect(PhoneNumber.formatted("+799912345") == "+7 999 123-45")
        #expect(PhoneNumber.formatted("+7999123456") == "+7 999 123-45-6")
        #expect(PhoneNumber.formatted("89991234567") == "+7 999 123-45-67")
        // Лишние цифры отбрасываются.
        #expect(PhoneNumber.formatted("+7 999 123-45-678") == "+7 999 123-45-67")
    }

    @Test("Стёртый разделитель стирает цифру, стёртая семёрка очищает поле")
    func edit() {
        #expect(PhoneNumber.edit(from: "+7 999 123-45-67", to: "+7 999 123-4567") == "+7 999 123-45-6")
        #expect(PhoneNumber.edit(from: "+7 999 1", to: "+7 999 ") == "+7 999")
        #expect(PhoneNumber.edit(from: "+7 9", to: "+79") == "+7")
        #expect(PhoneNumber.edit(from: "+7", to: "+") == "")
        #expect(PhoneNumber.edit(from: "", to: "+") == "+")
        #expect(PhoneNumber.edit(from: "", to: "89991234567") == "+7 999 123-45-67")
        #expect(PhoneNumber.edit(from: "+7 999 123-45-6", to: "+7 999 123-45-67") == "+7 999 123-45-67")
    }

    @Test("Номер для текста «код отправлен на…»")
    func display() {
        #expect(PhoneNumber.display("+79991234567") == "+7 999 123-45-67")
        #expect(PhoneNumber.display("+375291234567") == "+375291234567")
    }
}
