import SwiftUI
import MaxlyDomain
import MaxlyPresentation

/// «Сообщения»: быстрая реакция, которую ставит двойное нажатие в чате.
struct MessagesSettingsView: View {
    @Bindable var model: AccountSettingsModel
    let loadCatalog: () async -> [String]

    @State private var picking = false
    @State private var catalog = ReactionPalette.fallback

    var body: some View {
        List {
            Section {
                Text("Дважды нажмите на сообщение, чтобы поставить выбранную реакцию.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Быстрые реакции")
            }
        }
        .navigationTitle("Сообщения")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                picking = true
            } label: {
                Text(model.settings.quickReaction)
                    .font(.system(size: 40))
                    .frame(width: 76, height: 76)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Выбрать быструю реакцию")
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $picking) {
            NavigationStack {
                ScrollView {
                    let columns = Array(repeating: GridItem(.flexible()), count: 6)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(catalog, id: \.self) { emoji in
                            Button {
                                picking = false
                                Task { await model.setQuickReaction(emoji) }
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 32))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(emoji)
                        }
                    }
                    .padding()
                }
                .navigationTitle("Выберите реакцию")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Закрыть") { picking = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .task {
                let loaded = await loadCatalog()
                var seen = Set<String>()
                let clean = loaded
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && seen.insert($0).inserted }
                if !clean.isEmpty { catalog = clean }
            }
        }
    }
}
