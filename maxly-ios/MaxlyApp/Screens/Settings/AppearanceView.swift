import SwiftUI
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// «Оформление»: предпросмотр, шрифт (свой экран: шрифт, толщина, размер текста), тема и обои чата
/// (встроенные и своё фото: «Выбрать фото…», «Сбросить», затемнение и размытие).
struct AppearanceView: View {
    let settings: AppearanceSettings
    let wallpapers: ChatWallpaperLibrary
    @State private var pickingPhoto = false

    var body: some View {
        List {
            Section {
                AppearancePreview(wallpaper: settings.wallpaper, custom: wallpapers.globalBackdrop)
                    .animation(MaxlyMotion.fade, value: settings.wallpaper)
                    .animation(MaxlyMotion.fade, value: wallpapers.globalBackdrop)
                    .listRowBackground(Color.maxlyBackground)
            } header: {
                Text("Предпросмотр")
            }
            Section {
                NavigationLink {
                    FontView(settings: settings)
                } label: {
                    LabeledContent("Шрифт", value: settings.fontSummary)
                }
            } header: {
                Text("Текст")
            } footer: {
                Text("Шрифт, толщина и размер текста во всём приложении.")
            }
            Section {
                Picker("Тема", selection: Binding(
                    get: { settings.theme },
                    set: { settings.setTheme($0) }
                )) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Тема")
            } footer: {
                Text("«Системная» следует оформлению iOS: светлому, тёмному или автоматическому.")
            }
            Section {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(ChatWallpaper.allCases, id: \.self) { wallpaper in
                            WallpaperOption(wallpaper: wallpaper, isSelected: settings.wallpaper == wallpaper) {
                                settings.setWallpaper(wallpaper)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                .listRowInsets(EdgeInsets())
                .sensoryFeedback(.selection, trigger: settings.wallpaper)
                CustomWallpaperRows(library: wallpapers) { pickingPhoto = true }
            } header: {
                Text("Обои чата")
            } footer: {
                Text("Фон за сообщениями во всех чатах. «Осень (авто)» светлая в светлой теме и тёмная в тёмной. Своё фото закрывает выбранные обои и хранится только на этом устройстве; затемнение и размытие — для всех фото. Обои отдельного чата — в его профиле: «Ещё» → «Обои».")
            }
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
        .wallpaperPhotoFlow(isPresented: $pickingPhoto, scope: .global, library: wallpapers)
    }
}

/// «Шрифт»: образец, шрифт всего интерфейса (название каждого — им самим), толщина плавным ползунком
/// и размер текста.
///
/// Шрифт и толщина меняются сразу. Размер, пока палец на ползунке, меняется только в образце: всё
/// приложение перестраивается, когда палец отпущен, иначе список под пальцем прыгал бы.
struct FontView: View {
    let settings: AppearanceSettings

    /// Положение ползунка размера: номер шага `TextSizeStep`.
    @State private var position: Double
    @State private var isDragging = false
    @State private var weight: Double

    init(settings: AppearanceSettings) {
        self.settings = settings
        _position = State(initialValue: Double(settings.textSize.index))
        _weight = State(initialValue: Double(settings.fontWeight))
    }

    /// Шаг под ползунком: его показывает образец, в том числе во время движения.
    private var shown: TextSizeStep { TextSizeStep(index: Int(position.rounded())) }

    var body: some View {
        List {
            Section {
                AppearancePreview(wallpaper: settings.wallpaper)
                    .dynamicTypeSize(shown.dynamicTypeSize)
                    .listRowBackground(Color.maxlyBackground)
            } header: {
                Text("Предпросмотр")
            }
            Section {
                ForEach(AppFont.allCases, id: \.self) { font in
                    FontOption(font: font, isSelected: settings.font == font) {
                        settings.setFont(font)
                    }
                }
            } header: {
                Text("Шрифт")
            }
            Section {
                Slider(
                    value: $weight,
                    in: Double(FontWeightScale.min)...Double(FontWeightScale.max),
                    step: 10
                ) {
                    Text("Толщина")
                } minimumValueLabel: {
                    Text(verbatim: "А")
                        .font(.system(size: 18, weight: .light))
                        .accessibilityHidden(true)
                } maximumValueLabel: {
                    Text(verbatim: "А")
                        .font(.system(size: 18, weight: .bold))
                        .accessibilityHidden(true)
                }
                .accessibilityValue(FontWeightScale.caption(Int(weight)))
                HStack(spacing: 6) {
                    Text(FontWeightScale.caption(Int(weight)))
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    Button("Сбросить") {
                        weight = Double(FontWeightScale.standard)
                    }
                    .buttonStyle(.borderless)
                    .disabled(Int(weight) == FontWeightScale.standard)
                }
            } header: {
                Text("Толщина")
            } footer: {
                Text(settings.font == .system
                    ? "Обычный и полужирный текст меняются вместе. У системного шрифта толщина меняется ступенями."
                    : "Обычный и полужирный текст меняются вместе, плавно.")
            }
            Section {
                Slider(value: $position, in: 0...Double(TextSizeStep.maxIndex), step: 1) {
                    Text("Размер текста")
                } minimumValueLabel: {
                    Text(verbatim: "А")
                        .font(.system(size: 14))
                        .accessibilityHidden(true)
                } maximumValueLabel: {
                    Text(verbatim: "А")
                        .font(.system(size: 24))
                        .accessibilityHidden(true)
                } onEditingChanged: { editing in
                    isDragging = editing
                    if !editing { settings.setTextSize(shown) }
                }
                .accessibilityValue(shown.caption)
                HStack(spacing: 6) {
                    Text(shown.caption)
                        .monospacedDigit()
                    if shown == .standard {
                        Text("по умолчанию")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Сбросить") {
                        position = Double(TextSizeStep.standard.index)
                        settings.resetTextSize()
                    }
                    // Иначе кнопкой становится вся строка списка.
                    .buttonStyle(.borderless)
                    .disabled(shown == .standard)
                }
            } header: {
                Text("Размер текста")
            } footer: {
                Text("По умолчанию 17 пт, стандартный размер iOS.")
            }
        }
        .navigationTitle("Шрифт")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: settings.font)
        // Шаг сменился не пальцем (VoiceOver, клавиатура): применить сразу.
        .onChange(of: position) {
            if !isDragging { settings.setTextSize(shown) }
        }
        // Толщина — сразу, и пальцем тоже: образец и экран показывают её на ходу.
        .onChange(of: weight) {
            settings.setFontWeight(Int(weight.rounded()))
        }
    }
}

/// Строка шрифта: название и образец этим шрифтом, галочка у выбранного.
private struct FontOption: View {
    let font: AppFont
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(font.title)
                        .font(Typography.shared.style(.body, font: font))
                    Text("Съешь же ещё этих мягких булок")
                        .font(Typography.shared.style(.footnote, font: font))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.maxlyAccent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(font.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Образец: строка списка чатов и два сообщения из настоящих компонентов приложения, сообщения —
/// на выбранных обоях.
struct AppearancePreview: View {
    private let item: ChatListItem
    private let incoming: Message
    private let outgoing: Message
    private let wallpaper: ChatWallpaper
    private let custom: CustomWallpaperBackdrop?

    init(wallpaper: ChatWallpaper = .plain, custom: CustomWallpaperBackdrop? = nil, now: Date = Date()) {
        self.wallpaper = wallpaper
        self.custom = custom
        let chat = Chat(
            id: "appearance-preview",
            title: "Анна Смирнова",
            type: .private,
            lastMessageId: "preview-2",
            unreadCount: 2,
            updatedAt: now,
            preview: "Отлично, тогда до встречи в субботу!",
            isOnline: true
        )
        item = ChatListFormatter().item(for: chat, now: now)
        incoming = Message(
            id: "preview-1",
            chatId: chat.id,
            authorId: "peer",
            text: "Добрый вечер! Ты уже в дороге?",
            timestamp: now,
            status: .sent
        )
        outgoing = Message(
            id: "preview-2",
            chatId: chat.id,
            authorId: "me",
            text: "Да, буду минут через десять",
            timestamp: now,
            status: .sent
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            ChatRow(item: item)
            VStack(spacing: 6) {
                MessageBubble(message: incoming, isOutgoing: false)
                MessageBubble(message: outgoing, isOutgoing: true)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background { ChatWallpaperBackground(wallpaper: wallpaper, custom: custom) }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .environment(\.chatWallpaper, wallpaper)
            .environment(\.chatHasPhotoWallpaper, custom != nil)
        }
        .padding(.vertical, 6)
        .allowsHitTesting(false)
    }
}

/// Обои для выбора: уменьшенная картинка с двумя пузырями-образцами и подпись. Выбранные
/// обведены цветом приложения и отмечены галочкой.
private struct WallpaperOption: View {
    let wallpaper: ChatWallpaper
    let isSelected: Bool
    let action: () -> Void

    private static let size = CGSize(width: 66, height: 117)
    private static let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                thumbnail
                    .frame(width: Self.size.width, height: Self.size.height)
                    .overlay { sampleBubbles }
                    .clipShape(Self.shape)
                    .overlay {
                        Self.shape.strokeBorder(
                            isSelected ? Color.maxlyAccent : Color.secondary.opacity(0.35),
                            lineWidth: isSelected ? 2.5 : 0.5
                        )
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.white, Color.maxlyAccent)
                                .padding(6)
                        }
                    }
                Text(wallpaper.title)
                    .font(.app(.caption))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(wallpaper.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch wallpaper {
        case .autumnAuto:
            // Светлая половина и тёмная по диагонали: обои следуют теме.
            ZStack {
                ChatWallpaperBackground(wallpaper: .autumn, thumbnail: true)
                ChatWallpaperBackground(wallpaper: .autumnDark, thumbnail: true)
                    .mask { LowerDiagonal() }
            }
        default:
            ChatWallpaperBackground(wallpaper: wallpaper, thumbnail: true)
        }
    }

    /// Два крошечных пузыря: видно, как сообщения лягут на обои.
    private var sampleBubbles: some View {
        VStack(spacing: 5) {
            Capsule()
                .fill(wallpaper.hasImage ? Color.maxlyIncomingOnWallpaper : Color.maxlyIncoming)
                .frame(width: 34, height: 11)
                .frame(maxWidth: .infinity, alignment: .leading)
            Capsule()
                .fill(Color.maxlyOutgoing)
                .frame(width: 28, height: 11)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 7)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// Нижний правый треугольник прямоугольника: половина образца «Осень (авто)».
private struct LowerDiagonal: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
