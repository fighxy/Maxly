import AVFoundation
import AVKit
import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Просмотр фото и видео, как в Telegram и WhatsApp.
///
/// - Открывается полётом кадра из плитки в ленте и закрывается полётом обратно; плитка, которой
///   нет на экране (или фото увеличено, повёрнуто, экран боком), — просто гаснет.
/// - Касание прячет и показывает шапку (кто, когда, «3 из 7»), подпись, ленту миниатюр альбома и
///   кнопки вместе со строкой состояния; у играющего ролика они уходят сами (`MediaViewerChrome`).
/// - Смахивание вверх или вниз ведёт кадр за пальцем, фон гаснет; далеко или броском —
///   закрыть, иначе кадр возвращается (`MediaDismissRule`).
/// - Фото: щипок и двойное касание увеличивают, поворот четвертями.
/// - Видео: свой плеер — полоса с подгруженной частью, двойное касание у края ±10 с,
///   удержание — 2×, скорость, звук; поток не открылся — ролик скачивается с прогрессом.
/// - Просмотр поворачивается вслед за телефоном, остальное приложение — в портрете.
///
/// Показывать через `mediaViewerCover`: окно появляется без системной анимации и с прозрачным
/// фоном, полёт рисует сам просмотр.
struct MediaViewer: View {
    let request: MediaViewerRequest
    /// Скачать ролик целиком, если поток не открылся; доля загрузки — во втором аргументе.
    var download: (MediaSlide, @escaping @MainActor (Double) -> Void) async -> URL? = { slide, _ in slide.playURL }
    /// Итог сохранения («Фото сохранено в «Фото»») — капсула внизу.
    var notice: String?
    var isSaving = false
    /// Сохранить открытый кадр или поделиться им: id слайда и куда.
    var onSave: ((String, SaveTarget) -> Void)?
    /// «Перейти к сообщению»: просмотр закрывается, лента едет к сообщению.
    var onShowInChat: (() -> Void)?
    let onClose: () -> Void

    @State private var selection: String?
    @State private var zoomed = false
    @State private var scrubbing = false
    @State private var chrome = MediaViewerChrome()
    /// Поворот фото четвертями по часовой, свой у каждого кадра.
    @State private var turns: [String: Int] = [:]
    /// Смахивание: насколько увели кадр и решено ли, что жест вертикальный.
    @State private var dragOffset: CGFloat = 0
    @State private var dragAxis: Axis?
    /// Открытие и закрытие: доля «открытости» 0…1 и летящий кадр, если он есть.
    @State private var phase = Phase.opening
    @State private var progress: CGFloat = 0
    @State private var hero: Hero?
    /// Экран просмотра в координатах окна (рамки плиток — в них же).
    @State private var screen: CGRect = .zero
    /// Что сделать, когда просмотр закроется.
    @State private var afterClose: (() -> Void)?

    private enum Phase { case opening, open, closing }

    /// Кадр, летящий между плиткой и просмотром.
    private struct Hero {
        let image: UIImage
        let source: CGRect
        let cornerRadius: CGFloat
    }

    init(
        request: MediaViewerRequest,
        download: @escaping (MediaSlide, @escaping @MainActor (Double) -> Void) async -> URL? = { slide, _ in slide.playURL },
        notice: String? = nil,
        isSaving: Bool = false,
        onSave: ((String, SaveTarget) -> Void)? = nil,
        onShowInChat: (() -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.request = request
        self.download = download
        self.notice = notice
        self.isSaving = isSaving
        self.onSave = onSave
        self.onShowInChat = onShowInChat
        self.onClose = onClose
        _selection = State(initialValue: request.id)
        _hero = State(initialValue: Self.tile(request.id).map { Hero(image: $0.image, source: $0.frame, cornerRadius: $0.cornerRadius) })
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                    .opacity(MediaDismissRule.backgroundOpacity(offset: dragOffset, height: geo.size.height) * progress)
                    .ignoresSafeArea()
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        screen = frame
                        if phase == .opening { open() }
                    }
                pager
                    .offset(y: dragOffset)
                    .opacity(pagerOpacity)
                    .allowsHitTesting(phase == .open)
                if phase == .open && chrome.visible && dragOffset == 0 {
                    VStack(spacing: 0) {
                        header
                        Spacer(minLength: 0)
                        bottomBar
                    }
                    .transition(.opacity)
                }
                if let hero, phase != .open {
                    flyingFrame(hero)
                }
            }
            .simultaneousGesture(dismissDrag(height: geo.size.height))
        }
        .overlay(alignment: .bottom) { noticeView }
        .animation(.easeInOut(duration: 0.2), value: chrome.visible)
        .animation(.easeInOut(duration: 0.2), value: notice)
        .statusBarHidden(!chrome.visible || phase != .open)
        .persistentSystemOverlays(chrome.visible ? .automatic : .hidden)
        .presentationBackground(.clear)
        .onChange(of: selection) { _, id in
            zoomed = false
            chrome.show()
            if phase == .open { MediaSourceRegistry.shared.hiddenId = id }
        }
        .onAppear { OrientationLock.allowRotation() }
        .onDisappear {
            MediaSourceRegistry.shared.hiddenId = nil
            OrientationLock.lockPortrait()
        }
    }

    /// Во время полёта виден только летящий кадр; без него просмотр проявляется и гаснет целиком.
    private var pagerOpacity: CGFloat {
        if phase == .open { return 1 }
        return hero == nil ? progress : 0
    }

    // MARK: Полёт

    /// Плитка ленты: где стоит и её картинка из кэша — та же, что видна в ленте.
    private static func tile(_ id: String) -> (frame: CGRect, image: UIImage, cornerRadius: CGFloat)? {
        guard let source = MediaSourceRegistry.shared.source(for: id), let url = source.url,
              let image = ImagePipeline.shared.cached(url, maxPixel: source.maxPixel)?.image else { return nil }
        return (source.frame, image, source.cornerRadius)
    }

    /// Где кадр стоит в открытом просмотре: картинка, вписанная в экран.
    private func fullFrame(_ image: UIImage) -> CGRect {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return screen }
        return MediaHeroGeometry.fit(aspect: size.width / size.height, in: screen)
    }

    private func flyingFrame(_ hero: Hero) -> some View {
        let full = fullFrame(hero.image).offsetBy(dx: 0, dy: dragOffset)
        let rect = MediaHeroGeometry.interpolate(from: hero.source, to: full, progress: progress)
        return Color.clear
            .overlay(alignment: .topLeading) {
                Image(uiImage: hero.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: max(1, rect.width), height: max(1, rect.height))
                    .clipShape(RoundedRectangle(cornerRadius: hero.cornerRadius * (1 - progress), style: .continuous))
                    .offset(x: rect.minX - screen.minX, y: rect.minY - screen.minY)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    /// Первое измерение экрана: кадр вылетает из плитки (или просмотр проявляется).
    private func open() {
        guard screen.width > 0, progress == 0 else { return }
        if hero != nil { MediaSourceRegistry.shared.hiddenId = request.id }
        let animation: Animation = hero == nil ? .easeOut(duration: 0.2) : .spring(duration: 0.34, bounce: 0.12)
        withAnimation(animation) {
            progress = 1
        } completion: {
            guard phase == .opening else { return }
            phase = .open
            MediaSourceRegistry.shared.hiddenId = selection
        }
    }

    // MARK: Листание

    private var pager: some View {
        ScrollViewReader { proxy in
            pagerScroll
                .onAppear { proxy.scrollTo(request.id) }
        }
    }

    private var pagerScroll: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(request.slides) { slide in
                    page(slide)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(slide.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $selection)
        .scrollIndicators(.hidden)
        // Увеличенное фото и полоса ролика забирают палец себе.
        .scrollDisabled(zoomed || scrubbing || dragAxis == .vertical)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func page(_ slide: MediaSlide) -> some View {
        if slide.isVideo, slide.playURL != nil {
            VideoPage(
                slide: slide,
                poster: Self.tile(slide.id)?.image,
                active: selection == slide.id && phase == .open,
                chrome: $chrome,
                scrubbing: $scrubbing,
                download: download,
                // Ролик ушёл в окошко: просмотр закрывается сразу, без полёта.
                onPictureInPicture: finish
            )
        } else {
            PhotoPage(
                url: slide.stillURL,
                placeholder: Self.tile(slide.id)?.image,
                turns: turns[slide.id] ?? 0,
                onTap: { chrome.toggle() }
            ) { zoomed = $0 }
        }
    }

    private var current: MediaSlide? { request.slides.first { $0.id == selection } }
    private var currentIsVideo: Bool { current?.isVideo == true }

    // MARK: Шапка и низ

    private var header: some View {
        HStack(spacing: 10) {
            CircleButton(systemName: "xmark", label: "Закрыть") { close() }
            VStack(alignment: .leading, spacing: 1) {
                if let author = request.author, !author.isEmpty {
                    Text(author)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            Spacer(minLength: 8)
            if let slide = current, !slide.isVideo {
                CircleButton(systemName: "rotate.right", label: "Повернуть") {
                    turns[slide.id, default: 0] += 1
                }
            }
            if let onSave {
                shareButton(onSave)
            }
            if onSave != nil || onShowInChat != nil {
                moreMenu
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 24)
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }

    /// Подпись и лента миниатюр альбома; у ролика — над его полосой.
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let caption = request.caption {
                CaptionView(text: caption)
            }
            if request.slides.count > 1 {
                ThumbnailStrip(slides: request.slides, selection: selection) { id in
                    withAnimation(.snappy) { selection = id }
                }
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 12 + (currentIsVideo ? VideoControls.height : 0))
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    /// «12 октября, 14:05 · 3 из 7».
    private var subtitle: String? {
        var parts: [String] = []
        if let date = request.date {
            parts.append(date.formatted(.dateTime.day().month(.wide).hour().minute()))
        }
        if request.slides.count > 1, let index = request.slides.firstIndex(where: { $0.id == selection }) {
            parts.append("\(index + 1) из \(request.slides.count)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// «Поделиться» открытым кадром: файл качается (если ещё нет) и открывается системное окно.
    private func shareButton(_ onSave: @escaping (String, SaveTarget) -> Void) -> some View {
        Button {
            onSave(selection ?? request.id, .share)
        } label: {
            ZStack {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 38, height: 38)
            .background(.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel("Поделиться")
    }

    /// «⋯»: перейти к сообщению, сохранить в «Фото» или «Файлы».
    private var moreMenu: some View {
        Menu {
            if let onShowInChat {
                Button("Перейти к сообщению", systemImage: "bubble.left.and.text.bubble.right") {
                    close(then: onShowInChat)
                }
            }
            if let onSave {
                Button("Сохранить в Фото", systemImage: "square.and.arrow.down") { onSave(selection ?? request.id, .photos) }
                Button("Сохранить в Файлы", systemImage: "folder") { onSave(selection ?? request.id, .files) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.35), in: Circle())
        }
        .disabled(isSaving)
        .accessibilityLabel("Ещё")
    }

    @ViewBuilder
    private var noticeView: some View {
        if let notice {
            Text(notice)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(.bottom, 40)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
        }
    }

    // MARK: Закрытие

    /// Кадр летит обратно в свою плитку, если она на экране; иначе просмотр гаснет. [then] —
    /// что сделать после закрытия (перейти к сообщению).
    private func close(then: (() -> Void)? = nil) {
        guard phase != .closing else { return }
        afterClose = then
        let id = selection ?? request.id
        let upright = screen.height >= screen.width && (turns[id] ?? 0) % 4 == 0 && !zoomed
        if upright, let tile = Self.tile(id), MediaHeroGeometry.canReturn(to: tile.frame, screen: screen) {
            hero = Hero(image: tile.image, source: tile.frame, cornerRadius: tile.cornerRadius)
            MediaSourceRegistry.shared.hiddenId = id
            phase = .closing
            withAnimation(.spring(duration: 0.3, bounce: 0)) {
                progress = 0
                dragOffset = 0
            } completion: { finish() }
        } else {
            // Сначала портрет: иначе чат под просмотром мелькнул бы боком.
            OrientationLock.lockPortrait()
            hero = nil
            phase = .closing
            withAnimation(.easeOut(duration: 0.2)) { progress = 0 } completion: { finish() }
        }
    }

    /// Полёт закончился: плитка снова видна, окно просмотра убирается без своей анимации.
    private func finish() {
        MediaSourceRegistry.shared.hiddenId = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { onClose() }
        afterClose?()
    }

    /// Смахивание вверх или вниз: кадр идёт за пальцем, отпустили — закрыть или вернуть.
    private func dismissDrag(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard phase == .open, !zoomed, !scrubbing else { return }
                if dragAxis == nil {
                    dragAxis = abs(value.translation.height) > abs(value.translation.width) ? .vertical : .horizontal
                }
                guard dragAxis == .vertical else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                defer { dragAxis = nil }
                guard phase == .open, dragAxis == .vertical else { return }
                if MediaDismissRule.shouldClose(offset: dragOffset, velocity: value.velocity.height, height: height) {
                    close()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragOffset = 0 }
                }
            }
    }
}

extension View {
    /// Окно просмотра фото и видео: появляется и убирается без системного выезда снизу и с
    /// прозрачным фоном — открытие и закрытие рисует сам `MediaViewer`.
    func mediaViewerCover<Item: Identifiable, Cover: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Cover
    ) -> some View {
        modifier(InstantCover(item: item, cover: content))
    }
}

private struct InstantCover<Item: Identifiable, Cover: View>: ViewModifier {
    @Binding var item: Item?
    let cover: (Item) -> Cover
    @State private var shown: Item?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: Binding(get: { shown }, set: { value in
                if value == nil { item = nil }
                instantly { shown = value }
            })) { value in
                cover(value)
            }
            .onChange(of: item?.id) { _, _ in instantly { shown = item } }
            .onAppear { if item != nil { instantly { shown = item } } }
    }

    private func instantly(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}

/// Лента миниатюр альбома: открытая — шире и обведена, касание открывает другую.
private struct ThumbnailStrip: View {
    let slides: [MediaSlide]
    let selection: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 3) {
                    ForEach(slides) { slide in
                        let selected = slide.id == selection
                        RemoteImage(url: slide.stillURL, maxPixel: 200) {
                            Color.white.opacity(0.12)
                        }
                        .frame(width: selected ? 44 : 30, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay {
                            if slide.isVideo {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 2)
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(.white, lineWidth: selected ? 2 : 0)
                        }
                        .opacity(selected ? 1 : 0.7)
                        .padding(.horizontal, selected ? 4 : 0)
                        .id(slide.id)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(slide.id) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(slide.isVideo ? "Видео" : "Фото")
                    }
                }
                .padding(.horizontal, 16)
                .animation(.snappy, value: selection)
            }
            .scrollIndicators(.hidden)
            .onAppear { if let selection { proxy.scrollTo(selection, anchor: .center) } }
            .onChange(of: selection) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(height: 48)
    }
}

// MARK: - Мелкие части

/// Круглая кнопка на тёмной подложке.
private struct CircleButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.35), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Подпись к фото или видео внизу: три строки, касание раскрывает целиком.
private struct CaptionView: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white)
            .lineLimit(expanded ? nil : 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
    }
}

// MARK: - Фото

/// Фото: щипок и двойное касание увеличивают (двойное — в 2,5 раза к точке касания и обратно),
/// одиночное прячет интерфейс. Пока грузится оригинал, видна картинка плитки из ленты (с ней
/// же прилетел кадр), без неё — кольцо.
private struct PhotoPage: View {
    let url: URL?
    var placeholder: UIImage?
    let turns: Int
    let onTap: () -> Void
    let onZoom: (Bool) -> Void
    @State private var loaded = false

    var body: some View {
        ZStack {
            ZoomableImage(url: url, placeholder: placeholder, turns: turns, onTap: onTap, onLoaded: { loaded = $0 }, onZoom: onZoom)
            if !loaded && placeholder == nil {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Прокрутка, которая перекладывает фото при каждой смене размера (поворот экрана).
private final class PhotoScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        onLayout?()
    }
}

private struct ZoomableImage: UIViewRepresentable {
    let url: URL?
    /// Видна, пока не пришёл оригинал.
    var placeholder: UIImage?
    /// Поворот четвертями по часовой: картинка перерисовывается повёрнутой и заново вписывается.
    var turns = 0
    let onTap: () -> Void
    let onLoaded: (Bool) -> Void
    let onZoom: (Bool) -> Void

    func makeUIView(context: Context) -> PhotoScrollView {
        let scroll = PhotoScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.bouncesZoom = true
        scroll.delegate = context.coordinator
        scroll.backgroundColor = .clear
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        scroll.addSubview(imageView)
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        single.require(toFail: double)
        scroll.addGestureRecognizer(single)
        context.coordinator.scroll = scroll
        context.coordinator.imageView = imageView
        scroll.onLayout = { [weak coordinator = context.coordinator] in coordinator?.relayout() }
        context.coordinator.load(url)
        return scroll
    }

    func updateUIView(_ scroll: PhotoScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.rotate(to: turns)
        context.coordinator.layout()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableImage
        weak var scroll: UIScrollView?
        var imageView: UIImageView?
        private var task: Task<Void, Never>?
        /// Картинка как пришла и сколько четвертей она повёрнута на экране.
        private var original: UIImage?
        private var turns = 0

        init(parent: ZoomableImage) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            center()
            parent.onZoom(scrollView.zoomScale > 1.01)
        }

        @objc func tapped() { parent.onTap() }

        /// Двойное касание: увеличить к точке касания или вернуть к целому кадру.
        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scroll, let imageView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
                return
            }
            let scale: CGFloat = 2.5
            let point = recognizer.location(in: imageView)
            let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
            scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }

        /// Состояние «загружено» — после текущего обновления экрана: менять его посреди обновления нельзя.
        private func report(_ loaded: Bool) {
            let onLoaded = parent.onLoaded
            DispatchQueue.main.async { onLoaded(loaded) }
        }

        func load(_ url: URL?) {
            task?.cancel()
            original = nil
            imageView?.image = nil
            report(false)
            if let placeholder = parent.placeholder {
                // Плитка из ленты — на месте, пока грузится оригинал; не повёрнута и не «загружена».
                imageView?.image = placeholder
                relayout()
            }
            guard let url else { return }
            if url.isFileURL {
                show(UIImage(contentsOfFile: url.path))
                return
            }
            task = Task { [weak self] in
                let image: UIImage? = await Task.detached(priority: .userInitiated) {
                    guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
                    return UIImage(data: data)
                }.value
                guard !Task.isCancelled, let self else { return }
                // Оригинал не скачался — остаётся плитка, если она есть.
                if image != nil || self.parent.placeholder == nil { self.show(image) }
            }
        }

        private func show(_ image: UIImage?) {
            original = image
            imageView?.image = image.map { Self.rotated($0, turns: turns) }
            report(image != nil)
            relayout()
        }

        /// Повернуть на `next` четвертей: зум сбрасывается, повёрнутая картинка вписывается заново.
        func rotate(to next: Int) {
            guard next != turns else { return }
            turns = next
            guard let original, let imageView, let scroll else { return }
            scroll.setZoomScale(1, animated: false)
            UIView.transition(with: imageView, duration: 0.2, options: .transitionCrossDissolve) {
                imageView.image = Self.rotated(original, turns: next)
            }
            relayout()
        }

        /// Картинка, повёрнутая на `turns` четвертей по часовой.
        static func rotated(_ image: UIImage, turns: Int) -> UIImage {
            let quarter = ((turns % 4) + 4) % 4
            guard quarter != 0 else { return image }
            let size = quarter % 2 == 0 ? image.size : CGSize(width: image.size.height, height: image.size.width)
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                let canvas = context.cgContext
                canvas.translateBy(x: size.width / 2, y: size.height / 2)
                canvas.rotate(by: CGFloat(quarter) * .pi / 2)
                image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
            }
        }

        /// Размер экрана сменился (поворот): масштаб сбрасывается, кадр вписывается заново.
        func relayout() {
            scroll?.setZoomScale(1, animated: false)
            layout()
        }

        func layout() {
            guard let scroll, scroll.zoomScale <= 1.01, let imageView, let image = imageView.image else { return }
            let bounds = scroll.bounds
            guard bounds.width > 1, bounds.height > 1, image.size.width > 0, image.size.height > 0 else { return }
            let fitted = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * fitted, height: image.size.height * fitted)
            if scroll.zoomScale == 1 {
                imageView.frame = CGRect(origin: .zero, size: size)
                scroll.contentSize = size
            }
            center()
        }

        private func center() {
            guard let scroll, let imageView else { return }
            let bounds = scroll.bounds
            var frame = imageView.frame
            frame.origin.x = frame.width < bounds.width ? (bounds.width - frame.width) / 2 : 0
            frame.origin.y = frame.height < bounds.height ? (bounds.height - frame.height) / 2 : 0
            imageView.frame = frame
        }
    }
}

// MARK: - Видео

/// Страница ролика: свой плеер, жесты и полоса управления.
private struct VideoPage: View {
    let slide: MediaSlide
    /// Обложка из плитки ленты — видна сразу, пока нет первого кадра.
    var poster: UIImage?
    let active: Bool
    @Binding var chrome: MediaViewerChrome
    @Binding var scrubbing: Bool
    let download: (MediaSlide, @escaping @MainActor (Double) -> Void) async -> URL?
    let onPictureInPicture: () -> Void

    @State private var playback = VideoPlayback()
    @State private var taps = SeekTapAccumulator()
    @State private var seekBadge: SeekTapAccumulator.Seek?
    @State private var badgeToken = 0
    @State private var holding = false
    @State private var menuOpen = false

    var body: some View {
        ZStack {
            if !playback.hasFrame, let poster {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFit()
                    .allowsHitTesting(false)
            } else if !playback.hasFrame, let poster = slide.stillURL {
                AsyncImage(url: poster) { image in
                    image.resizable().scaledToFit()
                } placeholder: { Color.clear }
                .allowsHitTesting(false)
            }
            PlayerSurface(
                player: playback.player,
                onTap: { chrome.toggle() },
                onDoubleTap: seek(x:width:),
                onHold: hold(_:),
                onLayer: { layer in
                    playback.attach(layer) { onPictureInPicture() }
                }
            )
            status
            if let seekBadge {
                SeekBadge(seek: seekBadge)
                    .frame(maxWidth: .infinity, alignment: seekBadge.forward ? .trailing : .leading)
                    .padding(.horizontal, 36)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            if holding {
                Text("\(PlaybackSpeed.label(PlaybackSpeed.hold)) ▸▸")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 70)
                    .allowsHitTesting(false)
            }
            if chrome.visible {
                centerButton
                    .transition(.opacity)
                VideoControls(playback: playback, scrubbing: $scrubbing, menuOpen: $menuOpen)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: seekBadge)
        .animation(.easeInOut(duration: 0.15), value: holding)
        .task(id: active) {
            if active {
                playback.start(url: slide.playURL) { progress in await download(slide, progress) }
            } else {
                playback.pause()
            }
        }
        // В окошке ролик играет дальше: его держит `PictureInPicture`.
        .onDisappear { if !PictureInPicture.shared.isActive(playback) { playback.stop() } }
        .onChange(of: playback.isPlaying) { _, playing in
            if !playing { chrome.playbackStopped() }
        }
        // Меню скорости закрыли касанием мимо: следующее касание по кадру снимает флаг.
        .onChange(of: chrome.visible) { _, _ in menuOpen = false }
        // Играющий ролик через 3 секунды прячет интерфейс.
        .task(id: autoHideKey) {
            guard chrome.shouldAutoHide(playing: playback.isPlaying, scrubbing: scrubbing, menuOpen: menuOpen) else { return }
            try? await Task.sleep(for: .seconds(MediaViewerChrome.autoHideDelay))
            guard !Task.isCancelled, chrome.shouldAutoHide(playing: playback.isPlaying, scrubbing: scrubbing, menuOpen: menuOpen) else { return }
            chrome.hide()
        }
    }

    private var autoHideKey: [Bool] { [chrome.visible, playback.isPlaying, scrubbing, menuOpen, active] }

    /// Загрузка, скачивание с процентами или ошибка поверх кадра.
    @ViewBuilder
    private var status: some View {
        if let fraction = playback.downloading {
            VStack(spacing: 10) {
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: max(0.02, fraction))
                        .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: fraction)
                    Button {
                        playback.cancelDownload()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                    }
                    .accessibilityLabel("Отменить загрузку")
                }
                .frame(width: 60, height: 60)
                Text(MediaTimeText.download(fraction: fraction))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
        } else if playback.failed {
            VStack(spacing: 12) {
                Text("Видео не воспроизводится")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                Button("Повторить") { playback.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.25))
            }
            .padding(16)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        } else if playback.buffering {
            ProgressView()
                .tint(.white)
                .controlSize(.large)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var centerButton: some View {
        if playback.downloading == nil, !playback.failed, !playback.buffering || playback.hasFrame {
            Button {
                playback.toggle()
            } label: {
                Image(systemName: playback.ended ? "arrow.counterclockwise" : (playback.isPlaying ? "pause.fill" : "play.fill"))
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(.black.opacity(0.4), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback.isPlaying ? "Пауза" : "Смотреть")
        }
    }

    /// Двойное касание: у краёв — перемотка ±10 с, в середине — пауза или продолжение.
    private func seek(x: CGFloat, width: CGFloat) {
        guard let forward = SeekTapAccumulator.side(x: x, width: width) else {
            playback.toggle()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let seek = taps.tap(forward: forward, at: now, position: playback.position, duration: playback.duration)
        playback.seek(to: seek.target)
        seekBadge = seek
        badgeToken += 1
        let token = badgeToken
        Task {
            try? await Task.sleep(for: .seconds(SeekTapAccumulator.window))
            if token == badgeToken { seekBadge = nil }
        }
    }

    /// Удержание — ускорение, пока палец на экране.
    private func hold(_ began: Bool) {
        holding = began
        playback.setHoldingFast(began)
    }
}

/// «‹‹ 20 с» у левого края или «20 с ››» у правого.
private struct SeekBadge: View {
    let seek: SeekTapAccumulator.Seek

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: seek.forward ? "goforward" : "gobackward")
                .font(.system(size: 26, weight: .semibold))
            Text("\(seek.total) с")
                .font(.footnote.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(.white)
        .frame(width: 84, height: 84)
        .background(.black.opacity(0.35), in: Circle())
    }
}

/// Полоса ролика внизу: время, полоса с подгруженной частью, пауза, звук и скорость.
private struct VideoControls: View {
    static let height: CGFloat = 96

    let playback: VideoPlayback
    @Binding var scrubbing: Bool
    @Binding var menuOpen: Bool
    @State private var scrubFraction: Double?

    var body: some View {
        VStack(spacing: 6) {
            Scrubber(
                fraction: scrubFraction ?? playback.fraction,
                buffered: playback.bufferedFraction,
                active: scrubFraction != nil,
                onChange: { fraction in
                    if scrubFraction == nil { scrubbing = true }
                    scrubFraction = fraction
                    playback.scrub(to: fraction)
                },
                onEnd: { fraction in
                    playback.scrub(to: fraction, final: true)
                    scrubFraction = nil
                    scrubbing = false
                }
            )
            HStack(spacing: 14) {
                Button {
                    playback.toggle()
                } label: {
                    Image(systemName: playback.ended ? "arrow.counterclockwise" : (playback.isPlaying ? "pause.fill" : "play.fill"))
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(playback.isPlaying ? "Пауза" : "Смотреть")
                Text("\(MediaTimeText.clock(displayed)) / \(MediaTimeText.clock(playback.duration))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 8)
                Button {
                    playback.toggleMuted()
                } label: {
                    Image(systemName: playback.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(playback.muted ? "Включить звук" : "Выключить звук")
                if AVPictureInPictureController.isPictureInPictureSupported() {
                    Button {
                        playback.startPictureInPicture()
                    } label: {
                        Image(systemName: "pip.enter")
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("Картинка в картинке")
                }
                Menu {
                    ForEach(PlaybackSpeed.options, id: \.self) { rate in
                        Button {
                            playback.setRate(rate)
                            menuOpen = false
                        } label: {
                            if rate == playback.rate {
                                Label(PlaybackSpeed.label(rate), systemImage: "checkmark")
                            } else {
                                Text(PlaybackSpeed.label(rate))
                            }
                        }
                    }
                } label: {
                    Text(PlaybackSpeed.label(playback.rate))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 36, minHeight: 28)
                }
                .simultaneousGesture(TapGesture().onEnded { menuOpen = true })
                .accessibilityLabel("Скорость")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    private var displayed: TimeInterval {
        scrubFraction.map { $0 * playback.duration } ?? playback.position
    }
}

/// Полоса перемотки: сыграно — белым, подгружено — светлее, остальное — тускло. Палец ведёт
/// ползунок, кадр меняется вслед.
private struct Scrubber: View {
    let fraction: Double
    let buffered: Double
    let active: Bool
    let onChange: (Double) -> Void
    let onEnd: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(.white.opacity(0.45)).frame(width: width * min(1, max(0, buffered)))
                Capsule().fill(.white).frame(width: width * min(1, max(0, fraction)))
                Circle()
                    .fill(.white)
                    .frame(width: active ? 18 : 12, height: active ? 18 : 12)
                    .offset(x: width * min(1, max(0, fraction)) - (active ? 9 : 6))
            }
            .frame(height: active ? 6 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onChange(min(1, max(0, $0.location.x / width))) }
                    .onEnded { onEnd(min(1, max(0, $0.location.x / width))) }
            )
            .animation(.easeOut(duration: 0.12), value: active)
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("Перемотка")
        .accessibilityValue("\(Int((fraction * 100).rounded())) %")
    }
}

/// Слой ролика с жестами UIKit: касание, двойное касание с точкой и удержание.
private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let onTap: () -> Void
    let onDoubleTap: (CGFloat, CGFloat) -> Void
    let onHold: (Bool) -> Void
    /// Слой ролика готов: из него запускается картинка в картинке.
    var onLayer: (AVPlayerLayer) -> Void = { _ in }

    func makeUIView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        onLayer(view.playerLayer)
        view.backgroundColor = .clear
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        view.addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        single.require(toFail: double)
        view.addGestureRecognizer(single)
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.4
        view.addGestureRecognizer(hold)
        return view
    }

    func updateUIView(_ view: SurfaceView, context: Context) {
        context.coordinator.parent = self
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PlayerSurface

        init(parent: PlayerSurface) {
            self.parent = parent
        }

        @objc func tapped() { parent.onTap() }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            parent.onDoubleTap(recognizer.location(in: view).x, view.bounds.width)
        }

        @objc func held(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began: parent.onHold(true)
            case .ended, .cancelled, .failed: parent.onHold(false)
            default: break
            }
        }
    }

    final class SurfaceView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// Картинка в картинке: ролик из просмотра играет в окошке поверх других приложений и экранов.
///
/// Окошко открывается кнопкой на полосе ролика или само, когда приложение сворачивают во время
/// воспроизведения. Просмотр при этом закрывается, а ролик (плеер и его слой) держится здесь,
/// пока окошко не закроют.
@MainActor
private final class PictureInPicture: NSObject {
    static let shared = PictureInPicture()

    private struct Entry {
        weak var playback: VideoPlayback?
        let onStarted: () -> Void
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    /// Ролик, который сейчас в окошке.
    private var playing: VideoPlayback?

    func register(_ controller: AVPictureInPictureController, playback: VideoPlayback, onStarted: @escaping () -> Void) {
        entries = entries.filter { $0.value.playback != nil }
        entries[ObjectIdentifier(controller)] = Entry(playback: playback, onStarted: onStarted)
        controller.delegate = self
    }

    func isActive(_ playback: VideoPlayback) -> Bool { playing === playback }
}

extension PictureInPicture: @preconcurrency AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        playing = entries[ObjectIdentifier(controller)]?.playback
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        entries[ObjectIdentifier(controller)]?.onStarted()
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: any Error) {
        Log.warning(.media, "Картинка в картинке не открылась: \(error)")
        playing = nil
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        // Окошко закрыли: ролик останавливается и отпускается вместе с плеером.
        playing?.stop()
        playing = nil
        entries[ObjectIdentifier(controller)] = nil
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

/// Состояние одного ролика: время, подгруженная часть, загрузка целиком и ошибки.
///
/// Сначала играет поток. Не открылся (`AVPlayerItem.status == .failed`) — ролик один раз
/// скачивается целиком с прогрессом и играет с диска. Не вышло и так — ошибка с «Повторить».
@MainActor
@Observable
private final class VideoPlayback {
    let player = AVPlayer()
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var bufferedFraction: Double = 0
    private(set) var buffering = true
    private(set) var hasFrame = false
    private(set) var failed = false
    private(set) var ended = false
    private(set) var muted = false
    private(set) var rate: Double = 1
    /// Ролик скачивается целиком: доля 0…1.
    private(set) var downloading: Double?

    var fraction: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }

    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var download: ((@escaping @MainActor (Double) -> Void) async -> URL?)?
    @ObservationIgnored private var triedDownload = false
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var controlObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastScrub: TimeInterval = 0
    /// Слой ролика (держится и после ухода экрана — в нём играет окошко) и его картинка в картинке.
    @ObservationIgnored private var layer: AVPlayerLayer?
    @ObservationIgnored private var pictureInPicture: AVPictureInPictureController?

    /// Слой страницы готов: из него можно уйти в окошко кнопкой или сворачиванием приложения.
    func attach(_ layer: AVPlayerLayer, onStarted: @escaping () -> Void) {
        guard self.layer !== layer else { return }
        self.layer = layer
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let controller = AVPictureInPictureController(playerLayer: layer) else { return }
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        PictureInPicture.shared.register(controller, playback: self, onStarted: onStarted)
        pictureInPicture = controller
    }

    func startPictureInPicture() {
        if !isPlaying { play() }
        pictureInPicture?.startPictureInPicture()
    }

    /// Открыть ролик (один раз) и играть; повторный вызов — продолжить.
    func start(url: URL?, download: @escaping (@escaping @MainActor (Double) -> Void) async -> URL?) {
        prepareSession()
        guard !started else {
            if !failed, downloading == nil, !ended { play() }
            return
        }
        started = true
        failed = false
        ended = false
        self.url = url
        self.download = download
        guard let url else {
            failed = true
            return
        }
        observe()
        load(url)
        play()
    }

    func toggle() {
        if failed {
            retry()
        } else if ended {
            player.seek(to: .zero)
            ended = false
            play()
        } else if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        player.playImmediately(atRate: Float(rate))
    }

    func pause() { player.pause() }

    /// Страница ушла: ролик выгружается, наблюдатели снимаются; вернулись — `start` откроет заново.
    func stop() {
        downloadTask?.cancel()
        downloadTask = nil
        downloading = nil
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        controlObservation = nil
        itemObservations = []
        player.replaceCurrentItem(with: nil)
        started = false
        triedDownload = false
        hasFrame = false
    }

    func seek(to seconds: TimeInterval) {
        ended = false
        position = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Полосу тянут: кадр догоняет палец не чаще раза в 0,05 с, отпустили — точно.
    func scrub(to fraction: Double, final: Bool = false) {
        guard duration > 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard final || now - lastScrub > 0.05 else { return }
        lastScrub = now
        seek(to: fraction * duration)
    }

    func toggleMuted() {
        muted.toggle()
        player.isMuted = muted
    }

    func setRate(_ value: Double) {
        rate = value
        if isPlaying { player.rate = Float(value) }
    }

    /// Удержание: 2×, отпустили — прежняя скорость.
    func setHoldingFast(_ fast: Bool) {
        if fast {
            if !isPlaying { play() }
            player.rate = Float(PlaybackSpeed.hold)
        } else if isPlaying {
            player.rate = Float(rate)
        }
    }

    func retry() {
        failed = false
        triedDownload = false
        guard let url else { return }
        load(url)
        play()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloading = nil
        failed = true
    }

    private func load(_ url: URL) {
        buffering = true
        let item: AVPlayerItem
        if !url.isFileURL, let agent = MediaHTTP.userAgent {
            item = AVPlayerItem(asset: AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: agent]))
        } else {
            item = AVPlayerItem(url: url)
        }
        itemObservations = [
            item.observe(\.status, options: [.new]) { @Sendable [weak self] item, _ in
                let status = item.status
                let message = item.error.map { "\($0)" } ?? ""
                Task { @MainActor in self?.itemChanged(status, error: message) }
            },
            item.observe(\.loadedTimeRanges, options: [.new]) { @Sendable [weak self] item, _ in
                let ranges = item.loadedTimeRanges.map(\.timeRangeValue)
                Task { @MainActor in self?.buffered(ranges) }
            },
        ]
        player.replaceCurrentItem(with: item)
        player.isMuted = muted
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { @Sendable [weak self] _ in
            Task { @MainActor in
                self?.ended = true
                self?.isPlaying = false
            }
        }
    }

    private func observe() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { @Sendable [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in self?.tick(seconds) }
        }
        controlObservation = player.observe(\.timeControlStatus, options: [.new]) { @Sendable [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in self?.controlChanged(status) }
        }
    }

    private func tick(_ seconds: TimeInterval) {
        if seconds.isFinite { position = seconds }
        if let item = player.currentItem {
            let total = item.duration.seconds
            if total.isFinite, total > 0 { duration = total }
            if item.presentationSize != .zero, seconds > 0 { hasFrame = true }
        }
    }

    private func buffered(_ ranges: [CMTimeRange]) {
        guard duration > 0 else { return }
        let end = ranges.map { $0.end.seconds }.filter(\.isFinite).max() ?? 0
        bufferedFraction = min(1, end / duration)
    }

    private func controlChanged(_ status: AVPlayer.TimeControlStatus) {
        isPlaying = status == .playing || status == .waitingToPlayAtSpecifiedRate
        buffering = status == .waitingToPlayAtSpecifiedRate
        if status == .playing { hasFrame = true }
    }

    private func itemChanged(_ status: AVPlayerItem.Status, error: String) {
        switch status {
        case .readyToPlay:
            buffering = false
            if let total = player.currentItem?.duration.seconds, total.isFinite, total > 0 { duration = total }
        case .failed:
            Log.warning(.media, "Видео не открылось потоком: \(error)")
            fallback()
        default:
            break
        }
    }

    /// Поток не открылся: скачать целиком с прогрессом и играть с диска.
    private func fallback() {
        guard !triedDownload, let download else {
            failed = true
            buffering = false
            return
        }
        triedDownload = true
        downloading = 0
        buffering = false
        downloadTask = Task { [weak self] in
            let file = await download { fraction in self?.downloading = fraction }
            guard let self, !Task.isCancelled else { return }
            self.downloading = nil
            if let file {
                self.load(file)
                self.play()
            } else {
                self.failed = true
            }
        }
    }

    private func prepareSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
