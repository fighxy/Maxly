import Testing
import OrbitleDomain

@Suite("Текст ошибки сервера")
struct ServerErrorTextTests {
    @Test("Непустой текст сервера заменяет нашу фразу, пустой оставляет её")
    func prefersServerText() {
        #expect(OrbitleError.server(code: "x", text: "Нет прав").userMessage == "Нет прав")
        #expect(OrbitleError.server(code: "x", text: "  Подождите  ").userMessage == "Подождите")
        #expect(OrbitleError.server(code: "x", text: "  ").userMessage == "Ошибка сервера (x). Попробуйте позже")
        #expect(OrbitleError.server(code: "x", text: nil).userMessage == "Ошибка сервера (x). Попробуйте позже")
        #expect(OrbitleError.server(code: "too.many.requests", text: nil).userMessage == "Сервер просит подождать: слишком много запросов")
        #expect(OrbitleError.server(code: "too.many.requests", text: "Подождите").userMessage == "Подождите")
        #expect(OrbitleError.server(code: "too.many.requests", text: nil).isRateLimit)
    }
}
