import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

private struct FakeProfiles: ChatProfileRepository {
    var result: Result<ChatProfile, OrbitleError>

    func profile(chatId: String) async throws(OrbitleError) -> ChatProfile {
        try result.get()
    }
}

@Suite("Профиль чата")
@MainActor
struct ChatProfileViewModelTests {
    private func makeModel(_ profile: ChatProfile, title: String = "Из списка") -> ChatProfileViewModel {
        ChatProfileViewModel(chatId: profile.chatId, title: title, repository: FakeProfiles(result: .success(profile)))
    }

    @Test("Пока карточка грузится, шапка показывает имя из списка")
    func placeholder() {
        let model = makeModel(ChatProfile(kind: .user, chatId: "1", title: "Анна"), title: "Анна из списка")
        #expect(model.state == .loading)
        #expect(model.title == "Анна из списка")
        #expect(model.infoRows.isEmpty)
    }

    @Test("Пользователь: статус, телефон, о себе, имя пользователя")
    func user() async {
        let profile = ChatProfile(
            kind: .user, chatId: "13", peerId: "3", title: "Анна Ли",
            description: "Дизайнер", link: "anna", phone: "+79991234567", presence: .online
        )
        let model = makeModel(profile)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.title == "Анна Ли")
        #expect(model.isOnline)
        #expect(model.infoRows.map(\.id) == ["phone", "description", "link"])
        #expect(model.infoRows[0].value == "+7 999 123-45-67")
        #expect(model.infoRows[0].action == .call(URL(string: "tel:+79991234567")!))
        #expect(model.infoRows[1].title == "о себе")
        #expect(model.infoRows[2].value == "max.ru/anna")
        #expect(model.shareURL == URL(string: "https://max.ru/anna"))
        #expect(model.canWrite)
    }

    @Test("Бот: подпись, описание, команды со слешем")
    func bot() async {
        let profile = ChatProfile(
            kind: .bot, chatId: "5", peerId: "77", title: "Помощник",
            description: "Отвечает на вопросы", link: "https://max.ru/helper_bot",
            commands: [.init(name: "start", description: "Начать"), .init(name: "help")]
        )
        let model = makeModel(profile)
        await model.load()
        #expect(model.subtitle == "бот")
        #expect(model.infoRows.first?.title == "описание")
        #expect(model.commands.map(\.command) == ["/start", "/help"])
        #expect(model.commands.first?.description == "Начать")
        #expect(model.shareURL == URL(string: "https://max.ru/helper_bot"))
    }

    @Test("Канал: подписчики с разрядами и правильным окончанием, без «Написать»")
    func channel() async {
        let model = makeModel(ChatProfile(kind: .channel, chatId: "-9", title: "Новости", link: "news", participants: 12_501, isOfficial: true, isPublic: true))
        await model.load()
        #expect(model.subtitle == "12\u{202F}501 подписчик")
        #expect(model.isOfficial)
        #expect(!model.canWrite)
        #expect(model.infoRows.first?.title == "ссылка")
    }

    @Test("Множественное число по-русски")
    func plural() {
        let forms = ["участник", "участника", "участников"]
        let words = [1, 2, 5, 11, 12, 21, 22, 25, 101, 111].map { ChatProfileViewModel.plural($0, forms[0], forms[1], forms[2]) }
        #expect(words == ["участник", "участника", "участников", "участников", "участников", "участник", "участника", "участников", "участник", "участников"])
    }

    @Test("Ошибка без карточки видна, отмена — нет")
    func failure() async {
        let failing = ChatProfileViewModel(chatId: "1", title: "Чат", repository: FakeProfiles(result: .failure(.networkUnavailable)))
        await failing.load()
        #expect(failing.state == .failed("Нет соединения с сервером"))
        let cancelled = ChatProfileViewModel(chatId: "1", title: "Чат", repository: FakeProfiles(result: .failure(.cancelled)))
        await cancelled.load()
        #expect(cancelled.state == .loading)
    }

    @Test("Короткое имя и полная ссылка дают одну и ту же ссылку Max")
    func linkURL() {
        #expect(ChatProfile(kind: .user, chatId: "1", title: "", link: "@anna").linkURL == URL(string: "https://max.ru/anna"))
        #expect(ChatProfile(kind: .user, chatId: "1", title: "", link: "https://max.ru/anna").linkURL == URL(string: "https://max.ru/anna"))
        #expect(ChatProfile(kind: .user, chatId: "1", title: "", link: " ").linkURL == nil)
    }
}
