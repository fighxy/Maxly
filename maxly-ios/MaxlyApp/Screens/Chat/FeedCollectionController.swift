import SwiftUI
import UIKit
import MaxlyPresentation

/// Строка ленты: служебная над сообщениями (загрузчик истории, подсказка, пост), сообщение,
/// служебная под ними. Идентификаторы уникальны на весь снимок: один и тот же item в двух
/// секциях роняет diffable data source.
enum FeedItemID: Hashable, Sendable {
    case top(String)
    case row(String)
    case bottom(String)

    /// Секция: 0 — служебные сверху, 1 — сообщения, 2 — служебные снизу.
    var section: Int {
        switch self {
        case .top: 0
        case .row: 1
        case .bottom: 2
        }
    }
}

/// Строка снимка и отпечаток всего, от чего зависит её высота.
struct FeedEntry {
    var id: FeedItemID
    var key: FeedLayoutKey
    /// Сторона, от которой строка въезжает и к которой уходит в анимированном снимке.
    var edge: FeedEdge = .center
}

/// Что показывает лента: сверху вниз, старое сверху.
struct FeedContent {
    var top: [FeedEntry] = []
    var rows: [FeedEntry] = []
    var bottom: [FeedEntry] = []

    var all: [FeedEntry] { top + rows + bottom }
}

/// Где лента держит место.
enum FeedFollow: Equatable {
    /// Верхняя видимая строка остаётся на своём месте экрана.
    case anchor
    /// Последняя строка у нижнего края (над полем ввода).
    case bottom
    /// Строка `id` в доле `anchor` видимой области: 0 — у верха, 1 — у низа.
    case reveal(id: String, anchor: Double)
}

/// Что ленте нужно от экрана: вид строки, оценка её высоты и события прокрутки.
@MainActor
protocol FeedCollectionSource: AnyObject {
    /// SwiftUI-содержимое строки — один и тот же вид для ячейки и для замера вне экрана.
    func feedView(for id: FeedItemID) -> AnyView
    /// Быстрая оценка высоты строки далеко от экрана.
    func feedEstimate(for id: FeedItemID, width: CGFloat) -> CGFloat
    var feedEnvironment: FeedEnvironment { get }
    /// Поля секции: строки сообщений с отступами от краёв, служебные — на всю ширину.
    func feedSectionInsets(_ section: Int) -> UIEdgeInsets
    /// Прокрутка или раскладка сдвинули строки на экране.
    func feedDidMove()
    /// Палец взял ленту (`takeover`) или отпустил её и инерция кончилась.
    func feedUserScrolling(_ moving: Bool, takeover: Bool)
    func feedWillDisplay(_ id: FeedItemID)
}

/// Лента чата и комментариев на UICollectionView: старое сверху, новое снизу, обычная
/// раскладка без переворота слоя.
///
/// Один владелец высоты строки — `FeedHeightStore`: оценка, пока строка далеко, точный замер
/// той же SwiftUI-строки вне экрана (`FeedSizer`) до показа и, в редком случае расхождения,
/// собственная высота содержимого на экране. Рамка ячейки в высоту не пишется никогда.
///
/// Один владелец `contentOffset` — эта лента, по `FeedFollow`: низ, цель перехода или
/// верхняя видимая строка. Снимок, раскладка и смещение — в одном `CATransaction` без анимации.
/// Пока палец на ленте, она держит только верхнюю видимую строку и не прилипает к низу.
@MainActor
final class FeedCollectionController: UIViewController, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching {
    static let topSection = 0
    static let rowsSection = 1
    static let bottomSection = 2

    weak var source: (any FeedCollectionSource)?
    /// Сколько раз настраивались ячейки: номер настройки в отчёте о высоте (`configure`).
    private var configurations = 0
    /// Расстояние между строками сообщений.
    var rowSpacing: CGFloat = 2
    /// Новое сообщение у низа въезжает плавно; с «Уменьшением движения» — сразу.
    var animatesAppend = true
    /// «Уменьшение движения»: новые и удалённые строки только растворяются.
    var reduceMotion = false {
        didSet { (collectionView?.collectionViewLayout as? FeedFlowLayout)?.reducesMotion = reduceMotion }
    }

    private(set) var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, FeedItemID>!
    private var content = FeedContent()
    private var keys: [FeedItemID: FeedLayoutKey] = [:]
    private var rowIndex: [String: Int] = [:]
    private let heights = FeedHeightStore()
    private lazy var sizer = FeedSizer()

    private var follow: FeedFollow = .anchor
    private var headerBottom: CGFloat?
    private var composerTop: CGFloat?
    /// Лента уже стоит на своём месте с настоящим размером.
    private(set) var hasSettled = false
    /// Последнее сообщение у нижнего края — по положению после прошлого хода.
    private var wasAtBottom = true
    private var lastBounds: CGSize = .zero
    private var lastOffsetY: CGFloat = 0
    private(set) var scrollingTowardOlder = false
    /// Идёт плавный въезд к низу: следующая поправка тоже едет, а не прыгает.
    private var animatingToBottom = false
    /// Перекладка из-за новых высот назначена на следующий ход.
    private var relayoutScheduled = false
    /// Стороны строк прежнего снимка, пока применяется анимированный: по ним уходят удалённые.
    private var edgesBefore: [FeedEdge] = []
    /// Снимок, который применит анимация движения строк.
    private var pendingSnapshot: NSDiffableDataSourceSnapshot<Int, FeedItemID>?

    // MARK: Жизненный цикл

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = false
        view.insetsLayoutMarginsFromSafeArea = false
        let flow = FeedFlowLayout()
        flow.reducesMotion = reduceMotion
        flow.edge = { [weak self] item, appearing in self?.edge(item: item, appearing: appearing) }
        flow.scrollDirection = .vertical
        flow.minimumInteritemSpacing = 0
        flow.minimumLineSpacing = 0
        // Высота каждой строки своя, из `sizeForItemAt`. `.estimated` берёт одну на секцию.
        flow.estimatedItemSize = .zero
        flow.sectionInsetReference = .fromContentInset
        let collection = UICollectionView(frame: view.bounds, collectionViewLayout: flow)
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        FeedScroll.install(collection)
        collection.delegate = self
        collection.prefetchDataSource = self
        view.addSubview(collection)
        collectionView = collection
        configureDataSource()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let collectionView else { return }
        collectionView.frame = view.bounds
        let size = collectionView.bounds.size
        guard size.width > 1, size.height > 1 else { return }
        let widthChanged = abs(size.width - lastBounds.width) > 0.5
        let heightChanged = abs(size.height - lastBounds.height) > 0.5
        lastBounds = size
        guard widthChanged || heightChanged || !hasSettled else { return }
        // Поворот или клавиатура: место держит та же строка, а у низа лента остаётся у низа.
        let anchor = widthChanged ? captureAnchor() : nil
        settle(anchor: anchor, animated: false, stickIfAtBottom: true)
    }

    // MARK: Снимок

    /// Новое содержимое и куда встать. Строки у места, где лента встанет, меряются до показа.
    /// `live` — живое изменение (не открытие и не восстановление истории): новые и удалённые
    /// строки и выросший у низа пузырь могут двигаться (`FeedMotionPlan`).
    func update(_ next: FeedContent, follow: FeedFollow, forcePosition: Bool = false, live: Bool = false) {
        loadViewIfNeeded()
        let previous = content
        let previousFollow = self.follow
        self.follow = follow
        let ready = collectionView.bounds.width > 1 && collectionView.bounds.height > 1
        let anchor = ready ? captureAnchor() : nil
        let visible = ready ? visibleRowIDs() : []
        let oldIDs = previous.all.map(\.id)
        let newIDs = next.all.map(\.id)
        var changed: [FeedItemID] = []
        var nextKeys: [FeedItemID: FeedLayoutKey] = [:]
        nextKeys.reserveCapacity(newIDs.count)
        for entry in next.all {
            nextKeys[entry.id] = entry.key
            if let old = keys[entry.id], old != entry.key { changed.append(entry.id) }
        }
        let idsChanged = oldIDs != newIDs
        let appendedAtBottom = idsChanged
            && next.rows.count > previous.rows.count
            && previous.rows.last.map { last in next.rows.contains { $0.id == last.id } } ?? false
            && next.rows.last?.id != previous.rows.last?.id
        guard idsChanged || !changed.isEmpty || previousFollow != follow || forcePosition || !hasSettled else {
            content = next
            keys = nextKeys
            return
        }
        let motion = ready
            ? plannedMotion(previous: previous, next: next, changed: changed, visible: visible, live: live, commanded: forcePosition)
            : .instant
        content = next
        keys = nextKeys
        rowIndex = Dictionary(uniqueKeysWithValues: next.rows.enumerated().compactMap { index, entry -> (String, Int)? in
            guard case .row(let id) = entry.id else { return nil }
            return (id, index)
        })
        if idsChanged {
            heights.retain(Set(newIDs.map(Self.storeID)))
        }
        let snapshot = nextSnapshot(next, idsChanged: idsChanged, changed: changed)
        switch motion {
        case .appear, .disappear:
            if let snapshot { applyMoving(snapshot, previous: previous, motion: motion, anchor: anchor) }
        case .instant, .resize:
            if let snapshot {
                FeedScroll.performWithoutAnimation { dataSource.apply(snapshot, animatingDifferences: false) }
            }
        }
        guard ready else { return }
        // Команда (кнопка «вниз», переход к цитате или закрепу) важнее инерции: лента, которая
        // ещё катится после отпущенного пальца, останавливается и встаёт по команде. Раньше
        // команда ждала конца инерции и терялась. Палец на ленте по-прежнему главнее.
        if forcePosition { stopMomentum() }
        switch motion {
        case .disappear:
            // Смещение уже поставлено в той же анимации, что и строки.
            noteGeometry()
            return
        case .resize:
            settleResized(anchor: anchor)
            return
        case .appear, .instant:
            break
        }
        // Новое сообщение у низа и кнопка «вниз» с недалёкого места — плавно, остальное — сразу.
        let near = bottomDistance.distance < bottomDistance.visible * 1.5
        let animate = animatesAppend && hasSettled && follow == .bottom && !FeedScroll.isInteracting(collectionView)
            && ((appendedAtBottom && wasAtBottom) || (previousFollow != .bottom && near))
        settle(anchor: anchor, animated: animate, stickIfAtBottom: false)
    }

    /// Снимок для нового содержимого: новый состав или перенастройка строк с новым отпечатком.
    /// `nil` — менять нечего.
    private func nextSnapshot(
        _ next: FeedContent,
        idsChanged: Bool,
        changed: [FeedItemID]
    ) -> NSDiffableDataSourceSnapshot<Int, FeedItemID>? {
        if idsChanged {
            var snapshot = NSDiffableDataSourceSnapshot<Int, FeedItemID>()
            snapshot.appendSections([Self.topSection, Self.rowsSection, Self.bottomSection])
            snapshot.appendItems(next.top.map(\.id), toSection: Self.topSection)
            snapshot.appendItems(next.rows.map(\.id), toSection: Self.rowsSection)
            snapshot.appendItems(next.bottom.map(\.id), toSection: Self.bottomSection)
            let present = Set(next.all.map(\.id))
            let reconfigure = changed.filter { present.contains($0) }
            if !reconfigure.isEmpty { snapshot.reconfigureItems(reconfigure) }
            return snapshot
        }
        guard !changed.isEmpty else { return nil }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(changed)
        return snapshot
    }

    // MARK: Движение строк

    /// Как показать этот снимок (`FeedMotionPlan`). Считается до него: что было на экране и у низа.
    private func plannedMotion(
        previous: FeedContent,
        next: FeedContent,
        changed: [FeedItemID],
        visible: Set<String>,
        live: Bool,
        commanded: Bool
    ) -> FeedMotion {
        let oldRows = previous.rows.compactMap(Self.rowID)
        let newRows = next.rows.compactMap(Self.rowID)
        let removed = Set(oldRows).subtracting(newRows)
        let distance = bottomDistance
        return FeedMotionPlan.motion(FeedMotionPlan.Input(
            live: live,
            settled: hasSettled,
            interacting: FeedScroll.isInteracting(collectionView),
            commanded: commanded,
            change: CollectionChange.between(oldRows, newRows),
            followsBottom: follow == .bottom,
            atBottom: wasAtBottom,
            nearBottom: distance.distance < distance.visible * 1.5,
            removedVisible: !removed.isEmpty && removed.isSubset(of: visible),
            resizedVisible: changed.contains { id in
                if case .row(let rowID) = id { return visible.contains(rowID) }
                return false
            }
        ))
    }

    /// Снимок с движением строк: новые въезжают, удалённые сжимаются (`FeedFlowLayout`).
    /// Новые строки меряются до снимка, иначе они въехали бы с прикидкой высоты и
    /// поправились посреди движения. При удалении смещение и зазоры ставятся в той же
    /// анимации: строки выше удалённой съезжают вместе с лентой, а не прыгают. Въезд к новому
    /// внизу — плавная прокрутка из `settle`, как и раньше.
    private func applyMoving(
        _ snapshot: NSDiffableDataSourceSnapshot<Int, FeedItemID>,
        previous: FeedContent,
        motion: FeedMotion,
        anchor: Anchor?
    ) {
        let known = Set(previous.rows.map(\.id))
        for entry in content.rows where !known.contains(entry.id) { measure(entry.id) }
        edgesBefore = previous.rows.map(\.edge)
        pendingSnapshot = snapshot
        let stick = wasAtBottom
        animateRows(duration: 0.34, bounce: 0.1) {
            guard let snapshot = self.pendingSnapshot else { return }
            self.pendingSnapshot = nil
            self.dataSource.apply(snapshot, animatingDifferences: true)
            guard motion == .disappear else { return }
            self.collectionView.layoutIfNeeded()
            _ = self.applyInsets()
            self.position(anchor: anchor, animated: false, stickIfAtBottom: stick)
        }
        edgesBefore = []
    }

    /// Строка на экране у низа сменила высоту: раскладка едет плавно, лента держится низом.
    private func settleResized(anchor: Anchor?) {
        let stick = wasAtBottom
        measureWindow(around: focusRow(anchor: anchor))
        animateRows(duration: 0.22, bounce: 0) {
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.layoutIfNeeded()
            _ = self.applyInsets()
        }
        position(anchor: anchor, animated: true, stickIfAtBottom: stick)
        noteGeometry()
    }

    /// Пружина движения строк; с «Уменьшением движения» — короткое растворение.
    private func animateRows(duration: TimeInterval, bounce: CGFloat, _ changes: @escaping () -> Void) {
        if reduceMotion {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState],
                animations: changes
            )
        } else {
            UIView.animate(
                springDuration: duration,
                bounce: bounce,
                initialSpringVelocity: 0,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: changes
            )
        }
    }

    /// Сторона строки сообщений для `FeedFlowLayout`: новые — по новому снимку, уходящие — по прежнему.
    private func edge(item: Int, appearing: Bool) -> FeedEdge? {
        if appearing {
            return content.rows.indices.contains(item) ? content.rows[item].edge : nil
        }
        return edgesBefore.indices.contains(item) ? edgesBefore[item] : nil
    }

    /// Строки сообщений, ячейки которых сейчас на экране.
    private func visibleRowIDs() -> Set<String> {
        Set(collectionView.indexPathsForVisibleItems.compactMap { path -> String? in
            guard path.section == Self.rowsSection, case .row(let id)? = dataSource.itemIdentifier(for: path) else { return nil }
            return id
        })
    }

    /// Низ шапки и верх поля ввода (или клавиатуры) в координатах окна; `nil` — ещё не измерены.
    func setChrome(headerBottom: CGFloat?, composerTop: CGFloat?) {
        guard self.headerBottom != headerBottom || self.composerTop != composerTop else { return }
        self.headerBottom = headerBottom
        self.composerTop = composerTop
        guard hasSettled, let collectionView, collectionView.bounds.height > 1 else { return }
        let anchor = captureAnchor()
        let atBottom = wasAtBottom
        let animated = animatingToBottom
        var changed = false
        FeedScroll.performWithoutAnimation {
            changed = applyInsets()
            // Палец на ленте: зазор меняется, место под пальцем — нет.
            guard changed, !animated, !FeedScroll.isInteracting(collectionView) else { return }
            position(anchor: anchor, animated: false, stickIfAtBottom: atBottom)
        }
        if changed, animated, !FeedScroll.isInteracting(collectionView) {
            position(anchor: anchor, animated: true, stickIfAtBottom: atBottom)
        }
        noteGeometry()
    }

    /// Обновить содержимое видимых строк, если `shouldRefresh` говорит, что их значения сменились.
    /// Высота от этого не меняется: всё, что её меняет, — в отпечатке строки.
    func refreshVisible(_ shouldRefresh: (FeedItemID) -> Bool) {
        guard let collectionView else { return }
        for case let cell as FeedHostingCell in collectionView.visibleCells {
            guard let id = cell.itemID, keys[id] != nil, shouldRefresh(id) else { continue }
            configure(cell, id: id)
        }
    }

    // MARK: Место ленты

    struct Anchor {
        var id: String
        /// Верх строки минус `contentOffset` до изменения.
        var topInViewport: CGFloat
    }

    /// Верхняя строка сообщений, видимая ниже шапки. Служебные строки якорем не служат:
    /// загрузчик истории стоит над вставленной страницей и увёл бы ленту.
    private func captureAnchor() -> Anchor? {
        guard let collectionView else { return nil }
        let offset = collectionView.contentOffset.y
        let readableTop = offset + collectionView.adjustedContentInset.top
        let paths = collectionView.indexPathsForVisibleItems
            .filter { $0.section == Self.rowsSection }
            .sorted { $0.item < $1.item }
        for path in paths {
            guard let id = dataSource.itemIdentifier(for: path), case .row(let rowID) = id,
                  let frame = collectionView.layoutAttributesForItem(at: path)?.frame,
                  frame.maxY > readableTop + 0.5 else { continue }
            return Anchor(id: rowID, topInViewport: frame.minY - offset)
        }
        return nil
    }

    /// Строка, вокруг которой лента встанет: цель перехода, последняя или верхняя видимая.
    private func focusRow(anchor: Anchor?) -> String? {
        let last = content.rows.last.flatMap(Self.rowID)
        switch follow {
        case .reveal(let id, _): return rowIndex[id] != nil ? id : last
        case .bottom: return last
        case .anchor: return anchor?.id ?? last
        }
    }

    /// Раскладка, зазоры и смещение одним ходом. Плавный въезд к низу — после хода: в ходе
    /// без анимации он бы не поехал.
    private func settle(anchor: Anchor?, animated: Bool, stickIfAtBottom: Bool) {
        guard let collectionView, collectionView.bounds.width > 1, collectionView.bounds.height > 1 else { return }
        let stick = stickIfAtBottom && wasAtBottom
        measureWindow(around: focusRow(anchor: anchor))
        FeedScroll.performWithoutAnimation {
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            _ = applyInsets()
            if !animated { position(anchor: anchor, animated: false, stickIfAtBottom: stick) }
        }
        if animated { position(anchor: anchor, animated: true, stickIfAtBottom: stick) }
        hasSettled = true
        noteGeometry()
    }

    private func position(anchor: Anchor?, animated: Bool, stickIfAtBottom: Bool) {
        guard let collectionView else { return }
        let interacting = FeedScroll.isInteracting(collectionView)
        var target: String?
        if case .reveal(let id, _) = follow, rowIndex[id] != nil { target = id }
        let plan = FeedSettle.plan(
            interacting: interacting,
            contentFits: !interacting && contentFits,
            stickToBottom: follow == .bottom || stickIfAtBottom,
            hasHistoryReveal: target != nil,
            pinToLatest: false,
            hasAnchor: anchor != nil
        )
        switch plan {
        case .pinBottom:
            pinBottom(animated: animated)
        case .reveal:
            if case .reveal(let id, let fraction) = follow { reveal(id: id, anchor: fraction) }
        case .restore:
            if let anchor { restore(anchor) }
        case .keep:
            break
        }
    }

    private var contentFits: Bool {
        guard let collectionView else { return false }
        let inset = collectionView.adjustedContentInset
        return FeedOffset.contentFits(
            contentHeight: Double(collectionView.contentSize.height),
            boundsHeight: Double(collectionView.bounds.height),
            insetTop: Double(inset.top),
            insetBottom: Double(inset.bottom)
        )
    }

    private var offsetRange: ClosedRange<Double> {
        let inset = collectionView.adjustedContentInset
        return FeedOffset.offsetRange(
            contentHeight: Double(collectionView.contentSize.height),
            boundsHeight: Double(collectionView.bounds.height),
            insetTop: Double(inset.top),
            insetBottom: Double(inset.bottom)
        )
    }

    private func setOffset(_ y: Double, animated: Bool) {
        let range = offsetRange
        let clamped = CGFloat(FeedOffset.clamped(y, min: range.lowerBound, max: range.upperBound))
        let point = CGPoint(x: 0, y: clamped)
        if animated {
            guard abs(collectionView.contentOffset.y - clamped) > 0.5 else { return }
            animatingToBottom = true
            collectionView.setContentOffset(point, animated: true)
        } else {
            // Без анимации, с отменой начатой: прежний въезд не продолжит ехать к старой точке.
            let wasAnimating = animatingToBottom
            animatingToBottom = false
            if wasAnimating || abs(collectionView.contentOffset.y - clamped) > 0.25 {
                collectionView.setContentOffset(point, animated: false)
            }
        }
    }

    private func pinBottom(animated: Bool) {
        setOffset(offsetRange.upperBound, animated: animated)
    }

    private func reveal(id: String, anchor: Double) {
        guard let frame = frame(ofRow: id) else { return }
        let inset = collectionView.adjustedContentInset
        let viewport = max(0, collectionView.bounds.height - inset.top - inset.bottom)
        let range = offsetRange
        let y = FeedOffset.revealing(
            rowMinY: Double(frame.minY),
            rowHeight: Double(frame.height),
            anchor: anchor,
            viewportHeight: Double(viewport),
            insetTop: Double(inset.top),
            minOffset: range.lowerBound,
            maxOffset: range.upperBound
        )
        setOffset(y, animated: false)
    }

    private func restore(_ anchor: Anchor) {
        guard let frame = frame(ofRow: anchor.id) else { return }
        let y = Double(frame.minY - anchor.topInViewport)
        // Под пальцем смещение меняется, только если строки выше действительно сдвинулись.
        guard abs(collectionView.contentOffset.y - CGFloat(y)) > 0.25 else { return }
        let range = offsetRange
        collectionView.contentOffset.y = CGFloat(FeedOffset.clamped(y, min: range.lowerBound, max: range.upperBound))
    }

    /// Зазоры шапки и поля ввода. `true` — изменились.
    @discardableResult
    private func applyInsets() -> Bool {
        let insets = FeedScroll.chromeInsets(collectionView, headerBottom: headerBottom, composerTop: composerTop)
        let old = collectionView.contentInset
        guard abs(old.top - insets.top) > 0.5 || abs(old.bottom - insets.bottom) > 0.5 else { return false }
        // Лента у самого верха остаётся у верха: иначе выросшая шапка закрыла бы первые строки.
        let restingAtTop = abs(collectionView.contentOffset.y + old.top) < 1 && !FeedScroll.isInteracting(collectionView)
        let offset = collectionView.contentOffset
        collectionView.contentInset = insets
        collectionView.verticalScrollIndicatorInsets = insets
        // Остальное место ставит ход раскладки по `FeedFollow`, а не сама смена inset.
        collectionView.contentOffset = restingAtTop ? CGPoint(x: offset.x, y: -insets.top) : offset
        return true
    }

    /// Отменить цель перехода и прилипание: ленту взял палец.
    private func userTookOver() {
        follow = .anchor
        animatingToBottom = false
    }

    // MARK: Высоты

    private static func storeID(_ id: FeedItemID) -> String {
        switch id {
        case .top(let key): "top:" + key
        case .row(let key): key
        case .bottom(let key): "bottom:" + key
        }
    }

    private static func rowID(_ entry: FeedEntry) -> String? {
        if case .row(let id) = entry.id { return id }
        return nil
    }

    private func itemWidth(section: Int) -> CGFloat {
        let insets = source?.feedSectionInsets(section) ?? .zero
        return max(1, collectionView.bounds.width - insets.left - insets.right)
    }

    private func height(for id: FeedItemID) -> CGFloat {
        guard let key = keys[id] else { return 44 }
        let width = itemWidth(section: id.section)
        if let entry = heights.entry(id: Self.storeID(id), key: key, width: Double(width)) {
            return CGFloat(entry.height)
        }
        let estimate = max(1, source?.feedEstimate(for: id, width: width) ?? 44)
        heights.store(id: Self.storeID(id), key: key, width: Double(width), height: Double(estimate), source: .estimate)
        return estimate
    }

    /// Замерить строку вне экрана, если её высота ещё только оценена. `true` — высота изменилась.
    @discardableResult
    private func measure(_ id: FeedItemID) -> Bool {
        guard let source, let key = keys[id] else { return false }
        let width = itemWidth(section: id.section)
        let storeID = Self.storeID(id)
        guard !heights.isMeasured(id: storeID, key: key, width: Double(width)) else { return false }
        let before = heights.entry(id: storeID, key: key, width: Double(width))?.height
        let measured = sizer.height(
            of: source.feedView(for: id),
            environment: source.feedEnvironment,
            width: width,
            traits: collectionView.traitCollection
        )
        guard measured > 0 else { return false }
        heights.store(id: storeID, key: key, width: Double(width), height: Double(measured), source: .measured)
        let after = heights.entry(id: storeID, key: key, width: Double(width))?.height
        return before.map { abs($0 - (after ?? $0)) >= 0.5 } ?? true
    }

    /// Служебные строки и окно строк вокруг места, где лента встанет, — до раскладки.
    private func measureWindow(around focus: String?) {
        for entry in content.top + content.bottom { measure(entry.id) }
        guard !content.rows.isEmpty else { return }
        let index = focus.flatMap { rowIndex[$0] } ?? content.rows.count - 1
        for i in FeedMeasureWindow.range(focus: index, count: content.rows.count) {
            measure(content.rows[i].id)
        }
    }

    /// Строки вперёд по прокрутке, по несколько за кадр. Сдвинувшиеся высоты выше экрана
    /// компенсируются смещением: видимое не двигается.
    private func measureAhead() {
        guard let collectionView, hasSettled, !content.rows.isEmpty else { return }
        let visible = collectionView.indexPathsForVisibleItems
            .filter { $0.section == Self.rowsSection }
            .map(\.item)
        guard let first = visible.min(), let last = visible.max() else { return }
        let order = FeedMeasureWindow.scrollOrder(
            visible: first..<(last + 1),
            count: content.rows.count,
            towardOlder: scrollingTowardOlder
        )
        var budget = FeedMeasureWindow.perScrollStep
        var moved = false
        for index in order where budget > 0 {
            let id = content.rows[index].id
            guard let key = keys[id],
                  !heights.isMeasured(id: Self.storeID(id), key: key, width: Double(itemWidth(section: Self.rowsSection))) else { continue }
            budget -= 1
            if measure(id) { moved = true }
        }
        if moved { scheduleRelayout() }
    }

    /// Перекладка после новых высот — в следующем ходе, а не внутри прокрутки или раскладки
    /// ячеек: UICollectionView нельзя перекладывать изнутри её собственной раскладки.
    private func scheduleRelayout() {
        guard !relayoutScheduled else { return }
        relayoutScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.relayoutScheduled = false
            self.relayoutKeepingPlace()
        }
    }

    /// Перекладка после смены высот: место держит цель, низ или верхняя видимая строка.
    /// Пока палец на ленте — только верхняя видимая строка.
    private func relayoutKeepingPlace() {
        guard let collectionView, hasSettled else { return }
        let anchor = captureAnchor()
        let interacting = FeedScroll.isInteracting(collectionView)
        let animated = animatingToBottom && !interacting
        FeedScroll.performWithoutAnimation {
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            _ = applyInsets()
            if interacting {
                if let anchor { restore(anchor) }
            } else if !animated {
                position(anchor: anchor, animated: false, stickIfAtBottom: false)
            }
        }
        if animated { position(anchor: anchor, animated: true, stickIfAtBottom: false) }
        noteGeometry()
    }

    /// Строка на экране сообщила свою высоту. Если она разошлась с раскладкой больше чем на точку,
    /// высота записывается за этой строкой и лента перекладывается в следующем ходе — не внутри
    /// раскладки ячейки.
    private func observed(_ height: CGFloat, for id: FeedItemID) {
        guard let collectionView, let key = keys[id], height.isFinite, height > 1,
              let path = dataSource.indexPath(for: id),
              let laid = collectionView.layoutAttributesForItem(at: path)?.frame.height,
              abs(laid - height) >= 1 else { return }
        let width = itemWidth(section: id.section)
        guard heights.store(id: Self.storeID(id), key: key, width: Double(width), height: Double(height), source: .observed) else { return }
        scheduleRelayout()
    }

    // MARK: Ячейки

    private func configureDataSource() {
        let registration = UICollectionView.CellRegistration<FeedHostingCell, FeedItemID> { [weak self] cell, _, id in
            self?.configure(cell, id: id)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }
    }

    private func configure(_ cell: FeedHostingCell, id: FeedItemID) {
        guard let source else { return }
        cell.itemID = id
        let view = source.feedView(for: id)
        let environment = source.feedEnvironment
        let report: (CGFloat) -> Void = { [weak self, weak cell] height in
            guard let self, let cell, cell.itemID == id else { return }
            self.observed(height, for: id)
        }
        // Номер настройки ячейки входит в отчёт о высоте: после переиспользования или новой
        // настройки (реакции, просмотры) строка сообщает высоту заново, даже если она та же, что
        // у прежнего содержимого. Иначе отчёт не приходил, и строка с заниженной высотой так и
        // оставалась обрезанной.
        configurations &+= 1
        let pass = configurations
        cell.contentConfiguration = UIHostingConfiguration {
            FeedCellLayout {
                view
                    .modifier(FeedEnvironmentModifier(environment: environment, sizing: false))
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: FeedCellHeight.self) { FeedCellHeight(pass: pass, height: $0.size.height) } action: {
                        report($0.height)
                    }
            }
            // Лента заходит под шапку и полоску «домой», и ячейка у края получает safe area.
            // Без этого SwiftUI сдвигал пузырь на её величину: низ обрезался краем ячейки,
            // а пузырь ездил, пока строка проезжала край. Замер (`FeedSizer`) идёт без safe area.
            .ignoresSafeArea()
        }
        .margins(.all, 0)
        .minSize(width: 0, height: 0)
    }

    // MARK: Геометрия для экрана

    /// Рамка строки сообщения в координатах ленты; `nil` — такой строки нет.
    func frame(ofRow id: String) -> CGRect? {
        guard let collectionView, let path = dataSource.indexPath(for: .row(id)) else { return nil }
        return collectionView.layoutAttributesForItem(at: path)?.frame
    }

    /// Видимые строки сообщений с рамками в координатах окна, сверху вниз.
    func visibleRowFrames() -> [(id: String, frame: CGRect, index: Int)] {
        guard let collectionView else { return [] }
        return collectionView.indexPathsForVisibleItems
            .filter { $0.section == Self.rowsSection }
            .sorted { $0.item < $1.item }
            .compactMap { path -> (id: String, frame: CGRect, index: Int)? in
                guard let item = dataSource.itemIdentifier(for: path), case .row(let id) = item,
                      let attributes = collectionView.layoutAttributesForItem(at: path) else { return nil }
                return (id: id, frame: collectionView.convert(attributes.frame, to: nil), index: path.item)
            }
    }

    /// Рамка служебной строки в координатах окна, если она на экране.
    func visibleFrame(of id: FeedItemID) -> CGRect? {
        guard let collectionView, let path = dataSource.indexPath(for: id),
              let attributes = collectionView.layoutAttributesForItem(at: path) else { return nil }
        let frame = collectionView.convert(attributes.frame, to: nil)
        guard let window = FeedScroll.windowFrame(collectionView), frame.intersects(window) else { return nil }
        return frame
    }

    /// Расстояние от видимого низа до конца ленты в точках и высота видимой части.
    var bottomDistance: (distance: Double, visible: Double) {
        guard let collectionView else { return (0, 0) }
        let inset = collectionView.adjustedContentInset
        let distance = ScrollDownVisibility.distanceFromBottom(
            contentHeight: Double(collectionView.contentSize.height),
            offsetY: Double(collectionView.contentOffset.y),
            viewportHeight: Double(collectionView.bounds.height),
            insetTop: Double(inset.top),
            insetBottom: Double(inset.bottom)
        )
        return (distance, Double(max(0, collectionView.bounds.height - inset.top - inset.bottom)))
    }

    /// Видимая часть ленты (ниже шапки, выше поля ввода) в координатах окна.
    var readableFrame: CGRect? {
        guard let collectionView, let frame = FeedScroll.windowFrame(collectionView) else { return nil }
        return frame.inset(by: UIEdgeInsets(top: collectionView.adjustedContentInset.top, left: 0, bottom: collectionView.adjustedContentInset.bottom, right: 0))
    }

    var isInteracting: Bool {
        collectionView.map(FeedScroll.isInteracting) ?? false
    }

    private func noteGeometry() {
        wasAtBottom = bottomDistance.distance <= 24
        source?.feedDidMove()
    }

    // MARK: UICollectionViewDelegateFlowLayout

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = itemWidth(section: indexPath.section)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return CGSize(width: width, height: 1) }
        return CGSize(width: width, height: max(1, height(for: id)))
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        section == Self.rowsSection ? rowSpacing : 0
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        source?.feedSectionInsets(section) ?? .zero
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        source?.feedWillDisplay(id)
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        // Строки, к которым подъезжает лента, меряются заранее — по несколько за раз.
        var budget = FeedMeasureWindow.perScrollStep
        var moved = false
        for path in indexPaths where budget > 0 {
            guard let id = dataSource.itemIdentifier(for: path), let key = keys[id],
                  !heights.isMeasured(id: Self.storeID(id), key: key, width: Double(itemWidth(section: path.section))) else { continue }
            budget -= 1
            if measure(id) { moved = true }
        }
        if moved { scheduleRelayout() }
    }

    /// Остановить прокрутку по инерции, если палец уже отпущен.
    private func stopMomentum() {
        guard let collectionView, collectionView.isDecelerating, !collectionView.isTracking else { return }
        collectionView.setContentOffset(collectionView.contentOffset, animated: false)
        // Конец инерции экран узнаёт после хода обновления SwiftUI, а не внутри него.
        Task { @MainActor [weak self] in
            guard let self, let collectionView = self.collectionView, !FeedScroll.isInteracting(collectionView) else { return }
            self.source?.feedUserScrolling(false, takeover: false)
        }
    }

    // MARK: UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y
        if abs(y - lastOffsetY) > 1 {
            scrollingTowardOlder = y < lastOffsetY
            lastOffsetY = y
        }
        if FeedScroll.isInteracting(scrollView) { measureAhead() }
        noteGeometry()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        userTookOver()
        source?.feedUserScrolling(true, takeover: true)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        source?.feedUserScrolling(false, takeover: false)
        noteGeometry()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        source?.feedUserScrolling(false, takeover: false)
        noteGeometry()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        animatingToBottom = false
        noteGeometry()
    }
}
