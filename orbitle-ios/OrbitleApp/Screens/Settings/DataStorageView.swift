import Charts
import SwiftUI
import OrbitleDomain
import OrbitlePresentation

/// «Данные и память»: кольцо занятого места, список
/// категорий с отметками и «Очистить», срок хранения медиа и предел кэша. Внизу размер
/// базы сообщений: она нужна для работы без сети и вместе с кэшем не чистится.
struct DataStorageView: View {
    let model: StorageSettingsModel
    @State private var confirmsClear = false

    var body: some View {
        List {
            Section {
                overview
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            if model.isEmpty {
                Section {
                    Label("Кэш пуст", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            } else if model.usage != nil {
                Section {
                    ForEach(model.categories, id: \.self) { category in
                        categoryRow(category)
                    }
                } header: {
                    Text("Кэш")
                } footer: {
                    Text("Фото, видео и файлы останутся в облаке MAX: после очистки они загрузятся снова, когда понадобятся.")
                }

                Section {
                    Button(role: .destructive) {
                        confirmsClear = true
                    } label: {
                        HStack {
                            Spacer()
                            if model.isClearing {
                                ProgressView()
                            } else {
                                Text(clearTitle)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(model.clearable.isEmpty || model.isClearing)
                }
            }

            Section {
                Picker("Хранить медиа", selection: Binding(
                    get: { model.policy.keepMedia },
                    set: { period in Task { await model.setKeepMedia(period) } }
                )) {
                    ForEach(KeepMediaPeriod.allCases, id: \.self) { period in
                        Text(period.title).tag(period)
                    }
                }
            } footer: {
                Text("Медиа, которые вы не открывали дольше этого срока, удалятся с устройства.")
            }

            Section {
                Picker("Максимальный размер кэша", selection: Binding(
                    get: { model.policy.sizeLimit },
                    set: { limit in Task { await model.setSizeLimit(limit) } }
                )) {
                    ForEach(CacheSizeLimit.allCases, id: \.self) { limit in
                        Text(limit.title).tag(limit)
                    }
                }
            } footer: {
                Text("Если кэш больше, первыми удаляются медиа, которые открывали давно.")
            }

            if let usage = model.usage {
                Section {
                    LabeledContent("База сообщений", value: StorageSettingsModel.format(usage.database))
                } footer: {
                    Text("Чаты и сообщения для работы без сети. При очистке кэша они не удаляются.")
                }
            }
        }
        .navigationTitle("Данные и память")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        .confirmationDialog("Очистить кэш?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button(clearTitle, role: .destructive) {
                Task { await model.clearSelected() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Выбранные медиа удалятся с этого устройства. В чатах они останутся.")
        }
    }

    private var clearTitle: String {
        let bytes = model.selectedBytes
        return bytes > 0 ? "Очистить \(StorageSettingsModel.format(bytes))" : "Очистить"
    }

    // MARK: Кольцо

    @ViewBuilder
    private var overview: some View {
        VStack(spacing: 14) {
            ZStack {
                if let usage = model.usage, usage.cache > 0 {
                    Chart(model.categories, id: \.self) { category in
                        SectorMark(
                            angle: .value("Размер", Double(model.bytes(category))),
                            innerRadius: .ratio(0.68),
                            angularInset: 1.5
                        )
                        .cornerRadius(3)
                        .foregroundStyle(category.color)
                        .opacity(model.isSelected(category) ? 1 : 0.3)
                    }
                    .chartLegend(.hidden)
                    .animation(.easeInOut(duration: 0.25), value: model.selection)
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 26)
                        .padding(13)
                }
                VStack(spacing: 2) {
                    if let usage = model.usage {
                        Text(StorageSettingsModel.format(usage.cache))
                            .font(.title2.weight(.semibold))
                            .contentTransition(.numericText())
                        Text("кэш")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
            }
            .frame(width: 180, height: 180)
            .accessibilityElement(children: .combine)

            VStack(spacing: 4) {
                if let summary = model.summary {
                    Text(summary)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                if let free = model.freeSpace {
                    Text(free)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: Категории

    private func categoryRow(_ category: StorageCategory) -> some View {
        Button {
            model.toggle(category)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: model.isSelected(category) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(model.isSelected(category) ? category.color : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                Image(systemName: category.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(category.color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.title)
                        .foregroundStyle(.primary)
                    Text(StorageSettingsModel.percent(model.share(category) * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(StorageSettingsModel.format(model.bytes(category)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.isSelected(category) ? .isSelected : [])
    }
}

extension StorageCategory {
    var color: Color {
        switch self {
        case .photos: .blue
        case .videos: .purple
        case .videoNotes: .orange
        case .voice: .green
        case .files: .teal
        case .other: .gray
        }
    }

    var systemImage: String {
        switch self {
        case .photos: "photo.fill"
        case .videos: "play.rectangle.fill"
        case .videoNotes: "video.circle.fill"
        case .voice: "mic.fill"
        case .files: "doc.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}
