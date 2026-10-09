import Foundation
import OrbitleDomain

/// Разметка поля ввода: жирный, курсив, подчёркнутый, зачёркнутый, моноширинный и ссылки.
/// Смещения UTF-16 по тексту поля; при наборе отрезки сдвигаются вместе с текстом
/// (правила — `MessageMarkup`, общие сценарии test-fixtures/formatting).
public struct ComposerFormat: Equatable, Sendable {
    public private(set) var spans: [TextSpan]

    public init(spans: [TextSpan] = []) {
        self.spans = MessageMarkup.normalize(spans)
    }

    /// Текст поля изменился: отрезки сдвигаются, стёртое выпадает. Набранное на краю отрезка
    /// в него не входит.
    public mutating func textChanged(from old: String, to new: String) {
        guard old != new, !spans.isEmpty else { return }
        guard !new.isEmpty else { return spans = [] }
        let edit = MessageMarkup.diff(old: old, new: new)
        spans = MessageMarkup.replace(spans, at: edit.at, removed: edit.removed, inserted: edit.inserted)
    }

    /// Весь `range` накрыт видом `kind`: кнопка панели подсвечена.
    public func isActive(_ kind: TextSpan.Kind, in range: Range<Int>) -> Bool {
        MessageMarkup.covers(spans, kind: kind, start: range.lowerBound, end: range.upperBound)
    }

    /// Накрыт целиком — снять, иначе поставить на весь `range`.
    public mutating func toggle(_ kind: TextSpan.Kind, in range: Range<Int>) {
        guard !range.isEmpty, kind != .link else { return }
        spans = MessageMarkup.toggle(spans, kind: kind, start: range.lowerBound, end: range.upperBound)
    }

    /// Ссылка на `range`. Пустой адрес снимает ссылку; адрес без схемы получает `https://`.
    /// `false` — адрес не похож на ссылку, ничего не изменилось.
    @discardableResult
    public mutating func setLink(_ raw: String, in range: Range<Int>) -> Bool {
        guard !range.isEmpty else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            spans = MessageMarkup.setLink(spans, start: range.lowerBound, end: range.upperBound, url: nil)
            return true
        }
        guard let url = MessageMarkup.normalizeURL(trimmed) else { return false }
        spans = MessageMarkup.setLink(spans, start: range.lowerBound, end: range.upperBound, url: url)
        return true
    }

    /// Адрес ссылки, которая накрывает `range` целиком.
    public func link(in range: Range<Int>) -> String? {
        MessageMarkup.link(in: spans, start: range.lowerBound, end: range.upperBound)
    }

    /// Снять всю разметку панели с `range` (упоминания и анимодзи остаются).
    public mutating func clear(in range: Range<Int>) {
        for kind in MessageMarkup.toolbar {
            spans = MessageMarkup.clear(spans, kind: kind, start: range.lowerBound, end: range.upperBound)
        }
    }

    /// Есть ли на `range` что снимать.
    public func hasFormatting(in range: Range<Int>) -> Bool {
        spans.contains { span in
            MessageMarkup.toolbar.contains(span.kind)
                && span.from < range.upperBound && span.from + span.length > range.lowerBound
        }
    }
}
