import SwiftUI
import MaxlyData
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Раздел «GIF» панели на месте клавиатуры: поиск гифок и стикеров gifka.me. Стикеры MAX —
/// в соседнем разделе «Стикеры». Найденное уходит файлом GIF через обычную загрузку фото.
/// Выдача и запрос живут в `GifPanelModel` экрана чата и не сбрасываются при закрытии панели.
struct GifPanel: View {
    @Bindable var model: GifPanelModel
    /// Гифку можно отправить: чат ставит её в очередь отправки.
    let onPick: (GifkaMedia, GifkaClient) -> Void

    @AppStorage(GifkaSettings.enabledKey) private var searchEnabled = false
    @FocusState private var fieldFocused: Bool
    @State private var failure: String?
    /// Ответ на жалобу: «Жалоба отправлена» или ошибка.
    @State private var reportNotice: String?

    var body: some View {
        VStack(spacing: 8) {
            if searchEnabled {
                searchField
                Picker("Раздел", selection: $model.section) {
                    ForEach(GifPanelModel.Section.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                GifkaResults(
                    model: model.active,
                    pingback: model.pingback,
                    onReport: GifkaSettings.reportsEnabled ? { media, reason in report(media, reason: reason) } : nil
                ) { media in send(media) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                disabledNotice
            }
        }
        .padding(.top, 8)
        .alert("Нельзя отправить", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
        .alert(reportNotice ?? "", isPresented: Binding(get: { reportNotice != nil }, set: { if !$0 { reportNotice = nil } })) {
            Button("OK", role: .cancel) { reportNotice = nil }
        }
        .onAppear { if searchEnabled { model.appear() } }
        .onChange(of: searchEnabled) { _, enabled in if enabled { model.appear() } }
        .onChange(of: fieldFocused) { _, focused in model.isSearching = focused }
        .onDisappear { model.disappear() }
    }

    /// Один запрос на оба раздела: переключение «GIF | Стикеры» ищет то же самое.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(model.section == .gifs ? "Поиск GIF" : "Поиск стикеров", text: $model.query)
                .focused($fieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { fieldFocused = false }
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
    }

    private var disabledNotice: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// В сетке только лёгкие превью; файл GIF качает очередь отправки уже после выбора
    /// (над полем ввода видна загрузка с отменой).
    private func send(_ media: GifkaMedia) {
        let client = model.client
        let pingback = model.pingback
        Task { await pingback?.click(media.id) }
        guard media.canSendGIF(hasKey: client.hasKey) else {
            failure = client.hasKey
                ? "Автор запретил скачивать этот файл"
                : "Отправка найденных GIF требует ключа API gifka.me в сборке. Поиск и просмотр работают без него."
            return
        }
        onPick(media, client)
    }

    private func report(_ media: GifkaMedia, reason: GifkaReportReason) {
        let client = model.client
        Task {
            do {
                try await client.report(media.id, reason: reason)
                reportNotice = "Жалоба отправлена"
            } catch {
                reportNotice = "Не удалось отправить жалобу: \(GifkaSettings.message(error))"
            }
        }
    }
}

/// Сетка выдачи, подгрузка страниц и подпись «Гифки: gifka.me».
private struct GifkaResults: View {
    let model: GifSearchModel
    let pingback: GifkaPingback?
    /// `nil` — жалобы выключены флагом.
    let onReport: ((GifkaMedia, GifkaReportReason) -> Void)?
    let onPick: (GifkaMedia) -> Void

    var body: some View {
        ScrollView {
            if let failure = model.failure, model.items.isEmpty {
                VStack(spacing: 8) {
                    Text(failure)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Повторить") { model.retry() }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            } else if model.items.isEmpty, !model.loading {
                Text(model.query.isEmpty ? "Пока пусто" : "Ничего не нашлось")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
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
            if model.loading {
                ProgressView().padding()
            } else if let failure = model.failure, !model.items.isEmpty {
                // Следующая страница не пришла: выдача остаётся, внизу — «Повторить».
                Button("Повторить") { model.loadMore(retrying: true) }
                    .font(.app(.subheadline))
                    .accessibilityHint(failure)
                    .padding()
            }
            // Подпись со ссылкой на сайт, которую требуют условия API.
            Link(destination: GifkaSettings.siteURL) {
                Text("Гифки: ").foregroundStyle(.secondary) + Text("gifka.me").underline()
            }
            .font(.app(.footnote))
            .accessibilityHint("Открывает сайт gifka.me")
            .padding(.vertical, 10)
        }
        .scrollDismissesKeyboard(.immediately)
        // Другой раздел — своя прокрутка с начала.
        .id(ObjectIdentifier(model))
    }
}

/// Ячейка выдачи: гифка — ролик MP4 без звука, стикер — картинка WebP.
private struct GifkaCell: View {
    let media: GifkaMedia
    var onReport: ((GifkaReportReason) -> Void)?
    let onTap: () -> Void
    /// «Автовоспроизведение GIF» из настроек: без него в сетке стоит первый кадр.
    @Environment(\.gifAutoplay) private var gifAutoplay

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
                if media.kind == .gif, let mp4 = media.previewMP4(),
                   GifAutoplayPolicy.shouldPlay(allowed: gifAutoplay, hasVideo: true, visible: true) {
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

/// Строка над полем ввода: «Загружаем GIF…» с отменой, пока файл не ушёл, или ошибка с «Повторить».
/// Справа от заголовка — сколько гифок ждут за текущей.
struct GifDownloadBar: View {
    let title: String
    var failure: String?
    var waiting = 0
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
                HStack(spacing: 4) {
                    Text(failure == nil ? "Загружаем GIF…" : "GIF не отправилась").font(.app(.subheadline, .semibold))
                    if waiting > 0 {
                        Text("· ещё \(waiting)").font(.app(.subheadline)).foregroundStyle(.secondary)
                    }
                }
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
