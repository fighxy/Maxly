import Testing
import OrbitleDomain

@Suite("Пояснение отказа входа")
struct LoginNoticeTests {
    @Test("Заголовок сервера оставляет его текст, без заголовка — только запасные строки")
    func composed() {
        let server = LoginNotice.composed(
            serverTitle: "Подождите",
            localizedMessage: "Много попыток",
            detail: "ещё",
            fallbackTitle: "Слишком много входов",
            fallbackBody: "позже"
        )
        #expect(server.title == "Подождите")
        #expect(server.message == "Много попыток")

        let detailOnly = LoginNotice.composed(
            serverTitle: "Заголовок",
            localizedMessage: "",
            detail: "описание",
            fallbackTitle: "запас",
            fallbackBody: "тело"
        )
        #expect(detailOnly.message == "описание")

        let fallback = LoginNotice.composed(
            serverTitle: nil,
            localizedMessage: "обрывок",
            detail: "ещё",
            fallbackTitle: "Слишком много входов",
            fallbackBody: "позже"
        )
        #expect(fallback.title == "Слишком много входов")
        #expect(fallback.message == "позже")
    }
}
