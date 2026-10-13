import SwiftUI
import UIKit
import MaxlyDomain

/// iOS owns the persisted selection. Read it again on foreground entry rather
/// than keeping a second preference that could disagree after a failed change.
struct AppIconSettingsView: View {
    private enum Icon: String, CaseIterable, Identifiable {
        case black, white
        var id: Self { self }
        var title: String { self == .white ? "Белая" : "Чёрная" }
        var alternateName: String? { self == .white ? "AppIconWhite" : nil }
        var preview: String { self == .white ? "IconPreviewWhite" : "IconPreviewBlack" }
    }

    @State private var selectedName = UIApplication.shared.alternateIconName
    @State private var changing = false
    @State private var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                ForEach(Icon.allCases) { icon in
                    Button {
                        change(to: icon)
                    } label: {
                        HStack(spacing: 16) {
                            Image(icon.preview)
                                .resizable()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.gray.opacity(0.25)))
                                .accessibilityHidden(true)
                            Text(icon.title).foregroundStyle(.primary)
                            Spacer()
                            if selectedName == icon.alternateName {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(changing || !UIApplication.shared.supportsAlternateIcons)
                    .accessibilityAddTraits(selectedName == icon.alternateName ? [.isSelected] : [])
                }
                if changing { ProgressView("Меняем иконку…") }
            } footer: {
                Text(UIApplication.shared.supportsAlternateIcons
                     ? "Иконка на домашнем экране. Выбор сохраняется независимо от темы приложения."
                     : "Смена иконки недоступна в этой сборке приложения.")
            }
        }
        .navigationTitle("Иконка приложения")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selectedName = UIApplication.shared.alternateIconName }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { selectedName = UIApplication.shared.alternateIconName }
        }
        .alert("Не удалось сменить иконку", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Хорошо", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Вызов с обработчиком, а не `async`-вариант: тот на iOS 17–18 из `Task` иногда молча не
    /// меняет иконку. Ответ системы ждём через продолжение, состояние экрана — на главном потоке.
    private func change(to icon: Icon) {
        guard !changing, UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != icon.alternateName else { return }
        changing = true
        let name = icon.alternateName
        Task { @MainActor in
            let error: (any Error)? = await withCheckedContinuation { continuation in
                UIApplication.shared.setAlternateIconName(name) { error in
                    continuation.resume(returning: error)
                }
            }
            changing = false
            selectedName = UIApplication.shared.alternateIconName
            if let error {
                Log.warning(.app, "Иконка не сменилась (\(name ?? "основная")): \(error)")
                errorMessage = error.localizedDescription
            } else if selectedName != name {
                Log.warning(.app, "Иконка не сменилась (\(name ?? "основная")): система ответила без ошибки")
                errorMessage = "Система не применила иконку. Если приложение переподписано, проверьте, что при подписи сохранился набор иконок."
            } else {
                Log.info(.app, "Иконка сменилась: \(name ?? "основная")")
            }
        }
    }
}
