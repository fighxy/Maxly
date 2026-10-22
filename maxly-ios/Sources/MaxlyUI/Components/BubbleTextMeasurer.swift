import CoreText
import Foundation
import MaxlyDomain
import MaxlyPresentation

#if canImport(UIKit)
import UIKit
#endif

/// Высота текста пузыря через TextKit — вне главного потока раскладки SwiftUI.
///
/// Эвристика `chars / width` в `BubbleHeightCache` ошибается на длинных словах и
/// кастомных шрифтах. Здесь — `NSString.boundingRect` с тем же кеглем, что `.body`.
public enum BubbleTextMeasurer {
    /// Подключить к `BubbleHeightCache.textHeightProvider` при старте приложения.
    public static func installAsHeightProvider() {
        BubbleHeightCache.textHeightProvider = { text, maxWidth in
            Double(height(text: text, maxWidth: CGFloat(maxWidth)))
        }
    }

    public static func height(text: String, maxWidth: CGFloat, textSize: TextSizeStep = Typography.shared.textSize) -> CGFloat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, maxWidth > 1 else { return 0 }
        #if canImport(UIKit)
        let font = bodyFont(textSize: textSize)
        let box = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        let bounds = (trimmed as NSString).boundingRect(
            with: box,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(bounds.height)
        #else
        let lineHeight = Typography.pointSize(.body, textSize) * 1.25
        let charsPerLine = max(12.0, Double(maxWidth) / 8.5)
        return CGFloat(ceil(Double(trimmed.count) / charsPerLine) * lineHeight)
        #endif
    }

    #if canImport(UIKit)
    private static func bodyFont(textSize: TextSizeStep) -> UIFont {
        let size = Typography.pointSize(.body, textSize)
        if let ct = Typography.shared.platformFont(.body) {
            let name = CTFontCopyPostScriptName(ct) as String
            if let font = UIFont(name: name, size: size) { return font }
        }
        return .systemFont(ofSize: size)
    }
    #endif
}
