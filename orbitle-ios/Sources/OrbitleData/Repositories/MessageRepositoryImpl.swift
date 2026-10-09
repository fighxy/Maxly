import Foundation
import SwiftData
import OrbitleDomain

/// Реализация `MessageRepository` поверх SwiftData, сервера и очереди исходящих.
///
/// Пагинация идёт курсором по `timestamp`: страница содержит `pageSize` сообщений
/// строго старше курсора, от новых к старым. `loadMore` сначала берёт страницу
/// из кэша и, если её не хватает, догружает историю с сервера. Для каждого чата
/// репозиторий помнит, сколько сообщений показано (окно), и `loadOlder` расширяет
/// окно на страницу.
///
/// Отправка оптимистичная: сообщение сразу записывается со статусом `sending`
/// и ставится в `OutboxQueue`. Очередь сообщает результат через `OutboxStore`:
/// при успехе статус `sent` и `serverId`, при ошибке `failed`.
///
/// Swift 6: это `ModelActor` со своим фоновым контекстом. Макрос `@ModelActor`
/// не умеет инициализатор с `api`, поэтому `modelExecutor` и `modelContainer`
/// заданы явно. Модели SwiftData не покидают актор.
public actor MessageRepositoryImpl: MessageRepository, OutboxStore, ModelActor {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    public static let pageSize = 50

    private struct Observer {
        let chatId: String
        /// Пустая строка — основная лента, иначе id поста.
        let threadOf: String
        let continuation: AsyncStream<[Message]>.Continuation
    }

    private var observers: [UUID: Observer] = [:]
    /// Сколько последних сообщений показано в каждом чате.
    private var windows: [String: Int] = [:]
    /// Текущий автор исходящих. Задаётся после входа.
    private var currentUserId = ""
    private let api: any MaxAPI
    private var outbox: OutboxQueue?
    /// Растёт при каждой очистке базы. История, запрошенная до очистки, в базу не пишется.
    private var generation = 0
    /// Своё сообщение поставлено в очередь или ушло на сервер. Через это строка чата
    /// в списке сдвигается сразу, не дожидаясь пуша. Подключает `SyncEngine`.
    private var outgoingHandler: (@Sendable (OutgoingChange) async -> Void)?
    /// Последний запрос реакции по локальному id сообщения. Ответы на прежние запросы
    /// игнорируются, пуши не перебивают ожидающее нажатие.
    private var pendingReactions: [String: Int] = [:]
    /// Серверные id, для которых `MSG_GET_REACTIONS` уже спрашивали в этом сеансе.
    /// История канала не несёт реакций, и без этого каждый опрос спрашивал бы страницу заново.
    private var reactionsAsked: Set<String> = []
    /// До этого времени опрос чата не повторяет реакции после ошибки сервера.
    private var reactionsRetryAt: [String: Date] = [:]
    private var reactionRequest = 0
    /// Каталог реакций сервера, после первой удачной загрузки.
    private var catalog: [String]?
    /// Идущие загрузки вложений по локальному id сообщения.
    private var uploads: [String: Task<Void, Never>] = [:]
    /// Доля загрузки 0…1 по локальному id. Только в памяти: после перезапуска загрузка не
    /// продолжается, сообщение становится `failed` и ждёт повтора.
    private var progress: [String: Double] = [:]
    /// Загрузки, которые отменил пользователь: их сообщения удаляются, а не падают в `failed`.
    private var cancelledUploads: Set<String> = []
    private var progressObservers: [UUID: AsyncStream<[String: Double]>.Continuation] = [:]
    private var failureObservers: [UUID: AsyncStream<UploadFailure>.Continuation] = [:]
    /// Ошибки `attachError` по локальному id загрузки: ответ ядра на ту же загрузку берёт текст
    /// отсюда, если сам его не принёс.
    private var attachErrors: [String: String] = [:]
    /// Загрузки, уже помеченные `failed` по пушу: второй раз о них не сообщаем.
    private var reportedFailures: Set<String> = []
    /// Эхо своих сообщений, пришедшее раньше ответа на отправку, по серверному id. Сервер шлёт
    /// пуш о своём сообщении до того, как ответит на запрос отправки: раньше оно ложилось
    /// второй строкой и пропадало, когда приходил ответ, — лента прыгала. Теперь эхо ждёт
    /// ответа (`echoHold`); пришёл — эхо не нужно, нет — ложится в базу как есть.
    private var heldEchoes: [String: MessageRecord] = [:]
    /// Отметка прочтения собеседника по чату, мс: свои отправленные до неё — две галочки.
    /// Берётся из строки чата при первом показе, дальше растёт по `notePeerRead`.
    private var peerReadMarks: [String: Int64] = [:]
    static let echoHold: Duration = .seconds(8)
    /// Сколько последних сообщений сверяет `refreshReactions`: столько принимает один запрос.
    static let reactionsPage = 100
    /// Когда последняя страница чата в последний раз пришла с сервера.
    private var latestFetchedAt: [String: Date] = [:]
    /// Сколько секунд свежая страница считается актуальной. Возврат из профиля, опрос и
    /// повторное открытие чата в это окно сервер не спрашивают: на частые `CHAT_HISTORY`
    /// он отвечает `too.many.requests`. Новые сообщения в это время приходят пушами.
    private let latestReuse: TimeInterval
    /// Обновление просроченных адресов фото. Выключено, пока сервер не разрешил.
    private var photoRefreshEnabled = false
    private var photoURLExpired: @Sendable (String, Int64) -> Bool = { _, _ in false }
    private var photoRefreshQueue = PhotoRefreshQueue()

    /// Что случилось со своим сообщением.
    public enum OutgoingChange: Sendable, Equatable {
        /// Записано локально и ждёт отправки.
        case queued(MessageRecord)
        /// Сервер принял, у записи уже есть `serverId` и время сервера.
        case sent(MessageRecord)
        /// Отправка не удалась, сообщение ждёт повтора.
        case failed(MessageRecord)
        /// Удалённые сообщения чата (свои или убранные сверкой с сервером; локальные и
        /// серверные id): строке списка нужно новое последнее сообщение, если удалили его.
        case deleted(chatId: String, ids: [String])
    }

    /// `latestReuse` — сколько секунд последняя страница чата не перезапрашивается.
    public init(modelContainer: ModelContainer, api: any MaxAPI, latestReuse: TimeInterval = 10) {
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = modelContainer
        self.api = api
        self.latestReuse = latestReuse
    }

    public static func make(stack: SwiftDataStack, api: any MaxAPI) -> MessageRepositoryImpl {
        MessageRepositoryImpl(modelContainer: stack.container, api: api)
    }

    /// Подключает очередь исходящих. Очередь держит репозиторий слабой ссылкой.
    public func attach(outbox: OutboxQueue) async {
        self.outbox = outbox
        failStaleUploads()
        await outbox.attach(store: self)
    }

    public func setCurrentUser(id: String) {
        currentUserId = id
    }

    /// `enabled` — флаг сервера `photo-url-refresh`. Пока он выключен, адреса не спрашиваются.
    public func setPhotoURLRefresh(enabled: Bool, maxPerRequest: Int = 100, expired: @escaping @Sendable (String, Int64) -> Bool) {
        photoRefreshEnabled = enabled
        photoURLExpired = expired
        photoRefreshQueue = PhotoRefreshQueue(maxPerRequest: maxPerRequest)
    }

    public func currentUser() -> String {
        currentUserId
    }

    public func setOutgoingHandler(_ handler: (@Sendable (OutgoingChange) async -> Void)?) {
        outgoingHandler = handler
    }

    // MARK: MessageRepository

    /// Сообщения чата от старых к новым, в пределах текущего окна.
    /// Первое значение приходит сразу из кэша.
    public nonisolated func messages(chatId: String) -> AsyncStream<[Message]> {
        stream(chatId: chatId, threadOf: "")
    }

    public nonisolated func comments(chatId: String, postId: String) -> AsyncStream<[Message]> {
        stream(chatId: chatId, threadOf: postId)
    }

    private nonisolated func stream(chatId: String, threadOf: String) -> AsyncStream<[Message]> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addObserver(id, chatId: chatId, threadOf: threadOf, continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeObserver(id) }
            }
        }
    }

    /// Расширяет окно на одну страницу, при необходимости догружая историю с сервера.
    public func loadOlder(chatId: String) async throws(OrbitleError) {
        let shown = windows[chatId] ?? Self.pageSize
        let window = (try? fetchPage(chatId: chatId, before: nil, limit: shown)) ?? []
        _ = try await loadMore(chatId: chatId, before: window.last?.timestamp)
        windows[chatId] = shown + Self.pageSize
        notify(chatId: chatId)
    }

    /// Оптимистичная отправка: сообщение сразу попадает в базу со статусом `sending`
    /// и ставится в очередь. Результат отправки подписчики увидят через смену статуса.
    public func send(text: String, chatId: String) async throws(OrbitleError) {
        try await send(text: text, chatId: chatId, replyTo: nil)
    }

    /// Текст уходит в очередь. Цитата хранится локально: фасад пока отправляет только текст.
    public func send(text: String, chatId: String, replyTo: String?) async throws(OrbitleError) {
        try await send(text: text, chatId: chatId, replyTo: replyTo, formatting: [])
    }

    public func send(text: String, chatId: String, replyTo: String?, formatting: [TextSpan]) async throws(OrbitleError) {
        let localId = "local-\(UUID().uuidString)"
        var content = MessageContent.empty
        content.reply = replyQuote(replyTo)
        content.formatting = formatting.isEmpty ? nil : formatting
        let message = SDMessage(
            id: localId,
            chatId: chatId,
            authorId: currentUserId,
            text: text,
            timestamp: .now,
            status: .sending
        )
        message.contentJSON = MessageContentCodec.encode(content)
        do {
            message.chat = try chat(id: chatId)
            modelContext.insert(message)
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify(chatId: chatId)
        await outgoingHandler?(.queued(Self.record(message)))
        await outbox?.enqueue(localId)
    }

    // MARK: Вложения

    /// Пузырь с локальными копиями появляется сразу (`sending`), затем в фоне идут загрузка
    /// и `MSG_SEND`. Очередь текстов (`OutboxQueue`) эти сообщения не трогает: у них свой
    /// путь с ходом загрузки и отменой.
    public func sendAttachments(_ drafts: [AttachmentDraft], caption: String, chatId: String, replyTo: String?) async throws(OrbitleError) {
        guard !drafts.isEmpty else { throw .invalidRequest }
        let localId = "local-\(UUID().uuidString)"
        var content = MessageContent.empty
        content.reply = replyQuote(replyTo)
        content.attachments = drafts.enumerated().map { $0.element.preview(index: $0.offset) }
        content.drafts = drafts
        let text = drafts.contains { $0.kind == .contact || $0.kind == .sticker || $0.isRecording } ? "" : caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = SDMessage(
            id: localId,
            chatId: chatId,
            authorId: currentUserId,
            text: text,
            timestamp: .now,
            status: .sending
        )
        message.contentJSON = MessageContentCodec.encode(content)
        do {
            message.chat = try chat(id: chatId)
            modelContext.insert(message)
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify(chatId: chatId)
        await outgoingHandler?(.queued(Self.record(message)))
        startUpload(localId: localId)
    }

    /// Идущая загрузка отменяется, и сообщение исчезает. Неотправленное сообщение с
    /// вложениями без загрузки (упавшее) просто удаляется.
    public func cancelUpload(messageId: String) async {
        if let task = uploads[messageId] {
            cancelledUploads.insert(messageId)
            task.cancel()
            return
        }
        guard let message = try? message(id: messageId), message.status != .sent,
              Self.content(of: message).hasPendingUploads else { return }
        removeUnsent(localId: messageId)
    }

    public nonisolated func uploadProgress() -> AsyncStream<[String: Double]> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addProgressObserver(id, continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeProgressObserver(id) }
            }
        }
    }

    public nonisolated func uploadFailures() -> AsyncStream<UploadFailure> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addFailureObserver(id, continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeFailureObserver(id) }
            }
        }
    }

    private func addFailureObserver(_ id: UUID, _ continuation: AsyncStream<UploadFailure>.Continuation) {
        failureObservers[id] = continuation
    }

    private func removeFailureObserver(_ id: UUID) {
        failureObservers[id] = nil
    }

    var failureObserverCount: Int { failureObservers.count }

    private func publishFailure(_ failure: UploadFailure) {
        for continuation in failureObservers.values {
            continuation.yield(failure)
        }
    }

    /// Пуш `attachError`: сервер не принял файл, видео или аудио. Идущая загрузка того же вида
    /// сразу становится `failed` (если она такая одна), текст ошибки уходит открытому чату.
    /// Id вложения клиент до ответа не знает, поэтому сверяется вид.
    public func attachmentFailed(attachId: String, kind: String, text: String) async {
        let reason = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.warning(.messages, "Сервер не принял вложение \(kind) \(attachId): \(reason)")
        let candidates = uploads.keys.filter { localId in
            guard !reportedFailures.contains(localId), let stored = try? message(id: localId) else { return false }
            let drafts = Self.content(of: stored).drafts ?? []
            return drafts.contains { Self.matches($0.kind, attachKind: kind) }
        }
        guard candidates.count == 1, let localId = candidates.first,
              let message = try? message(id: localId) else { return }
        attachErrors[localId] = reason
        reportedFailures.insert(localId)
        message.status = .failed
        try? modelContext.save()
        notify(chatId: message.chatId)
        publishFailure(UploadFailure(chatId: message.chatId, messageId: localId, text: reason))
        await outgoingHandler?(.failed(Self.record(message)))
    }

    static func matches(_ draft: AttachmentDraft.Kind, attachKind: String) -> Bool {
        switch attachKind {
        case "file": draft == .file
        case "video": draft == .video || draft == .videoNote
        case "audio": draft == .voice
        default: draft == .file || draft == .video || draft == .videoNote || draft == .voice
        }
    }

    /// Загрузка ещё идёт (для тестов и повтора).
    public func isUploading(localId: String) -> Bool {
        uploads[localId] != nil
    }

    /// Дождаться конца загрузки сообщения, если она идёт.
    public func waitForUpload(localId: String) async {
        await uploads[localId]?.value
    }

    private func startUpload(localId: String) {
        guard uploads[localId] == nil, let stored = try? message(id: localId) else { return }
        let content = Self.content(of: stored)
        guard let drafts = content.drafts, !drafts.isEmpty else { return }
        let chatId = stored.chatId
        let caption = stored.text
        let quoted = content.reply?.messageId
        let replyTo = quoted.flatMap { Int64($0) == nil ? nil : $0 }
        let api = api
        progress[localId] = 0
        publishProgress()
        // Репозиторий живёт всё время работы приложения: сильная ссылка на время загрузки безопасна.
        uploads[localId] = Task {
            let result = await api.sendAttachments(chatId: chatId, drafts: drafts, caption: caption, replyTo: replyTo) { fraction in
                Task { await self.noteProgress(localId: localId, fraction: fraction) }
            }
            await self.finishUpload(localId: localId, result: result)
        }
    }

    private func noteProgress(localId: String, fraction: Double) {
        guard uploads[localId] != nil else { return }
        let value = min(max(fraction, 0), 1)
        // Колбэки идут отдельными задачами и могут прийти не по порядку.
        guard value > (progress[localId] ?? 0) else { return }
        progress[localId] = value
        publishProgress()
    }

    private func finishUpload(localId: String, result: Result<MessageRecord, MaxAPIError>) async {
        uploads[localId] = nil
        let pushed = attachErrors.removeValue(forKey: localId)
        let reported = reportedFailures.remove(localId) != nil
        progress[localId] = nil
        publishProgress()
        let cancelled = cancelledUploads.remove(localId) != nil
        guard let message = try? message(id: localId) else { return }
        if cancelled {
            Log.info(.messages, "Загрузка вложений отменена")
            removeUnsent(localId: localId)
            return
        }
        switch result {
        case .success(let record):
            let serverId = record.serverId ?? record.id
            heldEchoes[serverId] = nil
            for echo in (try? echoes(of: serverId, except: localId)) ?? [] {
                modelContext.delete(echo)
            }
            var content = Self.content(of: message)
            let fresh = MessageContentCodec.decode(record.contentJSON)
            content.attachments = Self.keepingLocalCopies(fresh.attachments, local: content.attachments)
            content.formatting = fresh.formatting
            content.drafts = nil
            message.contentJSON = MessageContentCodec.encode(content)
            if !record.text.isEmpty { message.text = record.text }
            message.status = .sent
            message.serverId = serverId
            message.timestamp = record.timestamp
            try? modelContext.save()
            notify(chatId: message.chatId)
            Log.info(.messages, "Вложения отправлены: \(serverId)")
            await outgoingHandler?(.sent(Self.record(message)))
        case .failure(let error):
            Log.warning(.messages, "Вложения не отправлены: \(error)")
            message.status = .failed
            try? modelContext.save()
            notify(chatId: message.chatId)
            guard !reported else { return }
            publishFailure(UploadFailure(chatId: message.chatId, messageId: localId, text: pushed ?? Self.uploadErrorText(error)))
            await outgoingHandler?(.failed(Self.record(message)))
        }
    }

    /// Текст ошибки загрузки от сервера: его фраза или ключ ошибки. Сеть и отмена — без текста.
    static func uploadErrorText(_ error: MaxAPIError) -> String {
        switch error {
        case .server(let code, let text): text ?? code
        case .rejected(let text): text
        default: ""
        }
    }

    /// Вложения сервера с путями к своим копиям: фото и видео видны сразу, без скачивания.
    /// Пары ищутся по порядку внутри вида: сервер держит порядок `attaches`.
    static func keepingLocalCopies(_ server: [ChatAttachment], local: [ChatAttachment]) -> [ChatAttachment] {
        guard !server.isEmpty else { return local }
        var photos = local.compactMap(\.photo).compactMap(\.localPath)[...]
        var videos = local.compactMap(\.video).compactMap(\.localPath)[...]
        var files = local.compactMap(\.file).compactMap(\.localPath)[...]
        var voices = local.compactMap(\.voice).compactMap(\.localPath)[...]
        return server.map { attachment in
            switch attachment {
            case .photo(var item):
                if item.localPath == nil, let path = photos.popFirst() { item.localPath = path }
                return .photo(item)
            case .video(var item):
                if item.localPath == nil, let path = videos.popFirst() { item.localPath = path }
                return .video(item)
            case .file(var item):
                if item.localPath == nil, let path = files.popFirst() { item.localPath = path }
                return .file(item)
            case .voice(var item):
                // Своё голосовое играет с записанного файла, без скачивания.
                if item.localPath == nil, let path = voices.popFirst() { item.localPath = path }
                return .voice(item)
            case .sticker(var item):
                // Ответ на отправку может прийти без адресов: остаются те, что были в пузыре.
                if let mine = local.compactMap(\.sticker).first(where: { $0.stickerId == item.stickerId }) {
                    if item.url == nil { item.url = mine.url }
                    if item.lottieURL == nil { item.lottieURL = mine.lottieURL }
                    if item.width == nil { item.width = mine.width; item.height = mine.height }
                }
                return .sticker(item)
            default:
                return attachment
            }
        }
    }

    private func removeUnsent(localId: String) {
        guard let message = try? message(id: localId) else { return }
        let chatId = message.chatId
        modelContext.delete(message)
        try? modelContext.save()
        notify(chatId: chatId)
    }

    /// После перезапуска загрузок нет: зависшие в `sending` сообщения с вложениями падают в
    /// `failed`, их можно повторить.
    private func failStaleUploads() {
        let sending = MessageStatus.sending.rawValue
        let descriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { $0.statusRaw == sending })
        var changed = Set<String>()
        for message in (try? modelContext.fetch(descriptor)) ?? [] where uploads[message.id] == nil {
            guard Self.content(of: message).hasPendingUploads else { continue }
            message.status = .failed
            changed.insert(message.chatId)
        }
        guard !changed.isEmpty else { return }
        try? modelContext.save()
        changed.forEach(notify(chatId:))
    }

    private func replyQuote(_ replyTo: String?) -> MessageReply? {
        guard let replyTo, let target = (try? message(id: replyTo)) ?? (try? message(serverId: replyTo)) else { return nil }
        let quoted = Self.record(target).domain
        let name = quoted.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return MessageReply(
            messageId: quoted.serverId ?? quoted.id,
            authorName: quoted.authorId == currentUserId ? "Вы" : (name.isEmpty ? "Сообщение" : name),
            preview: quoted.replySnippet,
            kind: quoted.replyKind
        )
    }

    private func addProgressObserver(_ id: UUID, _ continuation: AsyncStream<[String: Double]>.Continuation) {
        if case .terminated = continuation.yield(progress) { return }
        progressObservers[id] = continuation
    }

    private func removeProgressObserver(_ id: UUID) {
        progressObservers[id] = nil
    }

    private func publishProgress() {
        for continuation in progressObservers.values {
            continuation.yield(progress)
        }
    }

    /// Своя реакция: сразу в базе, затем на сервере. Ответ сервера (если в нём есть реакции)
    /// становится итогом, отказ возвращает прежние реакции. Для быстрых нажатий в базу
    /// ложится итог только последнего запроса по сообщению.
    public func toggleReaction(messageId: String, emoji: String) async throws(OrbitleError) {
        guard !emoji.isEmpty else { throw .invalidRequest }
        let stored = (try? message(id: messageId)) ?? (try? message(serverId: messageId))
        guard let stored else { throw .invalidRequest }
        guard let serverId = stored.serverId, Int64(serverId) != nil, stored.status == .sent else {
            throw .rejected("Сообщение ещё не отправлено")
        }
        let localId = stored.id
        let chatId = stored.chatId
        let postId = stored.threadOf
        let before = Self.content(of: stored).reactions
        let after = before.toggled(emoji)
        let wanted = after.mine
        try saveReactions(after, localId: localId)

        reactionRequest += 1
        let request = reactionRequest
        pendingReactions[localId] = request
        let result = await api.setReaction(chatId: chatId, messageId: serverId, postId: postId, emoji: wanted)
        // Поздний ответ на обогнанное нажатие ничего не трогает: итог даст последнее.
        guard pendingReactions[localId] == request else {
            if case .failure(let error) = result { Log.info(.messages, "Реакция обогнана новой: \(error)") }
            return
        }
        pendingReactions[localId] = nil
        switch result {
        case .success(let update):
            if let update {
                // Ответ на свою реакцию: своя известна, даже если сервер промолчал о ней.
                var confirmed = update
                if !confirmed.mineKnown {
                    confirmed.mine = wanted
                    confirmed.mineKnown = true
                }
                try applyReactions(localId: localId, update: confirmed)
            }
            Log.info(.messages, wanted == nil ? "Реакция снята с \(serverId)" : "Реакция на \(serverId) поставлена")
        case .failure(let error):
            Log.warning(.messages, "Реакция не изменена: \(error)")
            try? saveReactions(before, localId: localId, onlyIf: after)
            throw error.orbitleError
        }
    }

    /// Сверка реакций после возврата в приложение: пуши за время в фоне могли потеряться.
    ///
    /// Последняя страница перечитывается историей, как при входе в чат: там реакции есть у
    /// каждого сообщения, и это итог сервера (в том числе «реакций нет»). Более старые
    /// сообщения окна сверяются одним `MSG_GET_REACTIONS`. Из его ответа берутся только
    /// сообщения с реакциями: пропуск или пустая запись не значат «реакций нет» (сервер мог
    /// не узнать id), а стирать чужие реакции по такому ответу нельзя.
    public func refreshReactions(chatId: String) async {
        // Страница только что пришла (открытие чата, опрос): пуши за эти секунды не потерялись.
        if let at = latestFetchedAt[chatId], Date().timeIntervalSince(at) < latestReuse { return }
        let started = generation
        var covered = Set<String>()
        let requestedAt = Date.now
        switch await api.fetchMessages(chatId: chatId, before: nil, limit: Self.pageSize) {
        case .success(let fetched):
            let records = await withReactions(fetched, chatId: chatId, again: true)
            guard started == generation else { return }
            do {
                try upsert(records)
                latestFetchedAt[chatId] = Date()
                // Пустую историю при возврате из фона за «чат пуст» не считаем.
                let gone = records.isEmpty ? [] : pruneMissing(chatId: chatId, page: records, requestedAt: requestedAt)
                if !gone.isEmpty { await outgoingHandler?(.deleted(chatId: chatId, ids: gone)) }
                covered = Set(records.map { $0.serverId ?? $0.id })
            } catch {
                Log.info(.messages, "История для сверки реакций не записана: \(error)")
            }
        case .failure(let error):
            Log.info(.messages, "История для сверки реакций не загружена: \(error)")
        }

        let shown = min(windows[chatId] ?? Self.pageSize, Self.reactionsPage)
        let rows = (try? fetchPage(chatId: chatId, before: nil, limit: shown)) ?? []
        let serverIds = rows.compactMap { row -> String? in
            guard let serverId = row.serverId, Int64(serverId) != nil, row.status == .sent,
                  !covered.contains(serverId) else { return nil }
            return serverId
        }
        guard !serverIds.isEmpty, started == generation else { return }
        await applyFetchedReactions(chatId: chatId, serverIds: serverIds, started: started)
    }

    /// История канала приходит без реакций (`reactionsKnown == false`): они дозапрашиваются
    /// (`MSG_GET_REACTIONS`) до записи, и пузырь сразу ложится с реакциями —
    /// а не вырастает через мгновение после показа. Не ответил сервер — записи как были:
    /// реакции догонит `syncReactions`.
    /// `again` — сверка после фона: те же id спрашиваются ещё раз. Обычный опрос истории
    /// повторно их не трогает, а после ошибки сервера ждёт 30 секунд.
    func withReactions(_ records: [MessageRecord], chatId: String, again: Bool = false) async -> [MessageRecord] {
        if !again, let until = reactionsRetryAt[chatId], Date() < until { return records }
        let missing = records.compactMap { record -> String? in
            let id = record.serverId ?? record.id
            guard !record.reactionsKnown, Int64(id) != nil else { return nil }
            guard again || !reactionsAsked.contains(id) else { return nil }
            return id
        }
        guard !missing.isEmpty else { return records }
        guard case .success(let reactions) = await api.fetchReactions(chatId: chatId, messageIds: missing) else {
            reactionsRetryAt[chatId] = Date().addingTimeInterval(30)
            return records
        }
        reactionsRetryAt[chatId] = nil
        reactionsAsked.formUnion(missing)
        return records.map { record in
            guard !record.reactionsKnown,
                  let update = reactions[record.serverId ?? record.id],
                  update.counters.contains(where: { $0.count > 0 }) else { return record }
            var content = MessageContentCodec.decode(record.contentJSON)
            content.reactions = update.applied(to: content.reactions)
            var copy = record
            copy.contentJSON = MessageContentCodec.encode(content)
            return copy
        }
    }

    // MARK: Расшифровка голосовых

    public func transcribe(messageId: String, attachmentId: String) async throws(OrbitleError) -> Bool {
        let stored = (try? message(id: messageId)) ?? (try? message(serverId: messageId))
        guard let stored, let serverId = stored.serverId, Int64(serverId) != nil, stored.status == .sent,
              Int64(attachmentId) != nil else {
            throw .rejected("Голосовое ещё не отправлено")
        }
        let chatId = stored.chatId
        let localId = stored.id
        switch await api.transcribe(chatId: chatId, messageId: serverId, audioId: attachmentId) {
        case .success(let result):
            switch result.status {
            case 1:
                if let message = try? message(id: localId) { saveTranscript(result.text, voiceId: attachmentId, in: message) }
                return true
            case 0:
                return false
            default:
                throw .rejected("Не удалось расшифровать голосовое")
            }
        case .failure(let error):
            throw error.orbitleError
        }
    }

    /// Пуш расшифровки (`TRANSCRIPTION_RESULT`): текст ложится в первое голосовое сообщения.
    public func applyTranscription(chatId: String, messageId: String, text: String) {
        guard let stored = try? message(serverId: messageId), chatId.isEmpty || stored.chatId == chatId else { return }
        saveTranscript(text, voiceId: nil, in: stored)
    }

    private func saveTranscript(_ text: String, voiceId: String?, in message: SDMessage) {
        var content = Self.content(of: message)
        var changed = false
        var done = false
        content.attachments = content.attachments.map { attachment in
            guard !done, case .voice(var voice) = attachment, voiceId == nil || voice.id == voiceId else { return attachment }
            done = true
            guard voice.transcript != text else { return attachment }
            voice.transcript = text
            changed = true
            return .voice(voice)
        }
        guard changed else { return }
        message.contentJSON = MessageContentCodec.encode(content)
        try? modelContext.save()
        notify(chatId: message.chatId)
    }

    public func noteCommentCounts(chatId: String, counts: [String: Int]) async {
        guard !counts.isEmpty, let rows = try? messages(serverIds: Array(counts.keys)) else { return }
        var changed = false
        for (serverId, count) in counts {
            guard let message = rows[serverId], message.chatId == chatId else { continue }
            var content = Self.content(of: message)
            guard content.comments?.count != count else { continue }
            content.comments = CommentSummary(count: count)
            message.contentJSON = MessageContentCodec.encode(content)
            changed = true
        }
        guard changed else { return }
        try? modelContext.save()
        notify(chatId: chatId)
    }

    /// Реакции постов канала: история канала отдаёт посты без `reactionInfo`, поэтому они
    /// спрашиваются `MSG_GET_REACTIONS` для показанных сообщений.
    public func syncReactions(chatId: String, messageIds: [String]) async -> Bool {
        let started = generation
        let rows = (try? messages(serverIds: messageIds)) ?? [:]
        let serverIds = messageIds.filter { id in
            Int64(id) != nil && rows[id]?.status == .sent
        }
        guard !serverIds.isEmpty else { return true }
        return await applyFetchedReactions(chatId: chatId, serverIds: serverIds, started: started)
    }

    /// Один `MSG_GET_REACTIONS` и запись ответа. Берутся только сообщения с реакциями:
    /// пропуск или пустая запись не значат «реакций нет».
    private func applyFetchedReactions(chatId: String, serverIds: [String], started: Int) async -> Bool {
        switch await api.fetchReactions(chatId: chatId, messageIds: serverIds) {
        case .success(let reactions):
            guard started == generation else { return true }
            Log.info(.messages, "Реакции: запрошено \(serverIds.count), в ответе \(reactions.count)")
            var changed = false
            // Строки перечитываются одной выборкой: пока шёл запрос, база могла измениться.
            let current = (try? messages(serverIds: serverIds)) ?? [:]
            for serverId in serverIds {
                guard let update = reactions[serverId], update.counters.contains(where: { $0.count > 0 }),
                      let message = current[serverId], pendingReactions[message.id] == nil else { continue }
                var content = Self.content(of: message)
                let fresh = update.applied(to: content.reactions)
                guard fresh != content.reactions else { continue }
                content.reactions = fresh
                message.contentJSON = MessageContentCodec.encode(content)
                changed = true
            }
            guard changed else { return true }
            try? modelContext.save()
            notify(chatId: chatId)
            return true
        case .failure(let error):
            Log.info(.messages, "Реакции чата не обновлены: \(error)")
            return false
        }
    }

    public func reactionUsers(messageId: String) async throws(OrbitleError) -> [ReactionUser] {
        let stored = (try? message(id: messageId)) ?? (try? message(serverId: messageId))
        guard let stored, let serverId = stored.serverId, Int64(serverId) != nil else { return [] }
        switch await api.reactionUsers(chatId: stored.chatId, messageId: serverId) {
        case .success(let users):
            return users
        case .failure(let error):
            throw error.orbitleError
        }
    }

    /// «Кем прочитано»: список ядра, а имена и аватары, которых ядро не знает, — из базы
    /// (пользователи и авторы сохранённых сообщений).
    public func messageReaders(messageId: String) async throws(OrbitleError) -> [MessageReader] {
        let stored = (try? message(id: messageId)) ?? (try? message(serverId: messageId))
        guard let stored, let serverId = stored.serverId, Int64(serverId) != nil else { return [] }
        switch await api.messageReaders(chatId: stored.chatId, messageId: serverId) {
        case .success(let readers):
            return readers.map(withKnownProfile)
        case .failure(let error):
            throw error.orbitleError
        }
    }

    public func readersAvailable(chatId: String) async -> Bool {
        api.readersAvailable(chatId: chatId)
    }

    /// Имя и аватар читателя из базы, если ядро их не дало.
    private func withKnownProfile(_ reader: MessageReader) -> MessageReader {
        guard reader.name.isEmpty || reader.avatarURL == nil else { return reader }
        var reader = reader
        let id = reader.userId
        var users = FetchDescriptor<SDUser>(predicate: #Predicate { $0.id == id })
        users.fetchLimit = 1
        if let user = try? modelContext.fetch(users).first {
            if reader.name.isEmpty { reader.name = user.name }
            if reader.avatarURL == nil { reader.avatarURL = user.avatarUrl.flatMap(URL.init(string:)) }
        }
        guard reader.name.isEmpty || reader.avatarURL == nil else { return reader }
        var authored = FetchDescriptor<SDMessage>(
            predicate: #Predicate { $0.authorId == id && $0.authorName != "" },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        authored.fetchLimit = 1
        if let message = try? modelContext.fetch(authored).first {
            if reader.name.isEmpty { reader.name = message.authorName }
            if reader.avatarURL == nil, !message.authorAvatarURL.isEmpty { reader.avatarURL = URL(string: message.authorAvatarURL) }
        }
        return reader
    }

    public func reactionCatalog() async -> [String] {
        if let catalog { return catalog }
        switch await api.reactionCatalog() {
        case .success(let emoji):
            var seen = Set<String>()
            let unique = emoji.filter { !$0.isEmpty && seen.insert($0).inserted }
            if !unique.isEmpty { catalog = unique }
            return unique
        case .failure(let error):
            Log.info(.messages, "Каталог реакций не загружен: \(error)")
            return []
        }
    }

    /// Реакции из пуша (`SyncEngine`). Сообщения нет в кэше — пуш пропускается. Пока своё
    /// нажатие ждёт сервера, счётчики пуша не перебивают его: итог даст ответ сервера.
    public func applyReactions(chatId: String, messageId: String, update: ReactionUpdate) throws(OrbitleError) {
        guard let message = (try? message(serverId: messageId)) ?? (try? message(id: messageId)),
              message.chatId == chatId, pendingReactions[message.id] == nil else { return }
        try applyReactions(localId: message.id, update: update)
    }

    public func sendComment(text: String, chatId: String, postId: String) async throws(OrbitleError) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let comment = SDMessage(
            id: "local-\(UUID().uuidString)",
            chatId: chatId,
            authorId: currentUserId,
            text: body,
            timestamp: .now,
            status: .sent
        )
        comment.contentJSON = MessageContentCodec.encode(MessageContent(threadOf: postId))
        comment.threadOf = postId
        do {
            comment.chat = try chat(id: chatId)
            modelContext.insert(comment)
            if let parent = try message(id: postId) ?? message(serverId: postId) {
                var parentContent = Self.content(of: parent)
                parentContent.comments = CommentSummary(count: (parentContent.comments?.count ?? 0) + 1)
                parent.contentJSON = MessageContentCodec.encode(parentContent)
            }
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify(chatId: chatId)
    }

    /// Удаление: сначала сервер (для сообщений с серверным id), потом база. Если сервер
    /// отказал, сообщения остаются на месте и ошибка уходит на экран.
    public func delete(messageIds: [String], chatId: String, forEveryone: Bool) async throws(OrbitleError) {
        _ = try await deleteSelection(messageIds: messageIds, chatId: chatId, forEveryone: forEveryone)
    }

    /// Диалог удаления от ядра: сообщения ищутся по локальному или серверному id, ядру уходит
    /// серверный (у неотправленных — локальный: ядро считает их своими «только у себя»).
    public func deletePlan(messageIds: [String], chatId: String) async -> MessageSelectionRules.DeleteOptions? {
        let ids = messageIds.map { id in
            let found = (try? message(id: id)) ?? (try? message(serverId: id))
            return found?.serverId ?? found?.id ?? id
        }
        guard !ids.isEmpty, let plan = await api.deletePlan(chatId: chatId, messageIds: ids) else { return nil }
        return MessageSelectionRules.DeleteOptions(
            canDelete: plan.canDelete,
            showsForEveryone: plan.showsForEveryone,
            forcesForEveryone: plan.forcesForEveryone,
            forEveryoneByDefault: plan.forEveryoneByDefault
        )
    }

    public func editTimeoutSeconds() async -> Int? {
        let seconds = await api.editTimeoutSeconds()
        return seconds > 0 ? Int(seconds) : nil
    }

    /// Права из карточки чата ядра (`chatRights`).
    public func canDeleteOthers(chatId: String) async -> Bool? {
        guard let rights = await api.chatRights(chatId: chatId) else { return nil }
        return rights.isOwner || rights.canDeleteAnyMessage
    }

    /// Одним `MSG_DELETE` 66. Из ленты уходят только удалённые сервером; отклонённые остаются
    /// и возвращаются (их локальные id).
    public func deleteSelection(messageIds: [String], chatId: String, forEveryone: Bool) async throws(OrbitleError) -> [String] {
        let found = messageIds.compactMap { id in (try? message(id: id)) ?? (try? message(serverId: id)) }
        var localIds = found.map(\.id)
        var serverIds = found.compactMap { message -> String? in
            guard let serverId = message.serverId, Int64(serverId) != nil else { return nil }
            return serverId
        }
        var failedLocal: [String] = []
        if !serverIds.isEmpty {
            switch await api.deleteSelection(chatId: chatId, messageIds: serverIds, forEveryone: forEveryone) {
            case .failure(let error):
                Log.warning(.messages, "Сообщения не удалены: \(error)")
                throw error.orbitleError
            case .success(let result):
                let refused = Set(result.failed)
                if !refused.isEmpty {
                    failedLocal = found.filter { $0.serverId.map(refused.contains) == true }.map(\.id)
                    localIds.removeAll { failedLocal.contains($0) }
                    serverIds.removeAll { refused.contains($0) }
                    Log.warning(.messages, "Сервер не удалил сообщений: \(refused.count)")
                }
            }
        }
        do {
            // После ожидания сервера строки перечитываются: база могла измениться.
            for id in localIds {
                if let message = try message(id: id) { modelContext.delete(message) }
            }
            try modelContext.save()
        } catch {
            throw .storageError
        }
        Log.info(.messages, "Удалено сообщений: \(localIds.count)\(forEveryone ? " у всех" : " у себя")")
        notify(chatId: chatId)
        await outgoingHandler?(.deleted(chatId: chatId, ids: localIds + serverIds))
        return failedLocal
    }

    /// Локальная лента чата после очистки переписки. Сервер уже ответил в репозитории чатов.
    public func pin(chatId: String, messageId: String) async throws(OrbitleError) {
        if case .failure(let error) = await api.pinMessage(chatId: chatId, messageId: messageId) {
            throw error.orbitleError
        }
    }

    public func loadPins(chatId: String) async throws(OrbitleError) -> [ChatPin] {
        switch await api.pinnedMessages(chatId: chatId) {
        case .success(let pins): return pins
        case .failure(let error): throw error.orbitleError
        }
    }

    public func updatePin(chatId: String, action: String, messageIds: [String], forMe: Bool, notify: Bool) async throws(OrbitleError) {
        if case .failure(let error) = await api.updatePinned(chatId: chatId, action: action, messageIds: messageIds, forMe: forMe, notify: notify) {
            throw error.orbitleError
        }
    }

    public func schedule(chatId: String, text: String, sendAt: Date) async throws(OrbitleError) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw .invalidRequest }
        if case .failure(let error) = await api.scheduleMessage(chatId: chatId, text: body, sendAtMs: sendAt.unixMillis) {
            throw error.orbitleError
        }
    }

    public func scheduled(chatId: String) async throws(OrbitleError) -> [FoundMessage] {
        switch await api.scheduledMessages(chatId: chatId) {
        case .success(let hits): return hits
        case .failure(let error): throw error.orbitleError
        }
    }

    public func sendPoll(chatId: String, title: String, answers: [String]) async throws(OrbitleError) {
        if case .failure(let error) = await api.sendPoll(chatId: chatId, title: title, answers: answers) {
            throw error.orbitleError
        }
    }

    public func votePoll(chatId: String, messageId: String, pollId: String, answerId: String) async throws(OrbitleError) {
        if case .failure(let error) = await api.votePoll(chatId: chatId, messageId: messageId, pollId: pollId, answerId: answerId) {
            throw error.orbitleError
        }
    }

    public func castVotes(chatId: String, messageId: String, pollId: String, answerIds: [String]) async throws(OrbitleError) -> PollCountUpdate {
        switch await api.castPollVotes(chatId: chatId, messageId: messageId, pollId: pollId, answerIds: answerIds) {
        case .success(let counts):
            return PollCountUpdate(pollId: counts.pollId, total: counts.total, votes: counts.votes, multiple: counts.multiple)
        case .failure(let error):
            throw error.orbitleError
        }
    }

    public func refreshPolls(chatId: String, polls: [(messageId: String, pollId: String)]) async throws(OrbitleError) -> [PollCountUpdate] {
        let refs = polls.map { CorePollRef(messageId: $0.messageId, pollId: $0.pollId) }
        switch await api.pollUpdates(chatId: chatId, polls: refs) {
        case .success(let counts):
            return counts.map { PollCountUpdate(pollId: $0.pollId, total: $0.total, votes: $0.votes, multiple: $0.multiple) }
        case .failure(let error):
            throw error.orbitleError
        }
    }

    public func applyPollCounts(chatId: String, messageId: String, update: PollCountUpdate) async {
        do {
            guard let row = try message(id: messageId) ?? message(serverId: messageId) else { return }
            var content = MessageContentCodec.decode(row.contentJSON)
            var changed = false
            content.attachments = content.attachments.map { attachment in
                guard case .poll(var poll) = attachment else { return attachment }
                guard update.pollId.isEmpty || poll.id == update.pollId else { return attachment }
                poll.total = update.total
                poll.multiple = poll.multiple || update.multiple
                poll.answers = poll.answers.map { answer in
                    var next = answer
                    if let votes = update.votes[answer.id] { next.votes = votes }
                    return next
                }
                changed = true
                return .poll(poll)
            }
            guard changed else { return }
            row.contentJSON = MessageContentCodec.encode(content)
            try modelContext.save()
            notify(chatId: chatId)
        } catch {
            Log.warning(.messages, "Счётчик опроса не записан: \(error)")
        }
    }

    public func editScheduled(chatId: String, messageId: String, text: String, sendAt: Date) async throws(OrbitleError) -> FoundMessage {
        switch await api.editScheduled(chatId: chatId, messageId: messageId, text: text, sendAtMs: sendAt.unixMillis) {
        case .success(let item): return item
        case .failure(let error): throw error.orbitleError
        }
    }

    public func cancelScheduled(chatId: String, messageIds: [String]) async throws(OrbitleError) {
        if case .failure(let error) = await api.cancelScheduled(chatId: chatId, messageIds: messageIds) {
            throw error.orbitleError
        }
    }

    public func searchInChat(chatId: String, query: String) async throws(OrbitleError) -> [FoundMessage] {
        switch await api.searchInChat(chatId: chatId, query: query) {
        case .success(let hits): return hits.filter { !$0.messageId.isEmpty }
        case .failure(let error): throw error.orbitleError
        }
    }

    public func dropLocalHistory(chatId: String) async {
        let id = chatId
        do {
            try modelContext.deleteInstances(model: SDMessage.self, where: #Predicate { $0.chatId == id })
            try modelContext.save()
            windows[chatId] = 0
            latestFetchedAt[chatId] = nil
        } catch {
            Log.warning(.messages, "Очистка ленты не сохранилась: \(error)")
        }
        notify(chatId: chatId)
    }

    /// Правка текста: сначала сервер, затем база (текст, пометка «изменено», разметка сервера).
    public func edit(messageId: String, chatId: String, text: String) async throws(OrbitleError) {
        try await sendEdit(messageId: messageId, chatId: chatId, text: text, formatting: nil)
    }

    /// Текст и весь список разметки: сервер заменяет её целиком, пустой список снимает.
    public func edit(messageId: String, chatId: String, text: String, formatting: [TextSpan]) async throws(OrbitleError) {
        try await sendEdit(messageId: messageId, chatId: chatId, text: text, formatting: formatting)
    }

    /// `formatting` `nil` — прежняя правка только текста: ядро сохраняет разметку, где она
    /// ещё ложится на новый текст.
    private func sendEdit(messageId: String, chatId: String, text: String, formatting: [TextSpan]?) async throws(OrbitleError) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw .invalidRequest }
        let stored = (try? message(id: messageId)) ?? (try? message(serverId: messageId))
        guard let stored, let serverId = stored.serverId, Int64(serverId) != nil else {
            throw .rejected("Сообщение ещё не отправлено")
        }
        let localId = stored.id
        let result = if let formatting {
            await api.editMessage(chatId: chatId, messageId: serverId, text: body, formatting: formatting)
        } else {
            await api.editMessage(chatId: chatId, messageId: serverId, text: body)
        }
        switch result {
        case .success(let record):
            do {
                guard let message = try message(id: localId) else { return }
                message.text = record.text.isEmpty ? body : record.text
                var content = Self.content(of: message)
                let fresh = MessageContentCodec.decode(record.contentJSON)
                content.formatting = fresh.formatting
                content.edited = true
                message.contentJSON = MessageContentCodec.encode(content)
                if record.updateTimeMs > 0 { message.updateTimeMs = record.updateTimeMs }
                try modelContext.save()
            } catch {
                throw .storageError
            }
            Log.info(.messages, "Сообщение \(serverId) изменено")
            notify(chatId: chatId)
        case .failure(let error):
            Log.warning(.messages, "Сообщение не изменено: \(error)")
            throw error.orbitleError
        }
    }

    /// Пересылка по серверному id. Новое сообщение сразу записывается в целевой чат.
    public func forward(messageId: String, from chatId: String, to targetChatId: String) async throws(OrbitleError) {
        let stored = (try? message(id: messageId)) ?? (try? message(serverId: messageId))
        let serverId = stored?.serverId ?? messageId
        guard Int64(serverId) != nil else { throw .rejected("Сообщение ещё не отправлено") }
        switch await api.forwardMessage(toChatId: targetChatId, fromChatId: chatId, messageId: serverId) {
        case .success(let record):
            _ = try upsert([record])
            Log.info(.messages, "Сообщение переслано в чат \(targetChatId)")
        case .failure(let error):
            Log.warning(.messages, "Сообщение не переслано: \(error)")
            throw error.orbitleError
        }
    }

    public func noteDownloaded(messageId: String, attachmentId: String, localPath: String) async {
        guard let message = try? message(id: messageId) ?? message(serverId: messageId) else { return }
        var content = Self.content(of: message)
        content = content.settingLocalPath(localPath, attachmentId: attachmentId)
        message.contentJSON = MessageContentCodec.encode(content)
        try? modelContext.save()
        notify(chatId: message.chatId)
    }

    /// Комментарии поста, от старых к новым.
    public func commentPage(chatId: String, postId: String) throws(OrbitleError) -> [Message] {
        do {
            return try fetchThread(chatId: chatId, threadOf: postId, limit: 200).map { Self.record($0).domain }
        } catch {
            throw .storageError
        }
    }

    /// Повторная отправка сообщения со статусом `failed`.
    public func retry(messageId: String) async throws(OrbitleError) {
        guard let message = try? message(id: messageId), message.status == .failed else { return }
        let withAttachments = Self.content(of: message).hasPendingUploads
        do {
            message.status = .sending
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify(chatId: message.chatId)
        await outgoingHandler?(.queued(Self.record(message)))
        if withAttachments {
            startUpload(localId: messageId)
        } else {
            await outbox?.enqueue(messageId)
        }
    }

    // MARK: Страницы (курсор по timestamp)

    /// Страница строго старше `before` (самые новые, если `nil`), от новых к старым.
    /// Сначала берётся из кэша. Если в кэше меньше `pageSize`, недостающее
    /// догружается с сервера, сохраняется и страница читается заново.
    /// Без сети возвращается то, что есть в кэше.
    public func loadMore(chatId: String, before: Date?) async throws(OrbitleError) -> [Message] {
        let local = try page(chatId: chatId, before: before)
        guard local.count < Self.pageSize else { return local.map(\.domain) }

        let cursor = local.last?.timestamp ?? before
        let started = generation
        let limit = Self.pageSize - local.count
        // Страница старше курсора — это листание вверх: её ждёт пользователь, и пауза фоновых
        // чтений после чужого too.many.requests её не держит.
        let response: Result<[MessageRecord], MaxAPIError>
        if let cursor {
            response = await api.fetchOlderMessages(chatId: chatId, before: cursor, limit: limit)
        } else {
            response = await api.fetchMessages(chatId: chatId, before: nil, limit: limit)
        }
        try ensureCurrent(started)
        switch response {
        case .success(let fetched):
            guard !fetched.isEmpty else { return local.map(\.domain) }
            let records = await withReactions(fetched, chatId: chatId)
            try ensureCurrent(started)
            try upsert(records)
            return try page(chatId: chatId, before: before).map(\.domain)
        case .failure(.offline), .failure(.cancelled):
            return local.map(\.domain)
        case .failure(let error):
            if local.isEmpty { throw error.orbitleError }
            return local.map(\.domain)
        }
    }

    /// Самые свежие сообщения чата с сервера (открытие чата и периодический опрос).
    /// Страница, пришедшая меньше `latestReuse` секунд назад, повторно не спрашивается.
    public func fetchLatest(chatId: String) async throws(OrbitleError) {
        try await latest(chatId: chatId, opened: false)
    }

    /// Просроченные фото открытого чата: одна пачка за раз, повтор того же фото не копится.
    private func refreshExpiredPhotos(chatId: String) async {
        guard photoRefreshEnabled else { return }
        let now = Date().unixMillis
        var keys: [PhotoRefreshKey] = []
        let rows = (try? modelContext.fetch(FetchDescriptor<SDMessage>(predicate: #Predicate { $0.chatId == chatId }))) ?? []
        for row in rows {
            let messageId = row.serverId ?? row.id
            for attachment in Self.content(of: row).attachments {
                guard let photo = attachment.photo, let url = photo.url, !url.isFileURL else { continue }
                guard photoURLExpired(url.absoluteString, now) else { continue }
                keys.append(PhotoRefreshKey(chatId: chatId, messageId: messageId, photoId: photo.id))
            }
        }
        photoRefreshQueue.enqueue(keys)
        guard let batch = photoRefreshQueue.take(nowMs: now) else { return }
        switch await api.refreshPhotoURLs(batch) {
        case .success(let fresh):
            applyRefreshedPhotos(fresh, chatId: chatId)
        case .failure:
            photoRefreshQueue.requeue(batch)
        }
    }

    private func applyRefreshedPhotos(_ fresh: [RefreshedPhotoURL], chatId: String) {
        let useful = fresh.filter { !$0.url.isEmpty }
        guard !useful.isEmpty else { return }
        let rows = (try? modelContext.fetch(FetchDescriptor<SDMessage>(predicate: #Predicate { $0.chatId == chatId }))) ?? []
        var changed = false
        for row in rows {
            let content = Self.content(of: row)
            let next = content.replacingPhotoURLs(useful)
            guard next != content else { continue }
            row.contentJSON = MessageContentCodec.encode(next)
            changed = true
        }
        guard changed else { return }
        try? modelContext.save()
        notify(chatId: chatId)
    }

    public func openLatest(chatId: String) async throws(OrbitleError) {
        try await latest(chatId: chatId, opened: true)
    }

    /// `opened` — пользователь только что открыл чат: страница уходит и во время паузы чтений.
    private func latest(chatId: String, opened: Bool) async throws(OrbitleError) {
        if let at = latestFetchedAt[chatId], Date().timeIntervalSince(at) < latestReuse { return }
        let started = generation
        let requestedAt = Date.now
        let result = opened
            ? await api.fetchOpenedMessages(chatId: chatId, limit: Self.pageSize)
            : await api.fetchMessages(chatId: chatId, before: nil, limit: Self.pageSize)
        switch result {
        case .success(let fetched):
            let records = await withReactions(fetched, chatId: chatId)
            try ensureCurrent(started)
            try upsert(records)
            if opened { await refreshExpiredPhotos(chatId: chatId) }
            latestFetchedAt[chatId] = Date()
            let gone = pruneMissing(chatId: chatId, page: records, requestedAt: requestedAt)
            if !gone.isEmpty { await outgoingHandler?(.deleted(chatId: chatId, ids: gone)) }
        case .failure(let error):
            throw error.orbitleError
        }
    }

    /// Сверка удалений по свежей странице сервера. Пуш удаления приходит не всегда: удаление
    /// «у себя» с другого устройства сервер другим сессиям не рассылает, а пока приложение
    /// в фоне, пуши теряются. Страница — самые свежие сообщения на момент запроса, поэтому
    /// отправленные сообщения ленты от самого старого в ней до момента запроса, которых
    /// в ней нет, удаляются (последнее удалённое новее всех оставшихся). Пустая страница —
    /// в чате ничего нет. Раньше самого старого сообщения страницы ничего не трогается,
    /// как и свои ещё не отправленные и комментарии. Возвращает id убранных.
    @discardableResult
    func pruneMissing(chatId: String, page records: [MessageRecord], requestedAt: Date) -> [String] {
        // Запас на расхождение часов: только что пришедшее сообщение не должно пропасть.
        let newest = max(records.map(\.timestamp).max() ?? .distantPast, requestedAt.addingTimeInterval(-15))
        let oldest = records.map(\.timestamp).min() ?? .distantPast
        let present = Set(records.flatMap { [$0.id, $0.serverId].compactMap { $0 } })
        let id = chatId
        let root = ""
        let sent = MessageStatus.sent.rawValue
        let descriptor = FetchDescriptor<SDMessage>(predicate: #Predicate {
            $0.chatId == id && $0.threadOf == root && $0.statusRaw == sent
                && $0.timestamp >= oldest && $0.timestamp <= newest
        })
        guard let rows = try? modelContext.fetch(descriptor) else { return [] }
        let gone = rows.filter { row in
            let key = row.serverId ?? row.id
            return Int64(key) != nil && !present.contains(key) && !present.contains(row.id)
        }
        guard !gone.isEmpty else { return [] }
        let ids = gone.flatMap { [$0.id, $0.serverId].compactMap { $0 } }
        for row in gone { modelContext.delete(row) }
        do {
            try modelContext.save()
        } catch {
            Log.info(.messages, "Удалённые на сервере сообщения не убраны: \(error)")
            return []
        }
        Log.info(.messages, "Убрано удалённых на сервере сообщений: \(gone.count)")
        notify(chatId: chatId)
        return ids
    }

    /// Страница из кэша, без обращения к серверу.
    public func page(chatId: String, before: Date?, limit: Int = pageSize) throws(OrbitleError) -> [MessageRecord] {
        do {
            return try fetchPage(chatId: chatId, before: before, limit: limit).map(Self.record)
        } catch {
            throw .storageError
        }
    }

    // MARK: Запись (вызывается из SyncEngine)

    /// Вставляет новые сообщения и обновляет существующие. Сообщение с сервера
    /// совпадает с локальным по `id` или по `serverId` (своё отправленное).
    /// Возвращает id действительно вставленных записей: повторный пуш того же
    /// сообщения ничего не вставляет и не должен второй раз увеличить счётчик.
    @discardableResult
    public func upsert(_ records: [MessageRecord]) throws(OrbitleError) -> Set<String> {
        var touched = Set<String>()
        var inserted = Set<String>()
        do {
            // Три выборки на весь пакет (по id, по серверному id и чаты), а не по три на запись.
            var byId = try messages(ids: records.map(\.id))
            var byServerId = try messages(serverIds: records.map { $0.serverId ?? $0.id })
            let chatRows = try chats(ids: records.map(\.chatId))
            for record in records {
                let key = record.serverId ?? record.id
                if byId[record.id] == nil, byServerId[key] == nil, try holdsEcho(record) {
                    heldEchoes[key] = record
                    Task { [weak self] in
                        try? await Task.sleep(for: Self.echoHold)
                        await self?.releaseEcho(key)
                    }
                    continue
                }
                if let message = byId[record.id] ?? byServerId[record.serverId ?? record.id] {
                    message.text = record.text
                    message.status = record.status
                    message.mediaId = record.mediaId
                    Self.merge(record, into: message, keepReactions: pendingReactions[message.id] != nil)
                    if !record.authorName.isEmpty { message.authorName = record.authorName }
                    if !record.authorAvatarURL.isEmpty { message.authorAvatarURL = record.authorAvatarURL }
                    if record.updateTimeMs > 0 { message.updateTimeMs = record.updateTimeMs }
                    if let serverId = record.serverId {
                        message.serverId = serverId
                        byServerId[serverId] = message
                    }
                } else {
                    let message = SDMessage(
                        id: record.id,
                        chatId: record.chatId,
                        authorId: record.authorId,
                        text: record.text,
                        timestamp: record.timestamp,
                        status: record.status,
                        mediaId: record.mediaId,
                        serverId: record.serverId ?? record.id
                    )
                    message.contentJSON = record.contentJSON
                    message.threadOf = record.threadOf
                    message.authorName = record.authorName
                    message.authorAvatarURL = record.authorAvatarURL
                    message.updateTimeMs = max(record.updateTimeMs, 0)
                    message.chat = chatRows[record.chatId]
                    modelContext.insert(message)
                    byId[record.id] = message
                    byServerId[record.serverId ?? record.id] = message
                    inserted.insert(record.id)
                }
                touched.insert(record.chatId)
            }
            try modelContext.save()
        } catch {
            throw .storageError
        }
        touched.forEach(notify(chatId:))
        return inserted
    }

    /// Своё сообщение с сервера, а в этом чате ещё отправляется своё: скорее всего, это эхо
    /// отправляемого. Сообщения с другого своего устройства (отправки здесь нет) не ждут.
    private func holdsEcho(_ record: MessageRecord) throws -> Bool {
        guard !currentUserId.isEmpty, record.authorId == currentUserId, record.threadOf.isEmpty else { return false }
        let chatId = record.chatId
        let sending = MessageStatus.sending.rawValue
        var descriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { $0.chatId == chatId && $0.statusRaw == sending })
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    /// Собеседник прочитал чат до `mark` (мс): галочки своих сообщений перерисовываются.
    public func notePeerRead(chatId: String, mark: Int64) {
        guard mark > peerReadMark(chatId) else { return }
        peerReadMarks[chatId] = mark
        notify(chatId: chatId)
    }

    private func peerReadMark(_ chatId: String) -> Int64 {
        if let known = peerReadMarks[chatId] { return known }
        let stored = (try? chats(ids: [chatId]))?[chatId]?.peerReadMark ?? 0
        peerReadMarks[chatId] = stored
        return stored
    }

    /// Ответ на отправку так и не пришёл: эхо ложится в базу обычной записью.
    private func releaseEcho(_ key: String) {
        guard let record = heldEchoes.removeValue(forKey: key) else { return }
        if (try? message(serverId: key)) != nil { return }
        _ = try? upsert([record])
    }

    /// Правка из пуша. Текст меняется всегда. Пустой фрагмент и пустое имя не затирают
    /// то, что уже лежит в базе: фасад мог прислать только новый текст.
    /// `false`, если сообщения в кэше нет — правка не становится новым сообщением.
    @discardableResult
    public func applyEdit(_ record: MessageRecord) throws(OrbitleError) -> Bool {
        do {
            guard let message = try message(id: record.id) ?? message(serverId: record.serverId ?? record.id) else { return false }
            message.text = record.text
            if let mediaId = record.mediaId { message.mediaId = mediaId }
            Self.merge(record, into: message, keepReactions: pendingReactions[message.id] != nil)
            if !record.authorName.isEmpty { message.authorName = record.authorName }
            if !record.authorAvatarURL.isEmpty { message.authorAvatarURL = record.authorAvatarURL }
            if record.updateTimeMs > 0 { message.updateTimeMs = record.updateTimeMs }
            try modelContext.save()
            notify(chatId: message.chatId)
            return true
        } catch {
            throw .storageError
        }
    }

    /// Самое свежее сообщение чата в кэше.
    public func latest(chatId: String) -> MessageRecord? {
        ((try? fetchPage(chatId: chatId, before: nil, limit: 1)) ?? []).first.map(Self.record)
    }

    /// Стирает сообщения в контексте этого актора. Выход зовёт это до удаления чатов.
    public func removeAll() throws(OrbitleError) {
        generation += 1
        reactionsAsked.removeAll()
        reactionsRetryAt.removeAll()
        latestFetchedAt.removeAll()
        for (id, task) in uploads {
            cancelledUploads.insert(id)
            task.cancel()
        }
        do {
            try modelContext.deleteInstances(model: SDMessage.self)
            try modelContext.save()
        } catch {
            throw .storageError
        }
        let chatIds = Set(observers.values.map(\.chatId))
        windows.removeAll()
        for chatId in chatIds {
            notify(chatId: chatId)
        }
    }

    public func delete(messageId: String) throws(OrbitleError) {
        do {
            guard let message = try message(id: messageId) ?? message(serverId: messageId) else { return }
            let chatId = message.chatId
            modelContext.delete(message)
            try modelContext.save()
            notify(chatId: chatId)
        } catch {
            throw .storageError
        }
    }

    // MARK: OutboxStore

    public func pendingOutgoing() -> [MessageRecord] {
        let sending = MessageStatus.sending.rawValue
        let descriptor = FetchDescriptor<SDMessage>(
            predicate: #Predicate { $0.statusRaw == sending },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        // Сообщения с вложениями отправляет своя загрузка, не очередь текстов.
        return ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { !Self.content(of: $0).hasPendingUploads }
            .map(Self.record)
    }

    public func outgoing(localId: String) -> MessageRecord? {
        guard let message = try? message(id: localId), message.status == .sending,
              !Self.content(of: message).hasPendingUploads else { return nil }
        return Self.record(message)
    }

    public func markSent(localId: String, serverId: String, timestamp: Date) async {
        heldEchoes[serverId] = nil
        guard let message = try? message(id: localId) else { return }
        // Эхо своего сообщения (пуш или опрос истории) могло прийти раньше ответа на отправку
        // и лечь отдельной строкой с серверным id. Остаётся локальная строка: экран уже
        // показывает её под локальным id.
        for echo in (try? echoes(of: serverId, except: localId)) ?? [] {
            modelContext.delete(echo)
        }
        message.status = .sent
        message.serverId = serverId
        message.timestamp = timestamp
        try? modelContext.save()
        notify(chatId: message.chatId)
        await outgoingHandler?(.sent(Self.record(message)))
    }

    public func markFailed(localId: String) async {
        guard let message = try? message(id: localId) else { return }
        message.status = .failed
        try? modelContext.save()
        notify(chatId: message.chatId)
        await outgoingHandler?(.failed(Self.record(message)))
    }

    // MARK: Внутреннее

    /// База не очищалась с начала запроса. Иначе ответ устарел, и вызов считается отменённым.
    private func ensureCurrent(_ started: Int) throws(OrbitleError) {
        guard started == generation else { throw .cancelled }
    }

    func message(id: String) throws -> SDMessage? {
        var descriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Строки с тем же серверным id, кроме `localId`.
    private func echoes(of serverId: String, except localId: String) throws -> [SDMessage] {
        let optionalId: String? = serverId
        let descriptor = FetchDescriptor<SDMessage>(
            predicate: #Predicate { $0.id == serverId || $0.serverId == optionalId }
        )
        return try modelContext.fetch(descriptor).filter { $0.id != localId }
    }

    private func message(serverId: String) throws -> SDMessage? {
        let optionalId: String? = serverId
        var descriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { $0.serverId == optionalId })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Сообщения с этими локальными id, по id.
    private func messages(ids: [String]) throws -> [String: SDMessage] {
        guard !ids.isEmpty else { return [:] }
        let wanted = Array(Set(ids))
        let rows = try modelContext.fetch(FetchDescriptor<SDMessage>(predicate: #Predicate { wanted.contains($0.id) }))
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Сообщения с этими серверными id, по серверному id.
    private func messages(serverIds: [String]) throws -> [String: SDMessage] {
        guard !serverIds.isEmpty else { return [:] }
        let wanted = Array(Set(serverIds))
        let rows = try modelContext.fetch(FetchDescriptor<SDMessage>(predicate: #Predicate { message in
            message.serverId.flatMap { serverId in wanted.contains(serverId) } ?? false
        }))
        var result: [String: SDMessage] = [:]
        for row in rows {
            guard let serverId = row.serverId, result[serverId] == nil else { continue }
            result[serverId] = row
        }
        return result
    }

    private func chats(ids: [String]) throws -> [String: SDChat] {
        guard !ids.isEmpty else { return [:] }
        let wanted = Array(Set(ids))
        let rows = try modelContext.fetch(FetchDescriptor<SDChat>(predicate: #Predicate { wanted.contains($0.id) }))
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func fetchPage(chatId: String, before: Date?, limit: Int) throws -> [SDMessage] {
        let id = chatId
        let root = ""
        let predicate: Predicate<SDMessage>
        if let cursor = before {
            predicate = #Predicate { $0.chatId == id && $0.threadOf == root && $0.timestamp < cursor }
        } else {
            predicate = #Predicate { $0.chatId == id && $0.threadOf == root }
        }
        var descriptor = FetchDescriptor<SDMessage>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    private func fetchThread(chatId: String, threadOf: String, limit: Int) throws -> [SDMessage] {
        let id = chatId
        let thread = threadOf
        var descriptor = FetchDescriptor<SDMessage>(
            predicate: #Predicate { $0.chatId == id && $0.threadOf == thread },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    private func chat(id: String) throws -> SDChat? {
        var descriptor = FetchDescriptor<SDChat>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Подписчик мог уйти раньше, чем эта задача добралась до актора: тогда его снятие
    /// уже отработало, и сохранять его нельзя.
    private func addObserver(_ id: UUID, chatId: String, threadOf: String, _ continuation: AsyncStream<[Message]>.Continuation) {
        if case .terminated = continuation.yield(snapshot(chatId: chatId, threadOf: threadOf)) { return }
        observers[id] = Observer(chatId: chatId, threadOf: threadOf, continuation: continuation)
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func notify(chatId: String) {
        let targets = observers.values.filter { $0.chatId == chatId }
        guard !targets.isEmpty else { return }
        var cache: [String: [Message]] = [:]
        for observer in targets {
            if cache[observer.threadOf] == nil {
                cache[observer.threadOf] = snapshot(chatId: chatId, threadOf: observer.threadOf)
            }
            if let messages = cache[observer.threadOf] {
                observer.continuation.yield(messages)
            }
        }
    }

    public func sharedHistory(chatId: String, limit: Int) async -> [Message] {
        let id = chatId
        let root = ""
        let empty = ""
        let link = "http"
        var descriptor = FetchDescriptor<SDMessage>(
            predicate: #Predicate {
                $0.chatId == id && $0.threadOf == root && ($0.contentJSON != empty || $0.text.contains(link))
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = max(1, limit)
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.reversed().map { Self.record($0).domain }
    }

    /// Общие медиа с сервера. В кэш не пишутся: страница из одних вложений сочла бы пропущенные
    /// между ними сообщения загруженными, и в ленте появились бы дыры.
    public func sharedMedia(chatId: String, types: [SharedAttachType], anchorId: String, forward: Int, backward: Int) async -> [Message]? {
        guard !types.isEmpty, !anchorId.isEmpty else { return nil }
        switch await api.fetchSharedMedia(chatId: chatId, types: types, anchorId: anchorId, forward: forward, backward: backward) {
        case .success(let records): return records.map(\.domain)
        case .failure: return nil
        }
    }

    /// Окно вокруг далёкого сообщения с сервера, мимо кэша: страница вне свежей истории
    /// открыла бы в кэше дыру, а `loadMore` считает сохранённую историю сплошной. Сообщения,
    /// которые уже лежат в кэше, берутся оттуда — со скачанными файлами и своими реакциями.
    public func historyAround(chatId: String, messageId: String, at: Date?, forward: Int, backward: Int) async throws(OrbitleError) -> [Message] {
        let started = generation
        let result = await api.fetchMessagesAround(chatId: chatId, messageId: messageId, at: at, forward: forward, backward: backward)
        try ensureCurrent(started)
        switch result {
        case .success(let records):
            let page = records.filter { $0.threadOf.isEmpty }
            let keys = page.map { $0.serverId ?? $0.id }
            let byId = (try? messages(ids: keys)) ?? [:]
            let byServerId = (try? messages(serverIds: keys)) ?? [:]
            let mark = peerReadMark(chatId)
            return page
                .map { record -> Message in
                    let key = record.serverId ?? record.id
                    var message = (byServerId[key] ?? byId[key]).map { Self.record($0).domain } ?? record.domain
                    message.isRead = mark > 0 && message.status == .sent && message.timestamp.unixMillis <= mark
                    return message
                }
                .sorted { $0.timestamp < $1.timestamp }
        case .failure(let error):
            throw error.orbitleError
        }
    }

    /// Основная лента — последние сообщения окна от старых к новым. Тред — хронологически.
    private func snapshot(chatId: String, threadOf: String) -> [Message] {
        if threadOf.isEmpty {
            let limit = windows[chatId] ?? Self.pageSize
            let newestFirst = (try? fetchPage(chatId: chatId, before: nil, limit: limit)) ?? []
            let mark = peerReadMark(chatId)
            return newestFirst.reversed().map { row in
                var message = Self.record(row).domain
                message.isRead = mark > 0 && message.status == .sent && message.timestamp.unixMillis <= mark
                return message
            }
        }
        let rows = (try? fetchThread(chatId: chatId, threadOf: threadOf, limit: 200)) ?? []
        return rows.map { Self.record($0).domain }
    }

    /// Фрагмент записи поверх сохранённого. Пустой фрагмент значит «фасад его не прислал»,
    /// а не «вложений больше нет». Реакции записи заменяют прежние, если она их знает
    /// (`reactionsKnown`) или несёт хоть одну. Пока своё нажатие ждёт сервера, остаются прежние.
    private static func merge(_ record: MessageRecord, into message: SDMessage, keepReactions: Bool) {
        let fresh = record.reactionsKnown && !keepReactions
        if !record.contentJSON.isEmpty {
            var content = MessageContentCodec.decode(record.contentJSON)
            let stored = Self.content(of: message)
            if keepReactions || (!record.reactionsKnown && content.reactions.isEmpty) {
                content.reactions = stored.reactions
            }
            // Счётчик комментариев приходит отдельным запросом: история его не несёт, и без
            // этого полоса комментариев пропадала бы до следующего запроса — пузырь прыгал.
            if content.comments == nil { content.comments = stored.comments }
            // Расшифровку история не несёт: текст, полученный по запросу, не пропадает.
            let transcripts = Dictionary(stored.voices.compactMap { voice in voice.transcript.map { (voice.id, $0) } }, uniquingKeysWith: { first, _ in first })
            if !transcripts.isEmpty {
                content.attachments = content.attachments.map { attachment in
                    guard case .voice(var voice) = attachment, voice.transcript == nil, let kept = transcripts[voice.id] else { return attachment }
                    voice.transcript = kept
                    return .voice(voice)
                }
            }
            message.contentJSON = MessageContentCodec.encode(content)
            message.threadOf = record.threadOf
        } else if fresh {
            // Фрагмент пуст, а реакции известны: значит, их нет.
            var content = Self.content(of: message)
            guard !content.reactions.isEmpty else { return }
            content.reactions = []
            message.contentJSON = MessageContentCodec.encode(content)
        }
    }

    /// Записывает реакции сообщения и сообщает подписчикам.
    private func saveReactions(_ reactions: [MessageReaction], localId: String, onlyIf expected: [MessageReaction]? = nil) throws(OrbitleError) {
        do {
            guard let message = try message(id: localId) else { return }
            var content = Self.content(of: message)
            // Откат не трогает то, что уже поменял кто-то другой.
            if let expected, content.reactions != expected { return }
            guard content.reactions != reactions else { return }
            content.reactions = reactions
            message.contentJSON = MessageContentCodec.encode(content)
            try modelContext.save()
            notify(chatId: message.chatId)
        } catch {
            throw .storageError
        }
    }

    private func applyReactions(localId: String, update: ReactionUpdate) throws(OrbitleError) {
        guard let message = try? message(id: localId) else { return }
        try saveReactions(update.applied(to: Self.content(of: message).reactions), localId: localId)
    }

    private static func content(of message: SDMessage) -> MessageContent {
        var content = MessageContentCodec.decode(message.contentJSON)
        if !message.threadOf.isEmpty { content.threadOf = message.threadOf }
        return content
    }

    private static func record(_ message: SDMessage) -> MessageRecord {
        let content = content(of: message)
        return MessageRecord(
            id: message.id,
            serverId: message.serverId,
            chatId: message.chatId,
            authorId: message.authorId,
            text: message.text,
            timestamp: message.timestamp,
            status: message.status,
            mediaId: message.mediaId,
            contentJSON: MessageContentCodec.encode(content),
            threadOf: content.threadOf ?? "",
            authorName: message.authorName,
            authorAvatarURL: message.authorAvatarURL,
            updateTimeMs: message.updateTimeMs
        )
    }
}
