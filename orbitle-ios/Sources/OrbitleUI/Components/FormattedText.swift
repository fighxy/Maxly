import SwiftUI
import OrbitleDomain
import OrbitlePresentation

/// `AttributedString` для блока текста пузыря: форматирование сервера и ссылки,
/// найденные в тексте.
enum FormattedText {
    static func attributed(_ block: TextBlock, outgoing: Bool) -> AttributedString {
        var result = AttributedString(block.text)
        let linkColor: Color = outgoing ? .white : .orbitleAccent
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
                result[range].backgroundColor = (outgoing ? Color.white : Color.primary).opacity(0.1)
            case .underline:
                result[range].underlineStyle = .single
            case .heading:
                result[range].font = .headline
            case .link:
                let target = span.url.flatMap(URL.init(string:)) ?? URL(string: substring(block.text, span.from, span.length))
                if let target, target.scheme != nil { result[range].link = target }
                result[range].foregroundColor = linkColor
                result[range].underlineStyle = outgoing ? .single : nil
            case .mention:
                result[range].foregroundColor = linkColor
                result[range].inlinePresentationIntent = merged(result[range].inlinePresentationIntent, .stronglyEmphasized)
            case .quote, .animoji:
                // Анимодзи внутри строки рисуется обычным эмодзи; крупно и с анимацией —
                // в сообщении из одних эмодзи (`BigEmojiMessage`).
                break
            }
        }
        detectLinks(in: &result, text: block.text, color: linkColor, underline: outgoing)
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
        content(block, last: last)
            .foregroundStyle(outgoing ? Color.white : Color.primary)
    }

    private func quote(_ block: TextBlock, last: Bool) -> some View {
        // Полоса — в overlay: её высота равна высоте текста цитаты, а не всей доступной.
        content(block, last: last)
            .font(.callout)
            .foregroundStyle(outgoing ? Color.white.opacity(0.92) : Color.primary.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 5)
            .padding(.leading, 13)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(outgoing ? Color.white : Color.orbitleAccent)
                    .frame(width: 3)
            }
            .background((outgoing ? Color.white : Color.orbitleAccent).opacity(outgoing ? 0.18 : 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func content(_ block: TextBlock, last: Bool) -> Text {
        let body = Text(FormattedText.attributed(block, outgoing: outgoing))
        guard last else { return body }
        guard let trailingSpace else { return body }
        return body + trailingSpace.foregroundStyle(.clear)
    }
}
