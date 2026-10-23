import SwiftUI

/// Колонка содержимого пузыря.
///
/// Ширина — по самому широкому содержимому (но не больше предложенной), а не по гибким
/// строкам: ряд реакций с временем справа или подвал комментариев растягиваются ровно до
/// ширины текста и медиа и не раздувают короткий пузырь на всю ленту.
///
/// Время текста (`bubbleCorner()`) не занимает строки и не влияет на ширину: оно стоит в
/// правом нижнем углу предыдущей строки, у края колонки. Текст поэтому меряется по своей
/// ширине при переносе, а время всё равно у правого края, если цитата, медиа или голосовое
/// шире текста.
struct BubbleColumn: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = columnWidth(proposal: proposal, subviews: subviews)
        let height = subviews.reduce(CGFloat(0)) { sum, subview in
            guard !subview[BubbleCornerKey.self] else { return sum }
            return sum + subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if subview[BubbleCornerKey.self] {
                subview.place(at: CGPoint(x: bounds.maxX, y: y), anchor: .bottomTrailing, proposal: ProposedViewSize(size))
                continue
            }
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: size.height))
            y += size.height
        }
    }

    private func columnWidth(proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        let limit = proposal.width ?? .infinity
        let widest = subviews.reduce(CGFloat(0)) { widest, subview in
            guard !subview[BubbleCornerKey.self] else { return widest }
            let ideal = subview.sizeThatFits(.unspecified).width
            let fitted = subview.sizeThatFits(ProposedViewSize(width: limit.isFinite ? limit : nil, height: nil)).width
            // Текст в идеале — одна длинная строка: тогда берётся его ширина при переносе.
            return max(widest, min(ideal, fitted, limit))
        }
        return limit.isFinite ? min(widest, limit) : widest
    }
}

private struct BubbleCornerKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// Строка `BubbleColumn` в правом нижнем углу предыдущей строки: без своей высоты и ширины.
    func bubbleCorner() -> some View {
        layoutValue(key: BubbleCornerKey.self, value: true)
    }
}
