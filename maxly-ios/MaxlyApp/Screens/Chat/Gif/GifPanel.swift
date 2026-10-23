import SwiftUI
import MaxlyData
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Раздел «GIF» панели на месте клавиатуры: поиск гифок и стикеров gifka.me. Стикеры MAX —
/// в соседнем разделе «Стикеры». Найденное уходит файлом GIF через обычную загрузку фото.
struct GifPanel: View {
    enum Tab: String, CaseIterable, Identifiable {
        case gifs, gifkaStickers
        var id: String { rawValue }
        var title: String {
            switch self {
            case .gifs: "GIF"
            case .gifkaStickers: "Стикеры gifka.me"
            }
        }
    }

    let onPickGifka: (GifkaMedia, GifkaClient) -> Void

    @AppStorage(GifkaSettings.enabledKey) private var searchEnabled = false
    @State private var tab: Tab = .gifs
    @State private var gifs: GifSearchModel
    @State private var gifkaStickers: GifSearchModel
    @State private var failure: String?
    /// Ответ на жалобу: «Жалоба отправлена» или ошибка.
    @State private var reportNotice: String?
    /// Показы, выбор и отправка для gifka.me (`POST /v1/pingback`); без ключа `nil`.
    @State private var pingback: GifkaPingback?

    init(onPickGifka: @escaping (GifkaMedia, GifkaClient) -> Void) {
        self.onPickGifka = onPickGifka
        let client = GifkaClient(apiKey: GifkaSettings.apiKey)
        _pingback = State(initialValue: GifkaPingback(client: client))
        _gifs = State(initialValue: GifSearchModel(type: .gif, client: client))
        _gifkaStickers = State(initialValue: GifSearchModel(type: .sticker, client: client))
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("Раздел", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            Group {
                switch tab {
                case .gifs: gifkaPane(gifs)
                case .gifkaStickers: gifkaPane(gifkaStickers)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 4)
        .alert("Нельзя отправить", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
        .alert(reportNotice ?? "", isPresented: Binding(get: { reportNotice != nil }, set: { if !$0 { reportNotice = nil } })) {
            Button("OK", role: .cancel) { reportNotice = nil }
        }
        .onDisappear {
            let pingback = pingback
            Task { await pingback?.flush() }
        }
    }

    // MARK: gifka.me

    @ViewBuilder
    private func gifkaPane(_ model: GifSearchModel) -> some View {
        if !searchEnabled {
            VStack(spacing: 12) {
                Text("Поиск GIF выключен")
                    .font(.app(.headline))
                Text("Поиск идёт через gifka.me: текст запроса и ваш IP-адрес уходят на их сервер.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Включить поиск") { searchEnabled = true }
                    .buttonStyle(.borderedProminent)
                Text("Позже его можно выключить в «Настройки → Сообщения».")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        } else {
            GifkaResults(
                model: model,
                pingback: pingback,
                onReport: GifkaSettings.reportsEnabled ? { media, reason in report(media, reason: reason, client: model.client) } : nil
            ) { media in send(media, client: model.client) }
        }
    }

    /// В сетке только лёгкие превью; файл GIF качает чат уже после выбора (лист закрыт,
    /// внизу видна загрузка с отменой).
    private func send(_ media: GifkaMedia, client: GifkaClient) {
        let pingback = pingback
        Task { await pingback?.click(media.id) }
        guard media.canSendGIF(hasKey: client.hasKey) else {
            failure = client.hasKey
                ? "Автор запретил скачивать этот файл"
                : "Отправка найденных GIF требует ключа API gifka.me в сборке. Поиск и просмотр работают без него."
            return
        }
        onPickGifka(media, client)
    }

    private func report(_ media: GifkaMedia, reason: GifkaReportReason, client: GifkaClient) {
        Task {
            do {
                try await client.report(media.id, reason: reason)
                reportNotice = "Жалоба отправлена"
            } catch {
                reportNotice = "Не удалось отправить жалобу: \(error.localizedDescription)"
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.app(.subheadline))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Поле поиска, сетка выдачи и подпись «Гифки: gifka.me».
private struct GifkaResults: View {
    @Bindable var model: GifSearchModel
    let pingback: GifkaPingback?
    /// `nil` — жалобы выключены флагом.
    let onReport: ((GifkaMedia, GifkaReportReason) -> Void)?
    let onPick: (GifkaMedia) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(model.type == .gif ? "Поиск GIF" : "Поиск стикеров", text: $model.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Очистить")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)
            ScrollView {
                if let failure = model.failure, model.items.isEmpty {
                    VStack(spacing: 8) {
                        Text(failure).font(.app(.subheadline)).foregroundStyle(.secondary)
                        Button("Повторить") { model.retry() }
                    }
                    .padding(.top, 40)
                } else if model.items.isEmpty, !model.loading {
                    Text("Ничего не нашлось").font(.app(.subheadline)).foregroundStyle(.secondary).padding(.top, 40)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: model.type == .gif ? 2 : 4), spacing: 3) {
                    ForEach(model.items) { media in
                        GifkaCell(media: media, onReport: onReport.map { report in { report(media, $0) } }) { onPick(media) }
                            .onAppear {
                                let pingback = pingback
                                Task { await pingback?.views([media.id]) }
                                if media.id == model.items.last?.id { model.loadMore() }
                            }
                    }
                }
                .padding(.horizontal, 6)
                if model.loading { ProgressView().padding() }
                // Подпись со ссылкой на сайт, которую требуют условия API.
                Link(destination: GifkaSettings.siteURL) {
                    Text("Гифки: ").foregroundStyle(.secondary) + Text("gifka.me").underline()
                }
                .font(.app(.footnote))
                .accessibilityHint("Открывает сайт gifka.me")
                    .padding(.vertical, 10)
                    .padding(.bottom, 70)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .onAppear { model.start() }
    }
}

/// Ячейка выдачи: гифка — ролик MP4 без звука, стикер — картинка WebP.
private struct GifkaCell: View {
    let media: GifkaMedia
    var onReport: ((GifkaReportReason) -> Void)?
    let onTap: () -> Void

    var body: some View {
        if let onReport {
            button.contextMenu {
                Menu {
                    ForEach(GifkaReportReason.allCases) { reason in
                        Button(reason.title) { onReport(reason) }
                    }
                } label: {
                    Label("Пожаловаться", systemImage: "exclamationmark.bubble")
                }
            }
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: onTap) {
            ZStack {
                RemoteImage(url: (media.previewWebP() ?? media.poster)?.url, maxPixel: 400) {
                    Color.secondary.opacity(0.12)
                }
                .scaledToFill()
                if media.kind == .gif, let mp4 = media.previewMP4() {
                    GifLoopView(url: mp4.url)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(media.kind == .gif ? max(0.6, min(1.8, media.aspect)) : 1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(media.title.isEmpty ? (media.kind == .gif ? "GIF" : "Стикер") : media.title)
    }
}

/// Гифка, которая качается и уходит после выбора. Если не ушла — строка остаётся
/// с ошибкой и кнопкой «Повторить».
struct GifDownload {
    let id: UUID
    let media: GifkaMedia
    let client: GifkaClient
    var task: Task<Void, Never>?
    var failure: String?

    var title: String { media.title }
}

/// Строка над полем ввода: «Загружаем GIF…» с отменой, пока файл не ушёл, или ошибка с «Повторить».
struct GifDownloadBar: View {
    let title: String
    var failure: String?
    var onRetry: () -> Void = {}
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if failure == nil {
                ProgressView()
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(failure == nil ? "Загружаем GIF…" : "GIF не отправилась").font(.app(.subheadline, .semibold))
                if let failure {
                    Text(failure).font(.app(.caption)).foregroundStyle(.secondary).lineLimit(2)
                } else if !title.isEmpty {
                    Text(title).font(.app(.caption)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if failure != nil {
                Button("Повторить", action: onRetry)
                    .font(.app(.subheadline, .semibold))
                    .buttonStyle(.borderless)
            }
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(failure == nil ? "Отменить отправку GIF" : "Убрать GIF")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}
