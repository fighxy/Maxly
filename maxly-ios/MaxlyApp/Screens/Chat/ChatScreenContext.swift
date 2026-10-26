import Foundation
import MaxlyDomain
import MaxlyPresentation

/// Всё, что экран чата получает снаружи, кроме своей модели: данные чата из списка, службы
/// приложения и действия, которые выполняют список чатов и навигация. Собирает
/// `ChatScreenFactory`; раньше это были три десятка параметров `ChatView`.
struct ChatScreenContext {
    /// Данные чата на момент открытия экрана.
    struct Info {
        var title: String
        /// Комментарии канала: `true` включены, `false` выключены, `nil` сервер не сказал —
        /// тогда кнопка есть только у постов, к которым сервер прислал счётчик.
        var commentsEnabled: Bool?
        /// В группе у чужих сообщений видны имя и аватар автора, в личном чате и канале — нет.
        var chatType: ChatType = .private
        /// Можно ли писать. Нет — вместо поля ввода плашка (в канале — уведомления).
        /// `nil` — чата нет в списке (открыт из поиска или по ссылке): решает карточка чата.
        var canWrite: Bool? = true
        var isMuted = false
        /// Эмодзи двойного нажатия. `nil` — сервер выключил быструю реакцию.
        var quickReaction: String?
        /// Открыть профиль, как только он готов («Перейти в профиль» из истории).
        var opensProfile = false
    }

    /// Службы и живые данные приложения.
    struct Services {
        /// Чаты для пересылки (без текущего).
        var forwardTargets: () -> [ChatListItem] = { [] }
        /// Звук чата прямо из списка чатов. Читается в `body`, поэтому экран обновляется сразу,
        /// как переключили звук; снимок `isMuted` мог остаться прежним.
        var mutedNow: (() -> Bool)?
        /// Контакты для вкладки «Контакт» листа вложений. `nil` — вкладка пустая.
        var contactList: (() -> AsyncStream<[Contact]>)?
        /// Панель эмодзи и стикеров (одна на приложение: каталог грузится раз).
        var stickerPanel: StickerPanelModel?
        /// Сеть, «печатает…», звук и галочка — живые данные из списка чатов для шапки.
        var live: () -> ChatHeaderLive = { ChatHeaderLive() }
        /// Модель профиля чата: шапка берёт из неё статус, нажатие на шапку открывает профиль.
        var makeProfile: (() -> ChatProfileViewModel?)?
        var makeParticipantProfile: ((DialogDraft) -> ChatProfileViewModel?)?
        /// Управление группой или каналом. `nil` — до входа ядра.
        var chatAdmin: (any ChatAdminRepository)?
        /// Мини-приложение бота: кнопка «Открыть» и inline-кнопки `OPEN_APP`.
        var makeBotApp: ((BotAppRequest) -> MiniAppModel)?
        /// Звук на срок и папки для профиля (через список чатов).
        var listActions: ChatProfileListActions?
        /// Полоса «играет голосовое»; `nil` — без неё.
        var nowPlaying: VoiceNowPlaying?
    }

    /// Действия, которые выполняет не экран, а список чатов или навигация.
    struct Actions {
        var toggleMute: (() -> Void)?
        /// Очистка переписки или удаление чата из профиля. Первый флаг — очистка, второй — у всех.
        var eraseChat: ((Bool, Bool) -> Void)?
        /// Выйти из группы или отписаться от канала из профиля.
        var leave: (() -> Void)?
        /// Открыть другой чат из профиля (общий чат собеседника).
        var openChat: ((String) -> Void)?
        /// Открыть личный диалог (из «Кем прочитано»): черновик запоминается, чат открывается.
        var openDialog: ((DialogDraft) -> Void)?
        /// Пометка «непрочитано» с сообщения, отправленного в эту дату. Экран закрывает тот, кто
        /// открыл чат, когда сервер принял пометку.
        var markUnread: ((Date) -> Void)?
        /// Позвонить собеседнику личного чата (из профиля): аудио или видео.
        var call: ((CallCenter.Peer, Bool) -> Void)?
        /// Просьба открыть профиль (`Info.opensProfile`) выполнена.
        var profileOpened: () -> Void = {}
        /// Касание полосы, когда голосовое из другого чата: открыть тот чат на сообщении.
        var openVoice: ((VoiceNowPlaying.Track) -> Void)?
    }

    var info: Info
    var services = Services()
    var actions = Actions()
}
