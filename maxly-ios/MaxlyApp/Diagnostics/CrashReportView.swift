import SwiftUI

/// Прошлый запуск завершился сбоем: отчёт, выгрузка журнала и продолжение.
///
/// Экран показывается до запуска ядра, поэтому журнал можно достать, даже если приложение
/// падает сразу после старта.
struct CrashReportView: View {
    let container: AppContainer
    let report: String

    @State private var isContinuing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        MaxlyMark(size: 44)
                            .foregroundStyle(.secondary)
                        Text("Прошлый запуск завершился сбоем")
                            .font(.title3.bold())
                        Text("Выгрузите журнал и пришлите его разработчику: в нём есть место, где приложение упало. Потом можно попробовать запустить Maxly снова.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                LogSettingsSection(container: container)
                Section("Отчёт") {
                    Text(report)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(40)
                }
                Section {
                    Button {
                        isContinuing = true
                        Task { await container.continueAfterCrash() }
                    } label: {
                        HStack {
                            Text("Продолжить запуск")
                            if isContinuing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isContinuing)
                    ShareLink(item: report) {
                        Label("Поделиться текстом отчёта", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("Сбой")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
