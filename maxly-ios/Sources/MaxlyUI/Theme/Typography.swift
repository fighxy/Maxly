import CoreText
import Foundation
import Observation
import SwiftUI
import MaxlyDomain

/// Шрифт и толщина всего интерфейса из «Оформления → Шрифт».
///
/// Экраны берут шрифты через `Font.app(…)`: тело экрана читает `shared` и SwiftUI перерисовывает его,
/// когда шрифт, толщина или размер текста меняются. Системный шрифт остаётся шрифтом Dynamic Type
/// (толщина ступенями), встроенные — переменные: толщина любая в пределах оси `wght` файла, размер
/// стиля — по таблице Dynamic Type для шага размера текста из «Оформления».
@Observable
public final class Typography: @unchecked Sendable {
    public static let shared = Typography()

    public private(set) var font: AppFont = .system
    public private(set) var weight: Int = FontWeightScale.standard
    public private(set) var textSize: TextSizeStep = .standard

    public init() {}

    /// Корень приложения передаёт сюда настройки «Оформления». Те же значения ничего не меняют.
    public func apply(font: AppFont, weight: Int, textSize: TextSizeStep) {
        let weight = FontWeightScale.clamp(weight)
        if font != self.font { self.font = font }
        if weight != self.weight { self.weight = weight }
        if textSize != self.textSize { self.textSize = textSize }
    }

    /// Выбран встроенный шрифт: жирное и курсив в тексте сообщений задаются шрифтом явно.
    public var isCustom: Bool { font.file != nil }

    /// Шрифт стиля `style` толщины `weight` (`nil` — обычная для стиля: у `.headline` полужирная).
    /// `font` и `textSize` — для образцов на экране «Шрифт», по умолчанию выбранные.
    public func style(
        _ style: Font.TextStyle,
        weight: Font.Weight? = nil,
        italic: Bool = false,
        font choice: AppFont? = nil,
        textSize step: TextSizeStep? = nil
    ) -> Font {
        let choice = choice ?? self.font
        let requested = weight.map(Self.numeric) ?? Self.standardWeight(style)
        let axis = FontWeightScale.axis(choice, requested: requested, base: self.weight)
        guard let file = choice.file else {
            let system = Font.system(style).weight(Self.weight(axis))
            return italic ? system.italic() : system
        }
        let size = Self.pointSize(style, step ?? textSize)
        return Font(FontFiles.font(file: file, size: size, axis: axis, italic: italic))
    }

    /// Шрифт фиксированного размера (как `.system(size:)`, без Dynamic Type).
    public func fixed(size: CGFloat, weight: Font.Weight = .regular, font choice: AppFont? = nil) -> Font {
        let choice = choice ?? self.font
        let axis = FontWeightScale.axis(choice, requested: Self.numeric(weight), base: self.weight)
        guard let file = choice.file else { return .system(size: size, weight: Self.weight(axis)) }
        return Font(FontFiles.font(file: file, size: size, axis: axis, italic: false))
    }

    /// Код: JetBrains Mono, толщина сдвигается ползунком так же, как у основного шрифта.
    public func mono(_ style: Font.TextStyle, weight: Font.Weight? = nil, textSize step: TextSizeStep? = nil) -> Font {
        let requested = (weight.map(Self.numeric) ?? Self.standardWeight(style)) + self.weight - FontWeightScale.standard
        let axis = min(max(requested, FontWeightScale.monoRange.lowerBound), FontWeightScale.monoRange.upperBound)
        let size = Self.pointSize(style, step ?? textSize)
        return Font(FontFiles.font(file: FontWeightScale.monoFile, size: size, axis: axis, italic: false))
    }

    /// Шрифт для UIKit (заголовки навигации): `nil` у системного — UIKit берёт свой.
    public func platformFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> CTFont? {
        guard let file = font.file else { return nil }
        let requested = weight.map(Self.numeric) ?? Self.standardWeight(style)
        let axis = FontWeightScale.axis(font, requested: requested, base: self.weight)
        return FontFiles.font(file: file, size: Self.pointSize(style, textSize), axis: axis, italic: false)
    }

    // MARK: - Таблицы

    /// Размер стиля в пунктах на шаге размера текста — таблица Dynamic Type iOS (xSmall…xxxLarge).
    public static func pointSize(_ style: Font.TextStyle, _ step: TextSizeStep) -> CGFloat {
        let sizes: [CGFloat] = switch style {
        case .largeTitle: [31, 32, 33, 34, 36, 38, 40]
        case .title: [25, 26, 27, 28, 30, 32, 34]
        case .title2: [19, 20, 21, 22, 24, 26, 28]
        case .title3: [17, 18, 19, 20, 22, 24, 26]
        case .headline, .body: [14, 15, 16, 17, 19, 21, 23]
        case .callout: [13, 14, 15, 16, 18, 20, 22]
        case .subheadline: [12, 13, 14, 15, 17, 19, 21]
        case .footnote: [12, 12, 12, 13, 15, 17, 19]
        case .caption: [11, 11, 11, 12, 14, 16, 18]
        case .caption2: [11, 11, 11, 11, 13, 15, 17]
        default: [14, 15, 16, 17, 19, 21, 23]
        }
        return sizes[min(max(step.index, 0), sizes.count - 1)]
    }

    /// Обычная толщина стиля: `.headline` полужирный, остальные — 400.
    public static func standardWeight(_ style: Font.TextStyle) -> Int {
        style == .headline ? 600 : 400
    }

    public static func numeric(_ weight: Font.Weight) -> Int {
        switch weight {
        case .ultraLight: 100
        case .thin: 200
        case .light: 300
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy: 800
        case .black: 900
        default: 400
        }
    }

    /// Ближайшая системная толщина для оси (сотни).
    public static func weight(_ axis: Int) -> Font.Weight {
        switch Int((Double(axis) / 100).rounded()) {
        case ...1: .ultraLight
        case 2: .thin
        case 3: .light
        case 4: .regular
        case 5: .medium
        case 6: .semibold
        case 7: .bold
        case 8: .heavy
        default: .black
        }
    }
}

public extension Font {
    /// Стиль текста выбранным шрифтом (`.app(.body)`, `.app(.subheadline, .semibold)`).
    static func app(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        Typography.shared.style(style, weight: weight)
    }

    /// Фиксированный размер выбранным шрифтом, как `.system(size:weight:)`.
    static func app(size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Typography.shared.fixed(size: size, weight: weight)
    }

    /// Моноширинный шрифт кода (JetBrains Mono).
    static func appMono(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        Typography.shared.mono(style, weight: weight)
    }
}

/// Файлы встроенных шрифтов: регистрируются один раз, начертание с нужной толщиной кешируется.
enum FontFiles {
    private static let cache = Cache()

    static func font(file: String, size: CGFloat, axis: Int, italic: Bool) -> CTFont {
        let key = "\(file)@\(axis)@\(size)\(italic ? "i" : "")"
        if let font = cache.get(key) { return font }
        let font = make(file: file, size: size, axis: axis, italic: italic)
        cache.set(key, font)
        return font
    }

    /// Ось `wght` (`'w' 'g' 'h' 't'`).
    static let weightAxis = 0x7767_6874

    private static func make(file: String, size: CGFloat, axis: Int, italic: Bool) -> CTFont {
        // Встроенные шрифты без курсива: наклон — матрицей, как у синтетического курсива.
        var slant = CGAffineTransform(a: 1, b: 0, c: italic ? 0.2 : 0, d: 1, tx: 0, ty: 0)
        guard let base = descriptor(file) else {
            return CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }
        let variation = [kCTFontVariationAttribute: [NSNumber(value: weightAxis): NSNumber(value: axis)]] as CFDictionary
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(base, variation)
        return CTFontCreateWithFontDescriptor(descriptor, size, &slant)
    }

    private static func descriptor(_ file: String) -> CTFontDescriptor? {
        if let known = cache.descriptor(file) { return known }
        guard let url = Bundle.module.url(forResource: file, withExtension: "ttf"),
              let data = try? Data(contentsOf: url),
              let descriptor = CTFontManagerCreateFontDescriptorFromData(data as CFData)
        else {
            Log.warning(.ui, "Шрифт \(file) не найден в ресурсах")
            return nil
        }
        // Зарегистрированный шрифт SwiftUI находит и по имени, если пересоздаёт его из описания.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        cache.setDescriptor(file, descriptor)
        return descriptor
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var fonts: [String: CTFont] = [:]
        private var descriptors: [String: CTFontDescriptor] = [:]

        func get(_ key: String) -> CTFont? { lock.withLock { fonts[key] } }
        func set(_ key: String, _ font: CTFont) { lock.withLock { fonts[key] = font } }
        func descriptor(_ file: String) -> CTFontDescriptor? { lock.withLock { descriptors[file] } }
        func setDescriptor(_ file: String, _ descriptor: CTFontDescriptor) { lock.withLock { descriptors[file] = descriptor } }
    }
}
