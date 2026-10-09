import SwiftUI
import UIKit
import MaxlyData
import MaxlyDomain

/// «О приложении»: версия, журнал и отчёты о сбоях.
struct AboutView: View {
    let container: AppContainer

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    MaxlyLogoTile(size: 72)
                    Text(verbatim: "Maxly")
                        .font(.title2.bold())
                    Text("Версия \(AppContainer.versionNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                LabeledContent("Система", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
            }
            LogSettingsSection(container: container)
            CrashDumpsSection(store: container.crashDumps)
        }
        .navigationTitle("О приложении")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Отчёты о сбоях из архива: от свежего к старому, с текстом и удалением.
struct CrashDumpsSection: View {
    let store: CrashDumpStore?

    @State private var dumps: [CrashDump] = []
    @State private var confirmDelete = false

    var body: some View {
        Section {
            if dumps.isEmpty {
                Text("Сбоев не было")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dumps) { dump in
                    NavigationLink {
                        if let store {
                            CrashDumpView(dump: dump, store: store)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(CrashDumpView.title(for: dump))
                            Text(dump.summary)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete { offsets in
                    offsets.map { dumps[$0] }.forEach { store?.remove($0) }
                    reload()
                }
                Button("Удалить отчёты", role: .destructive) { confirmDelete = true }
            }
        } header: {
            Text("Отчёты о сбоях")
        } footer: {
            Text("Отчёт появляется при следующем запуске после сбоя и хранится здесь, пока его не удалят, но не больше 20 последних. Отчёты входят и в архив журнала.")
        }
        .onAppear(perform: reload)
        .confirmationDialog("Удалить отчёты о сбоях?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                store?.removeAll()
                Log.info(.app, "Отчёты о сбоях удалены")
                reload()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func reload() {
        dumps = store?.list() ?? []
    }
}

/// Полный текст отчёта о сбое: выделение и «Поделиться».
struct CrashDumpView: View {
    let dump: CrashDump
    let store: CrashDumpStore

    @State private var text = ""

    var body: some View {
        ScrollView {
            Text(text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(Self.title(for: dump))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: text) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
                .disabled(text.isEmpty)
            }
        }
        .task { text = store.text(of: dump) ?? "Отчёт не найден" }
    }

    /// «29 сент. 2026 г., 23:10» — по-русски при любом языке системы.
    static func title(for dump: CrashDump) -> String {
        dump.date.formatted(
            .dateTime.day().month(.abbreviated).year().hour().minute()
                .locale(Locale(identifier: "ru_RU"))
        )
    }
}
