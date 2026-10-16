import SwiftUI
import MaxlyData
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Вкладка «GIF» листа вложений: поиск gifka.me (гифки и стикеры).
/// Найденное в gifka.me уходит файлом GIF через обычную загрузку фото.
struct GifPanel: View {
    enum Tab: String, CaseIterable, Identifiable {
        case gifs, gifkaStickers
        var id: String { rawValue }
        var title: String {
            switch self {
            case .gifs: "GIF"
            case .gifkaStickers: "Стикеры"
            }
        }
    }

    let onSendGIF: (AttachmentDraft) -> Void

    @AppStorage(GifkaSettings.enabledKey) private var searchEnabled = false
    @State private var tab: Tab = .gifs
    @State private var gifs: GifSearchModel
    @State private var gifkaStickers: GifSearchModel
    @State private var sending: String?
    @State private var failure: String?

    init(onSendGIF: @escaping (AttachmentDraft) -> Void) {
        self.onSendGIF = onSendGIF
        let client = GifkaClient(apiKey: GifkaSettings.apiKey)
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
        .alert("Не отправилось", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
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
            GifkaResults(model: model, sending: sending) { media in send(media, client: model.client) }
        }
    }

    private func send(_ media: GifkaMedia, client: GifkaClient) {
        guard media.canSendGIF(hasKey: client.hasKey) else {
            failure = client.hasKey
                ? "Автор запретил скачивать этот файл"
                : "Отправка найденных GIF требует ключа API gifka.me в сборке. Поиск и просмотр работают без него."
            return
        }
        guard sending == nil else { return }
        sending = media.id
        Task {
            defer { sending = nil }
            do {
                let data = try await client.downloadGIF(media)
                let draft = try MediaExporter.draft(gifData: data)
                onSendGIF(draft)
            } catch {
                failure = error.localizedDescription
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
    let sending: String?
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
                        GifkaCell(media: media, sending: sending == media.id) { onPick(media) }
                            .onAppear { if media.id == model.items.last?.id { model.loadMore() } }
                    }
                }
                .padding(.horizontal, 6)
                if model.loading { ProgressView().padding() }
                // Подпись, которую требуют условия API.
                Link("Гифки: gifka.me", destination: GifkaSettings.siteURL)
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
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
    let sending: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RemoteImage(url: (media.previewWebP() ?? media.poster)?.url, maxPixel: 400) {
                    Color.secondary.opacity(0.12)
                }
                .scaledToFill()
                if media.kind == .gif, let mp4 = media.previewMP4() {
                    GifLoopView(url: mp4.url)
                }
                if sending {
                    Color.black.opacity(0.35)
                    ProgressView().tint(.white)
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

