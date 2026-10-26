import Foundation
import MaxlyDomain

/// Что экран чата показывает в канале, группе и личном диалоге (docs/chat-screen.md).
///
/// Одно место для всех решений «по типу чата»: экран, лента, поле ввода и пузыри читают их
/// отсюда, а не проверяют тип каждый у себя. Чистое значение из того, что знает экран: тип из
/// списка чатов, право писать, карточка чата (для чата вне списка) и состояние ленты.
public struct ChatScreenRules: Equatable, Sendable {
    /// Что стоит внизу вместо или вместо части поля ввода.
    public enum BottomBar: Equatable, Sendable {
        /// Поле ввода.
        case composer
        /// Пустой диалог с ботом: «Начать» (`startBot` ядра), поле ввода — после ответа бота.
        case startBot
        /// Чат вне списка с публичной ссылкой: «Подписаться» (канал) или «Вступить» (группа).
        case join(label: String)
        /// Подписчик канала: звук и поиск.
        case channelControls
        /// Писать нельзя, и других действий нет.
        case readOnly
    }

    /// Варианты закрепа сообщения.
    public enum PinOptions: Equatable, Sendable {
        /// Диалог: «Только у меня» или у обоих.
        case dialog
        /// Группа: с уведомлением участников или без.
        case group
        /// Канал: просто закрепить.
        case channel
    }

    /// Плашка под шапкой в диалоге с человеком не из контактов.
    public struct StrangerBar: Equatable, Sendable {
        /// «Заблокировать» рядом с «Добавить в контакты»: пока сам ему не писал.
        public var offersBlock: Bool
    }

    /// Что знает экран.
    public struct Input: Equatable, Sendable {
        /// Тип из списка чатов.
        public var listedType: ChatType
        /// Право писать из списка; `nil` — чата нет в списке (из поиска, по ссылке).
        public var canWrite: Bool?
        /// Вид из карточки чата; `nil` — карточка ещё не пришла.
        public var card: ChatProfile.Kind?
        /// У чата вне списка есть публичная ссылка: по ней можно подписаться или вступить.
        public var hasJoinLink = false
        /// Звук чата переключается со списка (чат в списке).
        public var canToggleMute = false
        /// Комментарии канала: `true` включены, `false` выключены, `nil` неизвестно.
        public var commentsEnabled: Bool?
        /// История сверена с сервером и в ней нет сообщений.
        public var historyEmpty = false
        /// Человек не в контактах, и его можно добавить (`ChatProfileViewModel.contactAction`).
        public var contactAddable = false
        /// Собеседник в чёрном списке; `nil` — неизвестно.
        public var peerBlocked: Bool?
        /// В ленте есть свои сообщения.
        public var hasOwnMessages = false
        /// Плашку незнакомца закрыли крестиком.
        public var strangerBarDismissed = false

        public init(listedType: ChatType, canWrite: Bool?, card: ChatProfile.Kind? = nil) {
            self.listedType = listedType
            self.canWrite = canWrite
            self.card = card
        }
    }

    /// Тип чата: из списка, а для чата вне списка — из карточки.
    public let kind: ChatType
    /// Поле ввода можно показать.
    public let writable: Bool
    public let bottomBar: BottomBar
    /// Комментарии под постами канала.
    public let allowsComments: Bool
    /// Звонок собеседнику (из профиля): только диалог с человеком.
    public let canCall: Bool
    /// «Выйти из группы» или «Отписаться» из профиля: группа или канал в списке.
    public let canLeave: Bool
    /// Подсказка «Канал готов» в пустом своём канале.
    public let showsChannelReady: Bool
    /// Поиск по каналу — кнопкой в нижней плашке подписчика.
    public let searchInBottomBar: Bool
    public let strangerBar: StrangerBar?

    public init(_ input: Input) {
        let listed = input.canWrite != nil
        let kind: ChatType
        let writable: Bool
        if let canWrite = input.canWrite {
            kind = input.listedType
            writable = canWrite
        } else {
            // Чат вне списка: вид из карточки. Писать можно только в личный диалог, боту и в
            // «Избранное», и только когда карточка уже пришла — иначе поле мелькнуло бы и пропало.
            switch input.card {
            case .channel?:
                kind = .channel
                writable = false
            case .group?:
                kind = .group
                writable = false
            case .user?, .bot?, .saved?:
                kind = .private
                writable = true
            case nil:
                kind = input.listedType
                writable = false
            }
        }
        self.kind = kind
        self.writable = writable

        let bottomBar: BottomBar
        if writable {
            bottomBar = input.card == .bot && input.historyEmpty ? .startBot : .composer
        } else if !listed, input.hasJoinLink, input.card == .channel || input.card == .group {
            bottomBar = .join(label: input.card == .channel ? "Подписаться" : "Вступить")
        } else if kind == .channel, input.canToggleMute {
            bottomBar = .channelControls
        } else {
            bottomBar = .readOnly
        }
        self.bottomBar = bottomBar

        allowsComments = kind == .channel && input.commentsEnabled == true
        canCall = kind == .private && input.card == .user
        canLeave = listed && kind != .private
        showsChannelReady = kind == .channel && writable
        searchInBottomBar = bottomBar == .channelControls && listed
        if kind == .private, input.card == .user, input.contactAddable, input.peerBlocked != true,
           !input.strangerBarDismissed {
            strangerBar = StrangerBar(offersBlock: !input.hasOwnMessages)
        } else {
            strangerBar = nil
        }
    }

    /// Имена и аватары авторов у чужих сообщений и переход в профиль автора: только группа.
    /// В диалоге автор один, в канале посты от имени канала.
    public var showsAuthors: Bool { kind == .group }
    /// Кто поставил реакцию: аватары на реакциях — только в группе.
    public var showsReactionUsers: Bool { kind == .group }
    /// Кнопка «@» к непрочитанным упоминаниям: только группа.
    public var showsMentionsButton: Bool { kind == .group }
    /// Выбор сообщений в канале с правом писать: удаление у всех подписчиков.
    public var isChannelAdmin: Bool { kind == .channel && writable }
    public var pinOptions: PinOptions {
        switch kind {
        case .private: .dialog
        case .group: .group
        case .channel: .channel
        }
    }
    /// Пункт удаления сообщения у всех.
    public var deleteForAllTitle: String {
        kind == .private ? "Удалить у меня и у собеседника" : "Удалить у всех"
    }
}
