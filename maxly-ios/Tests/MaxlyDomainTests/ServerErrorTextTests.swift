import Testing
import MaxlyDomain

@Suite("Текст ошибки сервера")
struct ServerErrorTextTests {
    @Test("Непустой текст сервера заменяет нашу фразу, пустой оставляет её")
    func prefersServerText() {
        #expect(MaxlyError.server(code: "x", text: "Нет прав").userMessage == "Нет прав")
        #expect(MaxlyError.server(code: "x", text: "  Подождите  ").userMessage == "Подождите")
        #expect(MaxlyError.server(code: "x", text: "  ").userMessage == "Ошибка сервера (x). Попробуйте позже")
        #expect(MaxlyError.server(code: "x", text: nil).userMessage == "Ошибка сервера (x). Попробуйте позже")
        #expect(MaxlyError.server(code: "too.many.requests", text: nil).userMessage == "Сервер просит подождать: слишком много запросов")
        #expect(MaxlyError.server(code: "too.many.requests", text: "Подождите").userMessage == "Подождите")
        #expect(MaxlyError.server(code: "too.many.requests", text: nil).isRateLimit)
    }
}
