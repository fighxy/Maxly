import AVFoundation
import SwiftUI
import UIKit
import OrbitleCallMedia
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Видео звонка по id дорожки.
struct CallVideo: UIViewRepresentable {
    let trackId: String?
    var fills = true

    func makeUIView(context: Context) -> CallVideoUIView {
        let view = CallVideoUIView()
        view.fills = fills
        view.trackId = trackId
        return view
    }

    func updateUIView(_ view: CallVideoUIView, context: Context) {
        view.fills = fills
        view.trackId = trackId
        view.refresh()
    }

    static func dismantleUIView(_ view: CallVideoUIView, coordinator: ()) {
        view.detach()
    }
}

/// Экран звонка: собеседник или участники, статус, кнопки.
struct CallScreen: View {
    @Bindable var center: CallCenter
    /// Ответить на входящий (с камерой или без): приложение сначала спрашивает микрофон.
    let onAnswer: (Bool) -> Void
    @State private var sharesLink = false

    var body: some View {
        if let call = center.call {
            ZStack {
                background(call)
                VStack(spacing: 0) {
                    topBar(call)
                    if isGrid(call) {
                        ParticipantsGrid(center: center, call: call)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                    } else {
                        header(call)
                            .padding(.top, mainVideo(call) == nil ? 48 : 8)
                    }
                    Spacer(minLength: 12)
                    if let notice = call.state.notice {
                        Text(notice)
                            .font(.footnote)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 12)
                    }
                    controls(call)
                        .padding(.bottom, 24)
                }
                if !isGrid(call), let local = call.state.localTrack, !call.state.isEnded {
                    localPreview(local)
                }
            }
            .foregroundStyle(.white)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $sharesLink) {
                if let link = call.joinLink {
                    CallLinkSheet(link: link, onJoin: nil)
                }
            }
        }
    }

    // MARK: Фон и шапка

    @ViewBuilder
    private func background(_ call: CallCenter.Call) -> some View {
        if let track = mainVideo(call) {
            CallVideo(trackId: track, fills: true)
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 220)
                        .ignoresSafeArea()
                }
        } else {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.13, blue: 0.20), Color(red: 0.04, green: 0.05, blue: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private func topBar(_ call: CallCenter.Call) -> some View {
        HStack {
            Button {
                center.minimize()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Свернуть звонок")
            Spacer()
            if call.state.recording {
                Label("Запись", systemImage: "record.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            }
            Spacer()
            if !call.isRinging, !call.state.isEnded {
                moreMenu(call)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
    }

    private func moreMenu(_ call: CallCenter.Call) -> some View {
        Menu {
            if call.state.cameraOn {
                Button {
                    Task { await center.switchCamera() }
                } label: {
                    Label("Сменить камеру", systemImage: "arrow.triangle.2.circlepath.camera")
                }
            }
            Button {
                Task { await center.toggleScreenSharing() }
            } label: {
                Label(call.state.screenSharing ? "Остановить показ экрана" : "Показать экран",
                      systemImage: call.state.screenSharing ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle")
            }
            if call.joinLink != nil {
                Button {
                    sharesLink = true
                } label: {
                    Label("Ссылка на звонок", systemImage: "link")
                }
            }
            if canRecord(call) {
                Button {
                    Task { await center.toggleRecording() }
                } label: {
                    Label(call.state.recording ? "Остановить запись" : "Записать звонок", systemImage: "record.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Ещё")
    }

    private func header(_ call: CallCenter.Call) -> some View {
        VStack(spacing: 10) {
            if mainVideo(call) == nil {
                AvatarView(title: call.peer.name, id: call.peer.id.isEmpty ? call.conversationId : call.peer.id, url: call.peer.avatarURL, size: 128)
                    .overlay {
                        if call.state.others.first?.speaking == true {
                            Circle().stroke(Color.green, lineWidth: 3).padding(-6)
                        }
                    }
                    .padding(.bottom, 8)
            }
            Text(call.peer.name.isEmpty ? "Звонок" : call.peer.name)
                .font(mainVideo(call) == nil ? .title.weight(.semibold) : .title3.weight(.semibold))
                .lineLimit(1)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(CallStatusText.status(of: call, now: context.date))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }
            if let other = call.state.others.first, !other.audioOn, call.state.phase == .active {
                Label("Микрофон собеседника выключен", systemImage: "mic.slash.fill")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(mainVideo(call) == nil ? 0 : 0.4), radius: 4)
    }

    private func localPreview(_ track: String) -> some View {
        VStack {
            HStack {
                Spacer()
                CallVideo(trackId: track, fills: true)
                    .frame(width: 104, height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 1))
                    .shadow(radius: 6)
                    .onTapGesture {
                        Task { await center.switchCamera() }
                    }
                    .accessibilityLabel("Ваше видео. Нажмите, чтобы сменить камеру")
            }
            Spacer()
        }
        .padding(.top, 60)
        .padding(.trailing, 14)
    }

    // MARK: Кнопки

    @ViewBuilder
    private func controls(_ call: CallCenter.Call) -> some View {
        if call.isRinging {
            HStack(spacing: 40) {
                CallRoundButton(title: "Отклонить", systemImage: "phone.down.fill", fill: .red) {
                    Task { await center.decline() }
                }
                if call.isVideo {
                    CallRoundButton(title: "С видео", systemImage: "video.fill", fill: .green) { onAnswer(true) }
                }
                CallRoundButton(title: "Ответить", systemImage: "phone.fill", fill: .green) { onAnswer(false) }
            }
        } else if call.state.isEnded {
            CallRoundButton(title: "Закрыть", systemImage: "xmark", fill: .white.opacity(0.2)) {
                Task { await center.hangUp() }
            }
        } else {
            VStack(spacing: 22) {
                HStack(spacing: 18) {
                    CallToggle(title: "Динамик", systemImage: "speaker.wave.2.fill", isOn: call.state.speakerOn) {
                        center.toggleSpeaker()
                    }
                    CallToggle(title: "Видео", systemImage: call.state.cameraOn ? "video.fill" : "video.slash.fill", isOn: call.state.cameraOn) {
                        Task { await center.toggleCamera() }
                    }
                    CallToggle(title: "Микрофон", systemImage: call.state.muted ? "mic.slash.fill" : "mic.fill", isOn: call.state.muted) {
                        Task { await center.toggleMute() }
                    }
                    CallToggle(title: "Экран", systemImage: "rectangle.on.rectangle", isOn: call.state.screenSharing) {
                        Task { await center.toggleScreenSharing() }
                    }
                }
                CallRoundButton(title: "Завершить", systemImage: "phone.down.fill", fill: .red) {
                    Task { await center.hangUp() }
                }
            }
        }
    }

    // MARK: Внутреннее

    private func isGrid(_ call: CallCenter.Call) -> Bool {
        call.direction == .group || call.state.others.count > 1
    }

    /// Видео собеседника на весь экран (звонок на двоих).
    private func mainVideo(_ call: CallCenter.Call) -> String? {
        guard !isGrid(call), !call.state.isEnded else { return nil }
        return call.state.others.first?.visibleTrack
    }

    private func canRecord(_ call: CallCenter.Call) -> Bool {
        isGrid(call) && (call.state.participants.first { $0.isSelf }?.isAdmin == true || call.state.recording)
    }
}

/// Плитки участников группового звонка: видео или аватар, имя, выключенный микрофон,
/// рамка у говорящего.
private struct ParticipantsGrid: View {
    let center: CallCenter
    let call: CallCenter.Call

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        ScrollView {
            VStack(spacing: 6) {
                Text(call.peer.name)
                    .font(.headline)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(CallStatusText.status(of: call, now: context.date))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.bottom, 8)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(call.state.participants) { participant in
                    tile(participant)
                }
            }
        }
    }

    private func tile(_ participant: CallParticipant) -> some View {
        let name = participant.isSelf ? "Вы" : (center.name(ofUser: participant.userId) ?? "Участник")
        let track = participant.isSelf ? call.state.localTrack : participant.visibleTrack
        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
            if let track {
                CallVideo(trackId: track, fills: true)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                AvatarView(title: name, id: participant.userId ?? String(participant.id), size: 64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 4) {
                if !participant.audioOn {
                    Image(systemName: "mic.slash.fill").font(.caption2)
                }
                if participant.handRaised {
                    Image(systemName: "hand.raised.fill").font(.caption2)
                }
                Text(name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.4), in: Capsule())
            .padding(8)
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(participant.speaking ? Color.green : .clear, lineWidth: 3)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Круглая кнопка-переключатель: включённая — белая с тёмным значком.
private struct CallToggle: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 60, height: 60)
                    .foregroundStyle(isOn ? Color.black : Color.white)
                    .background(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "включено" : "выключено")
    }
}

/// Большая круглая кнопка: ответить, отклонить, завершить.
private struct CallRoundButton: View {
    let title: String
    let systemImage: String
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(fill, in: Circle())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Плашка свёрнутого звонка над приложением: имя и время; нажатие разворачивает звонок.
struct ActiveCallBar: View {
    @Bindable var center: CallCenter

    var body: some View {
        if let call = center.call, !center.isExpanded {
            HStack(spacing: 10) {
                Image(systemName: call.isVideo || call.state.cameraOn ? "video.fill" : "phone.fill")
                    .font(.footnote)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(barText(call, now: context.date))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if !call.isRinging, !call.state.isEnded {
                    Button {
                        Task { await center.toggleMute() }
                    } label: {
                        Image(systemName: call.state.muted ? "mic.slash.fill" : "mic.fill")
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(call.state.muted ? "Включить микрофон" : "Выключить микрофон")
                }
                Button {
                    Task { await center.hangUp() }
                } label: {
                    Image(systemName: "phone.down.fill")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Завершить звонок")
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .foregroundStyle(.white)
            .background(call.isRinging ? Color.orange : Color.green)
            .contentShape(Rectangle())
            .onTapGesture { center.expand() }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Развернуть звонок")
        }
    }

    private func barText(_ call: CallCenter.Call, now: Date) -> String {
        let name = call.peer.name.isEmpty ? "Звонок" : call.peer.name
        return "\(name) · \(CallStatusText.status(of: call, now: now))"
    }
}

/// Звонки поверх приложения: полноэкранный звонок, плашка свёрнутого, ошибки, гудки,
/// датчик приближения и экран без автоблокировки.
struct CallHost: ViewModifier {
    let center: CallCenter?
    let onAnswer: (Bool) -> Void

    func body(content: Content) -> some View {
        if let center {
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    ActiveCallBar(center: center)
                }
                .fullScreenCover(isPresented: Binding(
                    get: { center.call != nil && center.isExpanded },
                    set: { shown in if !shown { center.minimize() } }
                )) {
                    CallScreen(center: center, onAnswer: onAnswer)
                }
                .alert("Звонок", isPresented: Binding(
                    get: { center.errorMessage != nil },
                    set: { if !$0 { center.dismissError() } }
                )) {
                    Button("Понятно", role: .cancel) { center.dismissError() }
                } message: {
                    Text(center.errorMessage ?? "")
                }
                .modifier(CallEffects(center: center))
        } else {
            content
        }
    }
}

/// Побочные эффекты звонка, не видные на экране.
private struct CallEffects: ViewModifier {
    let center: CallCenter
    @State private var ringback = RingbackPlayer()

    func body(content: Content) -> some View {
        content
            .onChange(of: center.playsRingback) { _, plays in
                if plays { ringback.start() } else { ringback.stop() }
            }
            .onChange(of: nearEar) { _, near in
                UIDevice.current.isProximityMonitoringEnabled = near
            }
            .onChange(of: center.call != nil) { _, active in
                UIApplication.shared.isIdleTimerDisabled = active
                if !active { ringback.stop() }
            }
    }

    /// Звонок без видео и без громкой связи: телефон у уха гасит экран.
    private var nearEar: Bool {
        guard let call = center.call, !call.state.isEnded, !call.isRinging else { return false }
        return !call.state.cameraOn && !call.state.speakerOn && call.state.others.allSatisfy { $0.visibleTrack == nil }
    }
}

/// Гудки исходящего: 425 Гц, секунда звука и четыре тишины, как на телефонных линиях.
@MainActor
final class RingbackPlayer {
    private var player: AVAudioPlayer?

    func start() {
        if player == nil {
            player = try? AVAudioPlayer(data: Self.tone())
            player?.numberOfLoops = -1
            player?.volume = 0.5
        }
        player?.currentTime = 0
        player?.play()
    }

    func stop() {
        player?.stop()
    }

    /// WAV в памяти: 8 кГц, 16 бит, моно.
    private static func tone() -> Data {
        let rate = 8_000
        let samples = rate * 5
        var pcm = Data(capacity: samples * 2)
        for index in 0..<samples {
            let value: Int16
            if index < rate {
                let fade = min(1.0, Double(min(index, rate - index)) / 160)
                value = Int16(sin(2 * .pi * 425 * Double(index) / Double(rate)) * 9_000 * fade)
            } else {
                value = 0
            }
            withUnsafeBytes(of: value.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) }
        }
        wav.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count))
        wav.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(rate))
        append(UInt32(rate * 2))
        append(UInt16(2))
        append(UInt16(16))
        wav.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }
}

/// Разрешения для звонка.
enum CallPermissions {
    /// Микрофон: спросить, если ещё не спрашивали.
    static func microphone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .undetermined: return await AVAudioApplication.requestRecordPermission()
        default: return false
        }
    }

    static let microphoneDenied = "Нет доступа к микрофону. Разрешите его Maxly в Настройках, чтобы звонить."
}
