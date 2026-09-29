import SwiftUI
import UniformTypeIdentifiers
import OrbitleData
import OrbitleDomain

/// Раздел «Отладка»: запись журнала, его размер, выгрузка ZIP и очистка.
///
/// Выгрузка открывает системное окно сохранения: там можно выбрать «На iPhone → Загрузки»
/// или iCloud Drive. Сам iOS не даёт приложению писать в «Загрузки» без выбора человека.
struct LogSettingsSection: View {
    let container: AppContainer

    @State private var isEnabled = true
    @State private var size = 0
    @State private var archive: LogArchive?
    @State private var isExporting = false
    @State private var isPreparing = false
    @State private var confirmClear = false
    @State private var message: String?

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { value in
                    isEnabled = value
                    container.setLogging(value)
                }
            )) {
                Label("Записывать журнал", systemImage: "doc.text.magnifyingglass")
            }
            LabeledContent("Размер журнала", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            Button {
                Task { await prepareArchive() }
            } label: {
                HStack {
                    Label("Выгрузить журнал (ZIP)", systemImage: "square.and.arrow.down")
                    if isPreparing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isPreparing || container.logs == nil)
            Button("Очистить журнал", role: .destructive) { confirmClear = true }
                .disabled(size == 0)
        } header: {
            Text("Отладка")
        } footer: {
            Text("В журнал попадают шаги входа, состояние соединения, синхронизация и ошибки. Коды, пароли и текст сообщений не записываются, номер телефона скрыт. Архив можно сохранить в «Файлы» → «На iPhone» → «Загрузки».")
        }
        .onAppear(perform: reload)
        .fileExporter(
            isPresented: $isExporting,
            document: archive,
            contentType: .zip,
            defaultFilename: archive?.filename
        ) { result in
            switch result {
            case .success(let url):
                Log.info(.app, "Журнал выгружен: \(url.lastPathComponent)")
                message = "Архив сохранён: \(url.lastPathComponent)"
            case .failure(let error):
                Log.warning(.app, "Выгрузка журнала не удалась: \(error)")
                message = "Не удалось сохранить архив"
            }
            archive = nil
        }
        .confirmationDialog("Очистить журнал?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Очистить", role: .destructive) {
                container.logs?.clear()
                Log.info(.app, "Журнал очищен")
                reload()
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func reload() {
        isEnabled = container.logs?.isEnabled ?? false
        size = container.logs?.totalSize() ?? 0
    }

    private func prepareArchive() async {
        guard let logs = container.logs else { return }
        isPreparing = true
        defer { isPreparing = false }
        Log.info(.app, "Сборка архива журнала")
        let info = """
        \(AppContainer.appVersion)
        \(ProcessInfo.processInfo.operatingSystemVersionString)
        Пользователь: \(container.currentUserId.isEmpty ? "не вошёл" : container.currentUserId)
        Выгружено: \(Date().formatted(.iso8601))
        """
        let result = await Task.detached(priority: .userInitiated) { () -> Result<LogArchive, Error> in
            Result {
                let url = try logs.makeArchive(info: info)
                defer { try? FileManager.default.removeItem(at: url) }
                return LogArchive(data: try Data(contentsOf: url), filename: url.deletingPathExtension().lastPathComponent)
            }
        }.value
        switch result {
        case .success(let ready):
            archive = ready
            isExporting = true
        case .failure(let error):
            Log.error(.app, "Архив журнала не собрался: \(error)")
            message = "Не удалось собрать архив журнала"
        }
        size = logs.totalSize()
    }
}

/// Готовый ZIP для системного окна сохранения.
struct LogArchive: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    let data: Data
    let filename: String

    init(data: Data, filename: String) {
        self.data = data
        self.filename = filename
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        filename = "orbitle-logs"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
