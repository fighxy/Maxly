import SwiftUI
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// «Оформление»: предпросмотр, размер текста, тема и обои чата.
///
/// Пока палец на ползунке, размер меняется только в предпросмотре. Всё приложение
/// перестраивается, когда палец отпущен, иначе список под пальцем прыгал бы.
struct AppearanceView: View {
    let settings: AppearanceSettings

    /// Положение ползунка: номер шага `TextSizeStep`.
    @State private var position: Double
    @State private var isDragging = false

    init(settings: AppearanceSettings) {
        self.settings = settings
        _position = State(initialValue: Double(settings.textSize.index))
    }

    /// Шаг под ползунком: его показывает предпросмотр, в том числе во время движения.
    private var shown: TextSizeStep { TextSizeStep(index: Int(position.rounded())) }

    var body: some View {
        List {
            Section {
                AppearancePreview(wallpaper: settings.wallpaper)
                    .dynamicTypeSize(shown.dynamicTypeSize)
                    .animation(MaxlyMotion.fade, value: settings.wallpaper)
                    .listRowBackground(Color.orbitleBackground)
            } header: {
                Text("Предпросмотр")
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
                Text("Меняет текст в списке чатов, сообщениях, контактах, звонках и настройках. По умолчанию 17 пт, стандартный размер iOS.")
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
            } header: {
                Text("Обои чата")
            } footer: {
                Text("Фон за сообщениями во всех чатах. «Осень (авто)» светлая в светлой теме и тёмная в тёмной.")
            }
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
        // Шаг сменился не пальцем (VoiceOver, клавиатура): применить сразу.
        .onChange(of: position) {
            if !isDragging { settings.setTextSize(shown) }
        }
    }
}

/// Образец: строка списка чатов и два сообщения из настоящих компонентов приложения, сообщения —
/// на выбранных обоях.
struct AppearancePreview: View {
    private let item: ChatListItem
    private let incoming: Message
    private let outgoing: Message
    private let wallpaper: ChatWallpaper

    init(wallpaper: ChatWallpaper = .plain, now: Date = Date()) {
        self.wallpaper = wallpaper
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
            .background { ChatWallpaperBackground(wallpaper: wallpaper) }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .environment(\.chatWallpaper, wallpaper)
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
                            isSelected ? Color.orbitleAccent : Color.secondary.opacity(0.35),
                            lineWidth: isSelected ? 2.5 : 0.5
                        )
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.white, Color.orbitleAccent)
                                .padding(6)
                        }
                    }
                Text(wallpaper.title)
                    .font(.caption)
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
                .fill(wallpaper.hasImage ? Color.orbitleIncomingOnWallpaper : Color.orbitleIncoming)
                .frame(width: 34, height: 11)
                .frame(maxWidth: .infinity, alignment: .leading)
            Capsule()
                .fill(Color.orbitleOutgoing)
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
