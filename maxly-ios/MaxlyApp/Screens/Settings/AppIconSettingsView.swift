import SwiftUI
import UIKit

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

    private func change(to icon: Icon) {
        guard !changing, UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != icon.alternateName else { return }
        changing = true
        Task { @MainActor in
            defer { changing = false }
            do {
                try await UIApplication.shared.setAlternateIconName(icon.alternateName)
            } catch {
                errorMessage = error.localizedDescription
            }
            selectedName = UIApplication.shared.alternateIconName
        }
    }
}
