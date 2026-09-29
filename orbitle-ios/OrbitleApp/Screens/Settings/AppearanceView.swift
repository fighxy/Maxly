import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// «Оформление»: предпросмотр, размер текста и тема.
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
                AppearancePreview()
                    .dynamicTypeSize(shown.dynamicTypeSize)
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
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
        // Шаг сменился не пальцем (VoiceOver, клавиатура): применить сразу.
        .onChange(of: position) {
            if !isDragging { settings.setTextSize(shown) }
        }
    }
}

/// Образец: строка списка чатов и два сообщения из настоящих компонентов приложения.
struct AppearancePreview: View {
    private let item: ChatListItem
    private let incoming: Message
    private let outgoing: Message

    init(now: Date = Date()) {
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
        }
        .padding(.vertical, 6)
        .allowsHitTesting(false)
    }
}
