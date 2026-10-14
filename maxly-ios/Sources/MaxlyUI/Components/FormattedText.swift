import SwiftUI
import MaxlyDomain
import MaxlyPresentation

/// `AttributedString` для блока текста пузыря: форматирование сервера и ссылки,
/// найденные в тексте.
enum FormattedText {
    static func attributed(_ block: TextBlock, outgoing: Bool, style: Font.TextStyle = .body) -> AttributedString {
        var result = AttributedString(block.text)
        let linkColor: Color = outgoing ? .maxlyOutgoingAccent : .maxlyAccent
        for span in block.spans {
            guard let range = range(of: span.from, span.length, in: result, text: block.text) else { continue }
            switch span.kind {
            case .strong:
                result[range].inlinePresentationIntent = merged(result[range].inlinePresentationIntent, .stronglyEmphasized)
            case .emphasized:
                result[range].inlinePresentationIntent = merged(result[range].inlinePresentationIntent, .emphasized)
            case .strikethrough:
                result[range].inlinePresentationIntent = merged(result[range].inlinePresentationIntent, .strikethrough)
            case .monospaced:
                result[range].inlinePresentationIntent = merged(result[range].inlinePresentationIntent, .code)
                result[range].backgroundColor = (outgoing ? Color.maxlyOutgoingText : Color.primary).opacity(0.1)
            case .underline:
                result[range].underlineStyle = .single
            case .heading:
                result[range].font = .app(.headline)
            case .link:
                let target = span.url.flatMap(URL.init(string:)) ?? URL(string: substring(block.text, span.from, span.length))
                if let target, target.scheme != nil { result[range].link = target }
                result[range].foregroundColor = linkColor
                // Подчёркивание отличает ссылки от текста независимо от восприятия цвета.
                result[range].underlineStyle = .single
            case .mention:
                result[range].foregroundColor = linkColor
                result[range].inlinePresentationIntent = merged(result[range].inlinePresentationIntent, .stronglyEmphasized)
            case .quote, .animoji, .unknown:
                // Анимодзи играет поверх своего места (`marked`, `AnimojiOverlay`, iOS 18+).
                break
            }
        }
        detectLinks(in: &result, text: block.text, color: linkColor, underline: true)
        applyTypography(&result, style: style)
        return result
    }

    /// Встроенный шрифт («Оформление → Шрифт») не умеет системные `.bold()`, курсив и `.monospaced()`:
    /// жирное, курсив и код получают свой шрифт явно, остальное наследует шрифт текста.
    static func applyTypography(_ result: inout AttributedString, style: Font.TextStyle, typography: Typography = .shared) {
        guard typography.isCustom else { return }
        let styled: InlinePresentationIntent = [.stronglyEmphasized, .emphasized, .code]
        let runs: [(InlinePresentationIntent, Range<AttributedString.Index>)] = result.runs[\.inlinePresentationIntent]
            .compactMap { intent, range in intent.map { ($0, range) } }
        for (intent, range) in runs where !intent.isDisjoint(with: styled) {
            let weight: Font.Weight? = intent.contains(.stronglyEmphasized) ? .bold : nil
            result[range].font = intent.contains(.code)
                ? typography.mono(style, weight: weight)
                : typography.style(style, weight: weight, italic: intent.contains(.emphasized))
            result[range].inlinePresentationIntent = intent.subtracting(styled)
        }
    }

    /// Текст с метками анимодзи (`AnimojiMark`): по ним рендерер оставляет место под Lottie.
    @available(iOS 18.0, macOS 15.0, *)
    static func marked(_ attributed: AttributedString, text: String, placed: [AnimojiText.Placed]) -> Text {
        let total = (text as NSString).length
        var result = Text("")
        var cursor = 0
        func piece(_ from: Int, _ length: Int) -> Text? {
            guard length > 0, let range = Range(NSRange(location: from, length: length), in: attributed) else { return nil }
            return Text(AttributedString(attributed[range]))
        }
        for item in placed where item.from >= cursor && item.from + item.length <= total {
            if let before = piece(cursor, item.from - cursor) { result = result + before }
            if let emoji = piece(item.from, item.length) {
                result = result + emoji.customAttribute(AnimojiMark(url: item.lottieURL, emoji: item.emoji))
            }
            cursor = item.from + item.length
        }
        if let rest = piece(cursor, total - cursor) { result = result + rest }
        return result
    }

    private static func merged(_ current: InlinePresentationIntent?, _ added: InlinePresentationIntent) -> InlinePresentationIntent {
        (current ?? []).union(added)
    }

    private static func range(of from: Int, _ length: Int, in attributed: AttributedString, text: String) -> Range<AttributedString.Index>? {
        let total = text.utf16.count
        let start = min(max(from, 0), total)
        let end = min(max(from + length, start), total)
        guard end > start else { return nil }
        return Range(NSRange(location: start, length: end - start), in: attributed)
    }

    private static func substring(_ text: String, _ from: Int, _ length: Int) -> String {
        let ns = text as NSString
        let start = min(max(from, 0), ns.length)
        let end = min(start + max(length, 0), ns.length)
        return ns.substring(with: NSRange(location: start, length: end - start))
    }

    /// Адреса и почта в обычном тексте становятся ссылками, как в любом мессенджере.
    private static func detectLinks(in result: inout AttributedString, text: String, color: Color, underline: Bool) {
        guard text.contains(".") || text.contains("@"),
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        let whole = NSRange(location: 0, length: (text as NSString).length)
        for match in detector.matches(in: text, options: [], range: whole) {
            guard let url = match.url, let range = Range(match.range, in: result) else { continue }
            if result[range].link != nil { continue }
            result[range].link = url
            result[range].foregroundColor = color
            if underline { result[range].underlineStyle = .single }
        }
    }
}

/// Текст пузыря с форматированием: абзацы и цитаты с полосой слева.
/// `trailingSpace` — невидимое место под время в конце последнего абзаца.
struct MessageTextView: View {
    let text: String
    let spans: [TextSpan]
    let outgoing: Bool
    let trailingSpace: Text?
    @Environment(\.animojiCatalog) private var catalog

    var body: some View {
        let blocks = ChatTextFormat.blocks(text: text, spans: spans)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                let last = index == blocks.count - 1
                if block.isQuote {
                    quote(block, last: last)
                } else {
                    line(block, last: last)
                }
            }
        }
    }

    private func line(_ block: TextBlock, last: Bool) -> some View {
        content(block, last: last, style: .body)
            .font(.app(.body))
            .foregroundStyle(outgoing ? Color.maxlyOutgoingText : Color.primary)
            .modifier(AnimojiOverlay(active: !animoji(block).isEmpty))
    }

    /// Анимодзи блока: играют на своём месте вместе с текстом.
    private func animoji(_ block: TextBlock) -> [AnimojiText.Placed] {
        AnimojiText.inline(text: block.text, spans: block.spans, catalog: catalog)
    }

    private func quote(_ block: TextBlock, last: Bool) -> some View {
        // Полоса — в overlay: её высота равна высоте текста цитаты, а не всей доступной.
        content(block, last: last, style: .callout)
            .modifier(AnimojiOverlay(active: !animoji(block).isEmpty))
            .font(.app(.callout))
            .foregroundStyle(outgoing ? Color.maxlyOutgoingText.opacity(0.92) : Color.primary.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 5)
            .padding(.leading, 13)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(outgoing ? Color.maxlyOutgoingAccent : Color.maxlyAccent)
                    .frame(width: 3)
            }
            .background((outgoing ? Color.maxlyOutgoingAccent : Color.maxlyAccent).opacity(outgoing ? 0.18 : 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func content(_ block: TextBlock, last: Bool, style: Font.TextStyle) -> Text {
        let attributed = FormattedText.attributed(block, outgoing: outgoing, style: style)
        var body = Text(attributed)
        if #available(iOS 18.0, macOS 15.0, *) {
            let placed = animoji(block)
            if !placed.isEmpty { body = FormattedText.marked(attributed, text: block.text, placed: placed) }
        }
        guard last else { return body }
        guard let trailingSpace else { return body }
        return body + trailingSpace.foregroundStyle(.clear)
    }
}
