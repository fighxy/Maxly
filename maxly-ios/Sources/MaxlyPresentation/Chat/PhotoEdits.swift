import Foundation

public struct PhotoPoint: Hashable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) {
        self.x = x.isFinite ? min(1, max(0, x)) : 0
        self.y = y.isFinite ? min(1, max(0, y)) : 0
    }
}

public struct PhotoSize: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) { self.width = max(1, width); self.height = max(1, height) }
}

public struct PhotoCrop: Hashable, Sendable {
    public let left: Double
    public let top: Double
    public let right: Double
    public let bottom: Double
    public init(left: Double, top: Double, right: Double, bottom: Double) {
        precondition([left, top, right, bottom].allSatisfy { $0.isFinite && (0...1).contains($0) } && right > left && bottom > top)
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
    public static let full = PhotoCrop(left: 0, top: 0, right: 1, bottom: 1)

    public static func between(_ a: PhotoPoint, _ b: PhotoPoint) -> PhotoCrop? {
        guard abs(a.x - b.x) >= 0.01 && abs(a.y - b.y) >= 0.01 else { return nil }
        return PhotoCrop(left: min(a.x, b.x), top: min(a.y, b.y), right: max(a.x, b.x), bottom: max(a.y, b.y))
    }
    public static func centered(_ size: PhotoSize, ratio: Double) -> PhotoCrop {
        precondition(ratio.isFinite && ratio > 0)
        let actual = Double(size.width) / Double(size.height)
        let width = min(1, ratio / actual), height = min(1, actual / ratio)
        return PhotoCrop(left: (1 - width) / 2, top: (1 - height) / 2, right: (1 + width) / 2, bottom: (1 + height) / 2)
    }
    public func pixels(_ size: PhotoSize) -> (x: Int, y: Int, width: Int, height: Int) {
        let x = min(size.width - 1, max(0, Int((left * Double(size.width)).rounded())))
        let y = min(size.height - 1, max(0, Int((top * Double(size.height)).rounded())))
        let endX = min(size.width, max(x + 1, Int((right * Double(size.width)).rounded())))
        let endY = min(size.height, max(y + 1, Int((bottom * Double(size.height)).rounded())))
        return (x, y, endX - x, endY - y)
    }
}

public enum PhotoFilter: String, CaseIterable, Sendable {
    case mono, sepia, warm, cool, contrast
    public var title: String {
        switch self { case .mono: "Ч/б"; case .sepia: "Сепия"; case .warm: "Тёплый"; case .cool: "Холодный"; case .contrast: "Контраст" }
    }
}

/// Правки по порядку; кадрирование/поворот затрагивают и ранее нанесённый рисунок.
public enum PhotoEdit: Hashable, Sendable {
    case crop(PhotoCrop)
    case rotate(clockwise: Bool)
    case flip
    case straighten(Double)
    case stroke(points: [PhotoPoint], color: UInt32, width: Double, brush: PhotoBrush = .pen)
    case text(PhotoText)
    case replaceText(PhotoText)
    case removeText(UUID)
    case shape(PhotoCrop, shape: PhotoShape, color: UInt32, width: Double, filled: Bool)
    case adjust(PhotoAdjustments)
    case filter(PhotoFilter, amount: Double)
}

public enum PhotoBrush: String, CaseIterable, Sendable { case pen = "Кисть", arrow = "Стрелка", marker = "Маркер", blur = "Размытие", eraser = "Ластик" }
public enum PhotoShape: String, CaseIterable, Sendable { case rectangle = "Прямоугольник", ellipse = "Эллипс" }
public enum PhotoTextStyle: String, CaseIterable, Sendable { case outline = "Контур", plain = "Обычный", solid = "Подложка", translucent = "Полупрозрачный" }
public enum PhotoFont: String, CaseIterable, Sendable { case sans = "Обычный", serif = "С засечками", mono = "Моно", italic = "Курсив" }
public enum PhotoAlignment: String, CaseIterable, Sendable { case left = "Слева", center = "По центру", right = "Справа" }
public struct PhotoText: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var point: PhotoPoint
    public var color: UInt32
    public var size: Double
    public var style: PhotoTextStyle = .outline
    public var font: PhotoFont = .sans
    public var alignment: PhotoAlignment = .left
    public init(id: UUID = UUID(), text: String, point: PhotoPoint, color: UInt32, size: Double, style: PhotoTextStyle = .outline, font: PhotoFont = .sans, alignment: PhotoAlignment = .left) {
        self.id = id; self.text = text; self.point = point; self.color = color; self.size = size; self.style = style; self.font = font; self.alignment = alignment
    }
}

public struct PhotoEditHistory: Equatable, Sendable {
    public private(set) var edits: [PhotoEdit] = []
    public private(set) var undone: [PhotoEdit] = []
    public init(edits: [PhotoEdit] = []) { self.edits = edits }
    public mutating func add(_ edit: PhotoEdit) { edits.append(edit); undone = [] }
    public mutating func undo() { if let last = edits.popLast() { undone.append(last) } }
    public mutating func redo() { if let last = undone.popLast() { edits.append(last) } }
    public var resolved: [PhotoEdit] {
        var replacements: [UUID: PhotoText] = [:]
        var removed = Set<UUID>()
        for edit in edits {
            if case .replaceText(let text) = edit { replacements[text.id] = text }
            if case .removeText(let id) = edit { removed.insert(id) }
        }
        return edits.compactMap { edit in
            switch edit {
            case .replaceText, .removeText: return nil
            case .text(let text): return removed.contains(text.id) ? nil : .text(replacements[text.id] ?? text)
            default: return edit
            }
        }
    }
    public var texts: [PhotoText] { resolved.compactMap { if case .text(let text) = $0 { return text }; return nil } }
    public func textPoint(_ id: UUID, displayed: PhotoPoint, original: PhotoSize) -> PhotoPoint {
        let commands = resolved
        guard let index = commands.firstIndex(where: { if case .text(let t) = $0 { return t.id == id }; return false }) else { return displayed }
        var current = original
        let sizes = commands.map { edit in
            let before = current
            switch edit {
            case .crop(let rect): let p = rect.pixels(current); current = PhotoSize(width: p.width, height: p.height)
            case .rotate: current = PhotoSize(width: current.height, height: current.width)
            default: break
            }
            return before
        }
        var x = displayed.x, y = displayed.y
        for i in commands.indices.reversed() where i > index {
            switch commands[i] {
            case .crop(let r): x = r.left + x * (r.right - r.left); y = r.top + y * (r.bottom - r.top)
            case .rotate(let clockwise): let oldX = x; x = clockwise ? y : 1-y; y = clockwise ? 1-oldX : oldX
            case .flip: x = 1-x
            case .straighten(let degrees):
                let w = Double(sizes[i].width), h = Double(sizes[i].height), a = degrees * .pi / 180
                let c = cos(a), s = sin(a), scale = max(abs(c)+h/w*abs(s),abs(c)+w/h*abs(s))
                let px = (x-0.5)*w/scale, py = (y-0.5)*h/scale
                x = (px*c+py*s)/w+0.5; y = (-px*s+py*c)/h+0.5
            default: break
            }
        }
        return PhotoPoint(x: x, y: y)
    }
    public func size(_ original: PhotoSize) -> PhotoSize {
        edits.reduce(original) { size, edit in
            switch edit {
            case .rotate: return PhotoSize(width: size.height, height: size.width)
            case .crop(let crop): let p = crop.pixels(size); return PhotoSize(width: p.width, height: p.height)
            default: return size
            }
        }
    }
}

public struct PhotoCropDrag: Sendable {
    let rect: PhotoCrop
    let start: PhotoPoint
    let left: Bool, right: Bool, top: Bool, bottom: Bool, move: Bool
    public init(rect: PhotoCrop, start: PhotoPoint, thresholdX: Double, thresholdY: Double) {
        self.rect = rect; self.start = start
        left = abs(start.x-rect.left) < thresholdX
        right = !left && abs(start.x-rect.right) < thresholdX
        top = abs(start.y-rect.top) < thresholdY
        bottom = !top && abs(start.y-rect.bottom) < thresholdY
        move = !left && !right && !top && !bottom && (rect.left...rect.right).contains(start.x) && (rect.top...rect.bottom).contains(start.y)
    }
    public func update(_ point: PhotoPoint) -> PhotoCrop {
        if move {
            let dx = min(1-rect.right,max(-rect.left,point.x-start.x)), dy = min(1-rect.bottom,max(-rect.top,point.y-start.y))
            return PhotoCrop(left: rect.left+dx, top: rect.top+dy, right: rect.right+dx, bottom: rect.bottom+dy)
        }
        if !left && !right && !top && !bottom { return PhotoCrop.between(start,point) ?? rect }
        return PhotoCrop(left: left ? min(point.x,rect.right-0.01) : rect.left, top: top ? min(point.y,rect.bottom-0.01) : rect.top,
                         right: right ? max(point.x,rect.left+0.01) : rect.right, bottom: bottom ? max(point.y,rect.top+0.01) : rect.bottom)
    }
}
