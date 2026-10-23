import QuartzCore
import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Окружение SwiftUI для строк ленты.
///
/// Ячейки UICollectionView — отдельные хосты SwiftUI: свои ключи окружения через границу UIKit
/// сами не проходят. Без этого пузырь в ячейке не знал приватного режима, меню экрана чата,
/// анимодзи и обоев. Те же значения получает замер высоты вне экрана, иначе он мерил бы
/// другую строку (например, без закрытия приватного режима).
struct FeedEnvironment {
    var privateMode: PrivateModeDisplay = .visible
    var dynamicTypeSize: DynamicTypeSize = .large
    var animojiCatalog: [String: URL] = [:]
    var reactionBurst: ReactionBurstHost?
    var messageMenuPresenter: MessageMenuPresenter?
    var chatWallpaper: ChatWallpaper = .standard
    var chatHasPhotoWallpaper = false
    var imageURLSizing: any ImageURLSizing = PassthroughImageURLSizing()
    var gifAutoplay = true
}

struct FeedEnvironmentModifier: ViewModifier {
    let environment: FeedEnvironment
    /// Строка собрана для замера: без реакции-вспышки, меню и плееров.
    let sizing: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.privateMode, environment.privateMode)
            .environment(\.animojiCatalog, environment.animojiCatalog)
            .environment(\.reactionBurst, sizing ? nil : environment.reactionBurst)
            .environment(\.messageMenuPresenter, sizing ? nil : environment.messageMenuPresenter)
            .environment(\.chatWallpaper, environment.chatWallpaper)
            .environment(\.chatHasPhotoWallpaper, environment.chatHasPhotoWallpaper)
            .environment(\.imageURLSizing, environment.imageURLSizing)
            .environment(\.gifAutoplay, sizing ? false : environment.gifAutoplay)
            .environment(\.isFeedSizing, sizing)
            .dynamicTypeSize(environment.dynamicTypeSize)
    }
}

/// Ячейка строки ленты: SwiftUI через `UIHostingConfiguration`. Высоту ей задаёт лента
/// (`FeedHeightStore`), содержимое прижато к верху и не рисуется за её пределами.
final class FeedHostingCell: UICollectionViewCell {
    /// Какая строка сейчас в ячейке: поздний отчёт о высоте от прежней строки отбрасывается.
    var itemID: FeedItemID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = true
        contentView.clipsToBounds = true
        // Лента заходит под шапку и полоску «домой»: поля ячейки не зависят от safe area экрана,
        // иначе строка у края сдвигалась на её величину (SwiftUI-часть — в `configure`).
        insetsLayoutMarginsFromSafeArea = false
        contentView.insetsLayoutMarginsFromSafeArea = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        itemID = nil
    }
}

/// Высота строки в отчёте ячейки и номер настройки, при которой она снята.
struct FeedCellHeight: Equatable {
    var pass: Int
    var height: CGFloat
}

/// Содержимое ячейки ленты: во всю ширину, своей высоты и прижато к верху. Пока лента не
/// переложила строку под настоящую высоту, лишнее обрезается снизу. Обычная рамка с
/// `maxHeight: .infinity` при содержимом выше ячейки становилась выше неё, и хост ячейки
/// ставил её по центру — у пузыря срезался верх.
struct FeedCellLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.first?.sizeThatFits(.unspecified).width ?? 0
        let height = proposal.height
            ?? subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)).height ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil)
            )
        }
    }
}

/// Замер высоты SwiftUI-строки вне экрана — тем же видом и окружением, что у ячейки, при
/// ширине ячейки. Так высота известна до показа: пузырь не обрезается и не наползает на соседа,
/// а лента не прыгает, когда строка появляется.
@MainActor
final class FeedSizer {
    private let host: UIHostingController<AnyView>

    init() {
        host = UIHostingController(rootView: AnyView(EmptyView()))
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
    }

    func height(of view: AnyView, environment: FeedEnvironment, width: CGFloat, traits: UITraitCollection) -> CGFloat {
        guard width > 1 else { return 0 }
        // Размер шрифта, жирный текст и масштаб экрана — как у ячеек ленты.
        host.traitOverrides.preferredContentSizeCategory = traits.preferredContentSizeCategory
        host.traitOverrides.legibilityWeight = traits.legibilityWeight
        host.traitOverrides.displayScale = traits.displayScale
        host.traitOverrides.layoutDirection = traits.layoutDirection
        host.rootView = AnyView(
            view
                .modifier(FeedEnvironmentModifier(environment: environment, sizing: true))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width)
        )
        let fitted = host.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        // Освободить строку: её изображения и анимации не держатся в памяти до следующего замера.
        host.rootView = AnyView(EmptyView())
        guard fitted.height.isFinite, fitted.height > 0, fitted.height < 20_000 else { return 0 }
        return fitted.height
    }
}

@MainActor
enum FeedScroll {
    static func isInteracting(_ scroll: UIScrollView) -> Bool {
        scroll.isTracking || scroll.isDragging || scroll.isDecelerating
    }

    /// Рамка ленты в окне. Вне окна `convert` возвращает bounds, и смещение −6 выглядит как верх экрана.
    static func windowFrame(_ view: UIView) -> CGRect? {
        guard view.window != nil else { return nil }
        return view.convert(view.bounds, to: nil)
    }

    struct WindowChrome {
        var safeTop: CGFloat
        var safeBottom: CGFloat
        var height: CGFloat
    }

    static func windowChrome(_ view: UIView? = nil) -> WindowChrome {
        let window = view?.window ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        let safe = window?.safeAreaInsets ?? .zero
        return WindowChrome(safeTop: safe.top, safeBottom: safe.bottom, height: window?.bounds.height ?? 0)
    }

    /// Полный content inset ленты: перекрытие шапки и поля ввода самой лентой плюс небольшой
    /// зазор (`FeedOffset.chromeInsets`). `contentInsetAdjustmentBehavior = .never`: safe area
    /// сюда второй раз не прибавляется. Короткая лента получает запас сверху и садится на поле ввода.
    static func chromeInsets(_ collection: UICollectionView, headerBottom: CGFloat?, composerTop: CGFloat?) -> UIEdgeInsets {
        let window = windowChrome(collection)
        let safe = collection.safeAreaInsets
        let unresolvedHeader = FeedOffset.unresolvedHeader(safeTop: Double(safe.top), windowTop: Double(window.safeTop))
        let unresolvedComposer = FeedOffset.unresolvedComposer(safeBottom: Double(safe.bottom), windowBottom: Double(window.safeBottom))
        let headerOverlap: Double
        let composerOverlap: Double
        if let frame = windowFrame(collection), frame.height > 1, window.height > 1 {
            headerOverlap = FeedOffset.headerOverlap(
                frameMinY: Double(frame.minY),
                frameMaxY: Double(frame.maxY),
                headerBottom: headerBottom.map(Double.init),
                unresolved: unresolvedHeader
            )
            composerOverlap = FeedOffset.composerOverlap(
                frameMinY: Double(frame.minY),
                frameMaxY: Double(frame.maxY),
                frameReachesScreenBottom: frame.maxY >= window.height - 1,
                composerTop: composerTop.map(Double.init),
                unresolved: unresolvedComposer
            )
        } else {
            headerOverlap = unresolvedHeader
            composerOverlap = unresolvedComposer
        }
        let resolved = FeedOffset.chromeInsets(
            boundsHeight: Double(collection.bounds.height),
            contentHeight: Double(collection.collectionViewLayout.collectionViewContentSize.height),
            headerOverlap: headerOverlap,
            composerOverlap: composerOverlap
        )
        return UIEdgeInsets(top: CGFloat(resolved.top), left: 0, bottom: CGFloat(resolved.bottom), right: 0)
    }

    /// Лента под полупрозрачной шапкой и полем ввода, зазор задаётся вручную.
    /// Стартовый inset берётся из окна, чтобы первый кадр не начинался под шапкой.
    static func install(_ collection: UICollectionView) {
        collection.backgroundColor = .clear
        collection.clipsToBounds = true
        collection.alwaysBounceVertical = true
        collection.keyboardDismissMode = .interactive
        collection.scrollsToTop = false
        collection.contentInsetAdjustmentBehavior = .never
        collection.insetsLayoutMarginsFromSafeArea = false
        collection.automaticallyAdjustsScrollIndicatorInsets = false
        collection.showsVerticalScrollIndicator = true
        hideSystemEdgeEffects(collection)
        let window = windowChrome()
        let seed = FeedOffset.chromeInsets(
            boundsHeight: 0,
            contentHeight: 0,
            headerOverlap: FeedOffset.unresolvedHeader(safeTop: 0, windowTop: Double(window.safeTop)),
            composerOverlap: FeedOffset.unresolvedComposer(safeBottom: 0, windowBottom: Double(window.safeBottom))
        )
        let insets = UIEdgeInsets(top: CGFloat(seed.top), left: 0, bottom: CGFloat(seed.bottom), right: 0)
        collection.contentInset = insets
        collection.verticalScrollIndicatorInsets = insets
        collection.contentOffset = CGPoint(x: 0, y: -insets.top)
    }

    /// Системный край прокрутки на новых iOS затемняет верх и низ ленты поверх своего размытия.
    static func hideSystemEdgeEffects(_ collection: UIScrollView) {
        if #available(iOS 26.0, *) {
            collection.topEdgeEffect.isHidden = true
            collection.bottomEdgeEffect.isHidden = true
            collection.leftEdgeEffect.isHidden = true
            collection.rightEdgeEffect.isHidden = true
        }
    }

    /// Снимок и смещение в одном ходе, без анимации слоя: иначе вставка двигает место под пальцем.
    static func performWithoutAnimation(_ work: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation(work)
        CATransaction.commit()
    }
}
