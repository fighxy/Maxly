import Foundation
import Observation
import OrbitleDomain

/// Открытый просмотр историй. `queue` — владельцы по порядку листания, `stories` — истории
/// текущего владельца от старых к новым (пусто, пока грузятся). `epoch` растёт при каждом
/// запуске истории: экран по нему заново запускает таймер, даже если история та же.
public struct StoryViewerState: Equatable, Sendable {
    public var queue: [StoryRing]
    public var ownerIndex: Int
    public var stories: [Story] = []
    public var storyIndex = 0
    public var isLoading = true
    /// Свои истории: в просмотре есть «Удалить».
    public var isOwn = false
    public var isDeleting = false
    public var epoch = 0

    public var ring: StoryRing { queue[ownerIndex] }
    public var story: Story? { stories.indices.contains(storyIndex) ? stories[storyIndex] : nil }
}

/// Истории: лента колец над списком чатов, кольца на аватарах, просмотр и публикация. Одна
/// модель на всё приложение после входа: список, шапка чата и профиль видят одни и те же
/// кольца. Порядок колец и продолжение с первой непросмотренной истории — как у эталонного
/// клиента (Komet `feature/FullStack`).
@MainActor
@Observable
public final class StoriesViewModel {
    /// Своё кольцо, если есть истории: плитка «Ваша история».
    public private(set) var own: StoryRing?
    /// Чужие кольца ленты: сначала непросмотренные, затем свежие.
    public private(set) var rings: [StoryRing] = []
    /// Кольца владельцев вне ленты (открытый профиль или чат).
    public private(set) var peers: [String: StoryRing] = [:]
    public private(set) var viewer: StoryViewerState?
    /// Идёт публикация: доля загруженного файла.
    public private(set) var publishProgress: Double?
    /// Сообщение для плашки; экран сбрасывает его после показа.
    public var message: String?
    /// Свой id: по нему личный чат находит собеседника. Пусто, пока не известен.
    public private(set) var myId = ""

    @ObservationIgnored private let repository: any StoriesRepository
    @ObservationIgnored private let now: () -> Date
    /// Кольца ленты по id владельца, включая своё.
    @ObservationIgnored private var feed: [String: StoryRing] = [:]
    /// Владельцы вне ленты, о которых уже спрашивали.
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private var cache: [String: [Story]] = [:]
    /// Истории, уже отмеченные просмотренными за этот просмотр.
    @ObservationIgnored private var marked: Set<String> = []
    /// Сколько историй владельца было просмотрено, когда его открыли: их не отмечаем снова.
    @ObservationIgnored private var seenAtOpen: [String: Int] = [:]
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var pending: [Task<Void, Never>] = []

    public init(repository: any StoriesRepository, now: @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
    }

    /// Подписка на пуши колец. Повторный вызов ничего не делает.
    public func start() {
        guard listening == nil else { return }
        let stream = repository.updates()
        listening = Task { [weak self] in
            for await ring in stream {
                self?.apply(ring)
            }
        }
    }

    public func stop() {
        listening?.cancel()
        listening = nil
    }

    /// Первая страница ленты заново. Ошибка не показывается: лента просто остаётся прежней.
    public func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        myId = await repository.currentUserId()
        guard let list = try? await repository.feed() else { return }
        var next: [String: StoryRing] = [:]
        for ring in list where !ring.isEmpty { next[ring.owner.id] = ring }
        feed = next
        publishState()
    }

    /// Кольцо владельца `ownerId` — из ленты или открытого профиля; `nil`, если историй нет.
    public func ring(of ownerId: String?) -> StoryRing? {
        guard let ownerId, !ownerId.isEmpty, ownerId != "0" else { return nil }
        if let own, own.owner.id == ownerId { return own }
        return rings.first { $0.owner.id == ownerId } ?? peers[ownerId]
    }

    /// Кольцо на аватаре чата. У человека — по id собеседника, у группы и канала — если владелец того же типа.
    public func ring(of ownerId: String?, kind: StoryOwner.Kind) -> StoryRing? {
        guard let ring = ring(of: ownerId), StoryStripMotion.ringMatches(ring, kind: kind) else { return nil }
        return ring
    }

    /// Собеседник личного чата: id диалога — это `мой id ^ id собеседника`, как и у эталонного
    /// клиента. У «Избранного» собеседника нет.
    public func peer(ofChat chatId: String, type: ChatType) -> String? {
        guard type == .private, chatId != "0", let chat = Int64(chatId), let me = Int64(myId), me != 0 else { return nil }
        let peer = chat ^ me
        return peer > 0 && peer != me ? String(peer) : nil
    }

    /// Кольцо человека вне ленты. Группа и канал запрашиваются с их типом.
    public func loadRing(_ ownerId: String?, kind: StoryOwner.Kind = .user) async {
        guard let ownerId, !ownerId.isEmpty, ownerId != "0" else { return }
        let key = "\(kind.rawValue):\(ownerId)"
        guard feed[ownerId] == nil, !requested.contains(key) else { return }
        requested.insert(key)
        do {
            let reply = try await repository.stories(owner: StoryOwner(id: ownerId, kind: kind))
            cache[ownerId] = reply.stories.filter { $0.media != nil }
            peers[ownerId] = reply.ring
            publishState()
        } catch {
            requested.remove(key)
        }
    }

    /// Открывает истории `ownerId`: свои — только свои, чужие — с листанием по ленте.
    public func open(_ ownerId: String) {
        guard let ring = ring(of: ownerId) else { return }
        let isOwn = ownerId == myId
        var queue = [ring]
        var index = 0
        if !isOwn, let found = rings.firstIndex(where: { $0.owner.id == ownerId }) {
            queue = rings
            index = found
        }
        marked.removeAll()
        seenAtOpen.removeAll()
        viewer = StoryViewerState(queue: queue, ownerIndex: index, isOwn: isOwn)
        showOwner(index)
    }

    /// Следующая история; после последней — следующий владелец, после последнего — закрытие.
    public func next() {
        guard let viewer else { return }
        if viewer.storyIndex + 1 < viewer.stories.count { start(viewer.storyIndex + 1) } else { nextOwner() }
    }

    /// Предыдущая история; на первой — предыдущий владелец.
    public func previous() {
        guard let viewer else { return }
        if viewer.storyIndex > 0 { start(viewer.storyIndex - 1) } else { previousOwner() }
    }

    public func nextOwner() {
        guard let viewer else { return }
        if viewer.ownerIndex + 1 < viewer.queue.count { showOwner(viewer.ownerIndex + 1) } else { close() }
    }

    public func previousOwner() {
        guard let viewer else { return }
        if viewer.ownerIndex > 0 { showOwner(viewer.ownerIndex - 1) } else { start(0) }
    }

    public func close() {
        loading?.cancel()
        loading = nil
        viewer = nil
    }

    /// Удаляет текущую свою историю и идёт к следующей; последнюю — закрывает просмотр.
    public func deleteCurrent() async {
        guard let current = viewer, let story = current.story, current.isOwn, !current.isDeleting else { return }
        viewer?.isDeleting = true
        do {
            try await repository.delete(storyIds: [story.id])
        } catch {
            viewer?.isDeleting = false
            fail(error, fallback: "Не удалось удалить историю")
            return
        }
        let ownerId = story.owner.id
        let left = current.stories.filter { $0.id != story.id }
        cache[ownerId] = left
        shrink(ownerId)
        guard viewer != nil else { return }
        if left.isEmpty {
            close()
        } else {
            viewer?.stories = left
            viewer?.isDeleting = false
            start(min(current.storyIndex, left.count - 1))
        }
    }

    /// Публикует историю. Пока идёт загрузка, `publishProgress` не `nil`.
    public func publish(_ story: OutgoingStory, audience: StoryAudience) async {
        guard publishProgress == nil else { return }
        publishProgress = 0
        let ring: StoryRing?
        do {
            ring = try await repository.publish(story, audience: audience) { [weak self] value in
                Task { @MainActor in
                    guard let self, self.publishProgress != nil else { return }
                    self.publishProgress = value
                }
            }
        } catch {
            publishProgress = nil
            fail(error, fallback: "Не удалось опубликовать историю")
            return
        }
        if myId.isEmpty { myId = await repository.currentUserId() }
        let me = myId
        if !me.isEmpty {
            cache[me] = nil
            let old = feed[me]
            feed[me] = ring ?? StoryRing(
                owner: StoryOwner(id: me),
                name: old?.name ?? "",
                avatarURL: old?.avatarURL,
                updatedAt: now(),
                total: (old?.total ?? 0) + 1,
                read: old?.read ?? 0
            )
        }
        publishProgress = nil
        message = "История опубликована"
        publishState()
    }

    /// Дождаться фоновой работы (загрузка историй, отметки). Для тестов.
    public func settle() async {
        while !pending.isEmpty {
            let tasks = pending
            pending.removeAll()
            for task in tasks { await task.value }
        }
    }

    // MARK: Внутреннее

    /// Пуш кольца: пустое убирается, остальное встаёт в ленту.
    func apply(_ ring: StoryRing) {
        let id = ring.owner.id
        if ring.isEmpty {
            feed[id] = nil
            peers[id] = nil
            cache[id] = nil
        } else {
            if feed[id]?.total != ring.total { cache[id] = nil }
            feed[id] = Self.withProfile(ring, known: feed[id] ?? peers[id])
            peers[id] = nil
        }
        publishState()
    }

    private func showOwner(_ index: Int) {
        guard let current = viewer, current.queue.indices.contains(index) else { return }
        let ring = current.queue[index]
        let ownerId = ring.owner.id
        loading?.cancel()
        let cached = cache[ownerId]
        viewer?.ownerIndex = index
        viewer?.stories = cached ?? []
        viewer?.storyIndex = 0
        viewer?.isLoading = cached == nil
        if let cached {
            begin(ring, cached)
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            let reply: OwnerStories
            do {
                reply = try await self.repository.stories(owner: ring.owner)
            } catch {
                if Task.isCancelled { return }
                self.fail(error, fallback: "Не удалось загрузить истории")
                self.close()
                return
            }
            if Task.isCancelled { return }
            let stories = reply.stories.filter { $0.media != nil }
            self.cache[ownerId] = stories
            if let fresh = reply.ring { self.replaceRing(Self.withProfile(fresh, known: ring)) }
            guard self.viewer?.ownerIndex == index else { return }
            self.viewer?.stories = stories
            self.viewer?.isLoading = false
            self.begin(self.viewer?.ring ?? ring, stories)
        }
        loading = task
        pending.append(task)
    }

    /// Первая история владельца: первая непросмотренная, если такая есть. Пустого — пропускаем.
    private func begin(_ ring: StoryRing, _ stories: [Story]) {
        guard !stories.isEmpty else {
            nextOwner()
            return
        }
        if seenAtOpen[ring.owner.id] == nil { seenAtOpen[ring.owner.id] = ring.read }
        start(Self.resumeIndex(ring, count: stories.count))
    }

    private func start(_ index: Int) {
        guard let current = viewer, !current.stories.isEmpty else { return }
        let i = min(max(index, 0), current.stories.count - 1)
        viewer?.storyIndex = i
        viewer?.epoch += 1
        viewer?.isLoading = false
        markSeen(current.ring, current.stories[i], index: i)
    }

    /// Отмечает историю просмотренной один раз; уже просмотренные до открытия не отмечаются.
    private func markSeen(_ ring: StoryRing, _ story: Story, index: Int) {
        guard story.owner.id != myId, index >= (seenAtOpen[ring.owner.id] ?? 0), !marked.contains(story.id) else { return }
        marked.insert(story.id)
        // Кольцо гаснет сразу, не дожидаясь ответа сервера.
        var current = self.ring(of: ring.owner.id) ?? ring
        let previousRead = current.read
        current.read = min(current.read + 1, current.total)
        replaceRing(current)
        let repository = repository
        let ownerId = ring.owner.id
        pending.append(Task { [weak self] in
            do {
                try await repository.markSeen(owner: story.owner, storyId: story.id)
            } catch {
                guard let self else { return }
                self.marked.remove(story.id)
                guard var now = self.ring(of: ownerId), now.read == min(previousRead + 1, now.total) else { return }
                now.read = previousRead
                self.replaceRing(now)
            }
        })
    }

    /// Свои истории после удаления одной: кольцо короче, пустое — убирается.
    private func shrink(_ ownerId: String) {
        guard var ring = feed[ownerId] else { return }
        ring.total = max(0, ring.total - 1)
        ring.read = min(ring.read, ring.total)
        feed[ownerId] = ring.isEmpty ? nil : ring
        publishState()
    }

    private func replaceRing(_ ring: StoryRing) {
        let id = ring.owner.id
        if feed[id] != nil {
            feed[id] = ring
        } else if peers[id] != nil {
            peers[id] = ring
        } else {
            return
        }
        publishState()
    }

    private func publishState() {
        let me = myId
        rings = Self.order(feed.values.filter { $0.owner.id != me })
        own = me.isEmpty ? nil : feed[me]
        if var current = viewer {
            current.queue = current.queue.map { feed[$0.owner.id] ?? peers[$0.owner.id] ?? $0 }
            viewer = current
        }
    }

    private func fail(_ error: Error, fallback: String) {
        let category = (error as? OrbitleError) ?? .unknown
        guard category != .cancelled else { return }
        message = category == .unknown ? fallback : (category.userMessage ?? fallback)
    }

    /// Сначала непросмотренные, затем свежие.
    public static func order<S: Sequence>(_ rings: S) -> [StoryRing] where S.Element == StoryRing {
        rings.sorted { a, b in
            if a.hasUnread != b.hasUnread { return a.hasUnread }
            return a.updatedAt > b.updatedAt
        }
    }

    /// С первой непросмотренной истории, если просмотрена часть; иначе с начала.
    public static func resumeIndex(_ ring: StoryRing, count: Int) -> Int {
        ring.read >= 1 && ring.read < count ? ring.read : 0
    }

    private static func withProfile(_ ring: StoryRing, known: StoryRing?) -> StoryRing {
        guard let known else { return ring }
        var merged = ring
        if merged.name.isEmpty { merged.name = known.name }
        if merged.avatarURL == nil { merged.avatarURL = known.avatarURL }
        return merged
    }
}
