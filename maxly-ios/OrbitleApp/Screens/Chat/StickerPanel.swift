import SwiftUI
import UIKit
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Панель эмодзи и стикеров на месте клавиатуры: сверху полоса
/// разделов (нажатие прокручивает к разделу, текущий подсвечен), сетка с заголовками,
/// снизу переключатель «Эмодзи | Стикеры» и «стереть».
struct StickerPanel: View {
    @Bindable var model: StickerPanelModel
    let height: CGFloat
    let onEmoji: (EmojiItem) -> Void
    let onBackspace: () -> Void
    let onSticker: (Sticker) -> Void

    @State private var currentEmoji: String?
    @State private var currentStickers: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.mode {
                case .emoji: emojiPane
                case .stickers: stickerPane
                }
            }
            .frame(maxHeight: .infinity)
            bottomBar
        }
        .frame(height: height)
        .background(Color(uiColor: .secondarySystemBackground).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider() }
        .onAppear { model.prepare() }
        .onDisappear { model.refreshRecents() }
    }

    // MARK: Эмодзи

    private var emojiPane: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                sectionStrip(
                    ids: model.emojiSections.map(\.id),
                    current: currentEmoji ?? model.emojiSections.first?.id
                ) { id in
                    jump(proxy, to: id) { currentEmoji = id }
                } icon: { id in
                    Image(systemName: model.emojiSections.first { $0.id == id }?.systemImage ?? "circle")
                        .font(.system(size: 17, weight: .medium))
                }
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 8), spacing: 2, pinnedViews: [.sectionHeaders]) {
                        ForEach(model.emojiSections) { section in
                            Section {
                                ForEach(section.items) { item in
                                    EmojiCell(item: item) { onEmoji(item); model.noteEmoji(item) }
                                }
                            } header: {
                                header(section.title)
                                    .id(section.id)
                                    .onAppear { currentEmoji = section.id }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: Стикеры

    @ViewBuilder
    private var stickerPane: some View {
        if model.stickerSections.isEmpty {
            VStack(spacing: 10) {
                if model.isLoading {
                    ProgressView()
                } else if let failure = model.failure {
                    Text(failure)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Повторить") { model.retry() }
                } else {
                    Text("Стикеров пока нет")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    sectionStrip(
                        ids: model.stickerSections.map(\.id),
                        current: currentStickers ?? model.stickerSections.first?.id
                    ) { id in
                        jump(proxy, to: id) { currentStickers = id }
                    } icon: { id in
                        stickerIcon(model.stickerSections.first { $0.id == id })
                    }
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4, pinnedViews: [.sectionHeaders]) {
                            ForEach(model.stickerSections) { section in
                                Section {
                                    ForEach(section.stickerIds, id: \.self) { id in
                                        StickerCell(sticker: model.stickers[id]) { sticker in
                                            onSticker(sticker)
                                            model.noteSticker(sticker)
                                        }
                                    }
                                } header: {
                                    header(section.title)
                                        .id(section.id)
                                        .onAppear {
                                            currentStickers = section.id
                                            model.loadStickers(of: section)
                                        }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    @ViewBuilder
    private func stickerIcon(_ section: StickerSection?) -> some View {
        if let image = section?.systemImage {
            Image(systemName: image).font(.system(size: 17, weight: .medium))
        } else {
            RemoteImage(url: section?.iconURL, maxPixel: 90) {
                Circle().fill(Color.secondary.opacity(0.15))
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    // MARK: Общее

    /// Полоса разделов: значки по горизонтали, текущий на подложке.
    private func sectionStrip<Icon: View>(
        ids: [String],
        current: String?,
        onTap: @escaping (String) -> Void,
        @ViewBuilder icon: @escaping (String) -> Icon
    ) -> some View {
        ScrollViewReader { strip in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(ids, id: \.self) { id in
                        Button { onTap(id) } label: {
                            icon(id)
                                .foregroundStyle(current == id ? Color.primary : Color.secondary)
                                .frame(width: 38, height: 34)
                                .background(
                                    current == id ? Color.primary.opacity(0.1) : .clear,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(id)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 44)
            .onChange(of: current) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { strip.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Color(uiColor: .secondarySystemBackground))
    }

    private func jump(_ proxy: ScrollViewProxy, to id: String, select: () -> Void) {
        select()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.26)) { proxy.scrollTo(id, anchor: .top) }
    }

    /// «Эмодзи | Стикеры» по центру, «стереть» справа (только у эмодзи).
    private var bottomBar: some View {
        ZStack {
            HStack(spacing: 2) {
                modeButton("Эмодзи", mode: .emoji)
                modeButton("Стикеры", mode: .stickers)
            }
            .padding(3)
            .background(Color.primary.opacity(0.07), in: Capsule())
            if model.mode == .emoji {
                HStack {
                    Spacer()
                    Button(action: onBackspace) {
                        Image(systemName: "delete.left")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .buttonRepeatBehavior(.enabled)
                    .accessibilityLabel("Стереть")
                }
                .padding(.trailing, 8)
            }
        }
        .frame(height: 46)
    }

    private func modeButton(_ title: String, mode: StickerPanelModel.Mode) -> some View {
        let selected = model.mode == mode
        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { model.mode = mode }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(selected ? Color(uiColor: .systemBackground) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Ячейка эмодзи: обычный — текстом, анимодзи — Lottie поверх своего эмодзи.
private struct EmojiCell: View {
    let item: EmojiItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Group {
                if let animated = item.animated, let icon = animated.iconURL {
                    // В сетке — картинка анимодзи: десятки Lottie сразу тормозили панель.
                    // Анимация играет в отправленном сообщении.
                    RemoteImage(url: icon, maxPixel: 102) {
                        Text(item.emoji).font(.system(size: 30))
                    }
                    .frame(width: 34, height: 34)
                } else {
                    Text(item.emoji).font(.system(size: 30))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(item.emoji)
    }
}

/// Ячейка стикера: пока стикер не загружен — серая заглушка. Долгое нажатие — крупный
/// просмотр с «Отправить».
private struct StickerCell: View {
    let sticker: Sticker?
    let onSend: (Sticker) -> Void

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            if let sticker {
                Button { onSend(sticker) } label: {
                    // В сетке картинка, Lottie — только если картинки нет (и стоит на первом
                    // кадре); анимация — в крупном просмотре и в сообщении.
                    AnimatedSticker(lottieURL: sticker.url == nil ? sticker.lottieURL : nil, stillURL: sticker.url, size: side, playing: false) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
                .contextMenu {
                    Button("Отправить", systemImage: "paperplane") { onSend(sticker) }
                } preview: {
                    AnimatedSticker(lottieURL: sticker.lottieURL, stillURL: sticker.url, size: 240)
                        .padding(12)
                }
                .accessibilityLabel(sticker.tags.first.map { "Стикер \($0)" } ?? "Стикер")
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .padding(4)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Нажатие слегка уменьшает ячейку.
private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
