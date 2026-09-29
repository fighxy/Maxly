import SwiftUI

/// Алфавитный указатель справа от списка.
///
/// На iOS 26 это системный указатель `List` (`sectionIndexLabel`), на прежних
/// версиях SwiftUI его нет, и вместо него рисуется `SectionIndexStrip`.
public enum SectionIndexSupport {
    public static var isNative: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) { return true }
        #endif
        return false
    }
}

public extension View {
    /// Буква раздела в системном указателе (iOS 26). На прежних версиях ничего не делает.
    @ViewBuilder
    func orbitlSectionIndexLabel(_ label: String) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            sectionIndexLabel(label)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Показывает системный указатель списка (iOS 26).
    @ViewBuilder
    func orbitlSectionIndexVisible(_ visible: Bool) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            listSectionIndexVisibility(visible ? .visible : .hidden)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// Указатель для iOS 17–18: столбик букв, нажатие и протягивание пальцем
/// прокручивают список. Если буквы не помещаются, часть заменяется точками.
public struct SectionIndexStrip: View {
    private let titles: [String]
    private let onSelect: (String) -> Void
    @State private var current: String?

    public init(titles: [String], onSelect: @escaping (String) -> Void) {
        self.titles = titles
        self.onSelect = onSelect
    }

    private static let rowHeight: CGFloat = 15

    public var body: some View {
        GeometryReader { proxy in
            let entries = Self.entries(titles, fitting: proxy.size.height)
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    Text(entry.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 20, height: Self.rowHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        select(at: value.location.y, height: proxy.size.height, entries: entries)
                    }
                    .onEnded { _ in current = nil }
            )
        }
        .frame(width: 22)
        .sensoryFeedback(.selection, trigger: current)
        .accessibilityElement()
        .accessibilityLabel("Алфавитный указатель")
        .accessibilityAdjustableAction { direction in
            let index = current.flatMap { titles.firstIndex(of: $0) } ?? -1
            let next: Int
            switch direction {
            case .increment: next = min(index + 1, titles.count - 1)
            case .decrement: next = max(index - 1, 0)
            @unknown default: return
            }
            guard titles.indices.contains(next) else { return }
            current = titles[next]
            onSelect(titles[next])
        }
    }

    private func select(at y: CGFloat, height: CGFloat, entries: [Entry]) {
        let contentHeight = CGFloat(entries.count) * Self.rowHeight
        let top = (height - contentHeight) / 2
        let position = Int(((y - top) / Self.rowHeight).rounded(.down))
        guard let entry = entries[safe: min(max(position, 0), entries.count - 1)] else { return }
        // Точка ведёт к букве, которую она заменила.
        guard entry.target != current else { return }
        current = entry.target
        onSelect(entry.target)
    }

    struct Entry {
        let label: String
        let target: String
    }

    /// Буквы, которые помещаются по высоте. Лишние заменяются точкой через одну.
    static func entries(_ titles: [String], fitting height: CGFloat) -> [Entry] {
        let capacity = max(Int(height / rowHeight), 3)
        guard titles.count > capacity, titles.count > 2 else {
            return titles.map { Entry(label: $0, target: $0) }
        }
        // Первая и последняя буквы всегда видны, между видимыми — точки.
        let slots = capacity % 2 == 0 ? capacity - 1 : capacity
        let visible = (slots + 1) / 2
        let step = Double(titles.count - 1) / Double(max(visible - 1, 1))
        var result: [Entry] = []
        for index in 0..<visible {
            let position = Int((Double(index) * step).rounded())
            if index > 0 {
                let previous = Int((Double(index - 1) * step).rounded())
                let skipped = (previous + position) / 2
                result.append(Entry(label: "•", target: titles[skipped]))
            }
            result.append(Entry(label: titles[position], target: titles[position]))
        }
        return result
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
