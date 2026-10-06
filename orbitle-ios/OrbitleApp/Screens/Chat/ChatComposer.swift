import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Поле ввода чата: ошибка и подсказки над ним, правка и ответ, поле со скрепкой,
/// запись голосового и кружка, отправка. Вынесено из `ChatView`: поле перерисовывается
/// при наборе текста, а лента в это время не трогается.
struct ChatComposer: View {
    @Bindable var viewModel: ChatViewModel
    let recording: RecordingSession
    var focus: FocusState<Bool>.Binding
    @Binding var attachmentsShown: Bool
    /// Панель эмодзи и стикеров на месте клавиатуры.
    @Binding var panelShown: Bool
    let canWrite: Bool
    /// Плашка вместо поля ввода. Нет, пока не ясно, можно ли писать (чат вне списка ждёт карточку).
    var showsReadOnlyBar = true
    let chatType: ChatType
    let isMuted: Bool
    let onToggleMute: (() -> Void)?
    /// «Открыть приложение» бота с мини-приложением. `nil` — кнопки нет.
    var onOpenApp: (() -> Void)? = nil
    /// «Подписаться» или «Вступить» вместо плашки у канала или группы вне списка.
    var join: Join? = nil

    struct Join {
        let label: String
        let busy: Bool
        let action: () -> Void
    }
    /// Отступ поля ввода от краёв.
    static let inset: CGFloat = 12
    @Environment(\.privateMode) private var privateMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Стекло поля ввода: скрепка перетекает в поле и обратно (iOS 26).
    @Namespace private var composerGlass

    var body: some View { composer }

    /// Плавающий пузырь ввода: капсула поля и кнопка отправки на стекле (iOS 26),
    /// на iOS 17–18 — на материале.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .orbitleGlassCapsule()
                    .transition(.orbitleBar(edge: .bottom, reduceMotion: reduceMotion))
            }
            if let hint = recording.hint {
                Text(hint)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .orbitleGlassCapsule()
                    .frame(maxWidth: .infinity)
                    .transition(.orbitleBar(edge: .bottom, reduceMotion: reduceMotion))
            }
            if !viewModel.mentionHints.isEmpty {
                hintRow(viewModel.mentionHints.map(\.name)) { name in
                    if let member = viewModel.mentionHints.first(where: { $0.name == name }) {
                        viewModel.insertMention(member)
                    }
                }
            }
            if !viewModel.commandHints.isEmpty {
                hintRow(viewModel.commandHints.map(\.name)) { name in
                    if let command = viewModel.commandHints.first(where: { $0.name == name }) {
                        viewModel.insertCommand(command)
                    }
                }
            }
            if let notice = viewModel.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .orbitleGlassCapsule()
                    .frame(maxWidth: .infinity)
                    .transition(.orbitleBar(edge: .bottom, reduceMotion: reduceMotion))
            }
            if let target = viewModel.editTarget {
                editBar(target)
            } else if let reply = viewModel.replyTarget {
                replyBar(reply)
            }
            if let onOpenApp {
                Button(action: onOpenApp) {
                    Label("Открыть приложение", systemImage: "square.grid.2x2.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.orbitleAccent)
                .orbitleGlassCapsule()
            }
            if canWrite {
                input
            } else if showsReadOnlyBar {
                readOnlyBar
            }
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: viewModel.editTarget?.id)
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: viewModel.replyTarget?.id)
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: recording.hint)
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: viewModel.errorMessage)
    }

    /// Поле ввода и кнопка отправки (при правке — галочка).
    private var input: some View {
        VStack(spacing: 0) {
            OrbitleGlassGroup(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    if recording.isActive {
                        RecordingBar(session: recording)
                            .transition(.opacity)
                    }
                    if !recording.isActive {
                        Button {
                            focus.wrappedValue = false
                            attachmentsShown = true
                        } label: {
                            Image(systemName: "paperclip")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .orbitleGlassCircle(size: 44)
                        .orbitleGlassID("attach", in: composerGlass)
                        // При правке слот сохраняется: длинный текст не получает
                        // дополнительный перенос из-за смены ширины на 52 pt.
                        .opacity(viewModel.editTarget == nil ? 1 : 0)
                        .disabled(viewModel.editTarget != nil)
                        .accessibilityHidden(viewModel.editTarget != nil)
                        .transition(.orbitlePop(reduceMotion: reduceMotion))
                        .accessibilityLabel("Прикрепить")
                    }
                    if !recording.isActive {
                        HStack(alignment: .bottom, spacing: 0) {
                            TextField("Сообщение", text: $viewModel.draft, axis: .vertical)
                                .focused(focus)
                                .lineLimit(1...5)
                                .textFieldStyle(.plain)
                                .padding(.leading, 16)
                                .padding(.vertical, 11)
                            panelButton
                        }
                        .frame(minHeight: 44)
                        .orbitleGlassRounded(radius: 22)
                        .orbitleGlassID("field", in: composerGlass)
                    }
                    ZStack {
                        if showsRecordButton {
                            RecordButton(session: recording)
                                .transition(.opacity)
                        } else {
                            sendButton.transition(.opacity)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: showsRecordButton)
                }
            }
        }
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: recording.isActive)
        // Скрепка прячется при правке и возвращается после неё.
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: viewModel.editTarget == nil)
    }

    private func hintRow(_ titles: [String], onPick: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(titles, id: \.self) { title in
                    Button(title) { onPick(title) }
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .orbitleGlassCapsule()
                }
            }
        }
    }

    /// Смайлик в поле ввода открывает панель эмодзи и стикеров вместо клавиатуры, на открытой
    /// панели он становится клавиатурой и возвращает её.
    private var panelButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                if panelShown {
                    panelShown = false
                    focus.wrappedValue = true
                } else {
                    focus.wrappedValue = false
                    panelShown = true
                }
            }
        } label: {
            Image(systemName: panelShown ? "keyboard" : "face.smiling")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 42, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(panelShown ? "Клавиатура" : "Эмодзи и стикеры")
    }

    /// Кнопка записи видна, пока поле пустое (и не идёт правка) или пока идёт запись.
    private var showsRecordButton: Bool {
        recording.phase != .idle
            || (viewModel.editTarget == nil && viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var sendButton: some View {
        Button {
            Task { await viewModel.send() }
        } label: {
            Image(systemName: viewModel.editTarget == nil ? "arrow.up" : "checkmark")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentTransition(.symbolEffect(.replace))
        }
        .orbitleProminentButtonStyle()
        .buttonBorderShape(.circle)
        .tint(Color.orbitleAccent)
        .disabled(!viewModel.canSend)
        .accessibilityLabel(viewModel.editTarget == nil ? "Отправить" : "Сохранить правку")
    }

    /// Писать нельзя: вне списка — «Подписаться» или «Вступить», в канале — кнопка звука, как в
    /// Telegram, в остальных — пояснение. Кнопки — небольшие капсулы по центру, не во всю ширину.
    @ViewBuilder
    private var readOnlyBar: some View {
        if let join {
            Button(action: join.action) {
                ZStack {
                    Text(join.label)
                        .font(.subheadline.weight(.semibold))
                        .opacity(join.busy ? 0 : 1)
                    if join.busy { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 22)
                .frame(minHeight: 38)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.orbitleAccent)
            .orbitleGlassCapsule()
            .disabled(join.busy)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(join.label)
        } else if chatType == .channel, let onToggleMute {
            Button(action: onToggleMute) {
                Label(isMuted ? "Включить звук" : "Выключить звук", systemImage: isMuted ? "bell" : "bell.slash")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 38)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.orbitleAccent)
            .orbitleGlassCapsule()
            .frame(maxWidth: .infinity)
        } else {
            Text("Писать в этот чат нельзя")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
                .orbitleGlassCapsule()
        }
    }

    private func editBar(_ message: Message) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.orbitleAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Редактирование")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.orbitleAccent)
                Text(privateMode.isMasked ? PrivateModeMask.messageText(outgoing: true) : message.text)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 9)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.orbitleAccent)
                    .frame(width: 3)
            }
            Spacer(minLength: 8)
            Button {
                viewModel.cancelEdit()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отменить правку")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
        .orbitleGlassRounded(radius: 20)
        .transition(.orbitleBar(edge: .bottom, reduceMotion: reduceMotion))
    }

    private func replyTitle(_ message: Message) -> String {
        if viewModel.isOutgoing(message) { return "Вы" }
        let name = message.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Ответ" : name
    }

    private func replyBar(_ message: Message) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.orbitleAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(privateMode.isMasked ? "Ответ" : replyTitle(message))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.orbitleAccent)
                    .lineLimit(1)
                Text(privateMode.isMasked ? PrivateModeMask.messageText(outgoing: viewModel.isOutgoing(message)) : message.replySnippet)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 9)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.orbitleAccent)
                    .frame(width: 3)
            }
            Spacer(minLength: 8)
            Button {
                viewModel.cancelReply()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отменить ответ")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
        .orbitleGlassRounded(radius: 20)
        .transition(.orbitleBar(edge: .bottom, reduceMotion: reduceMotion))
    }
}
