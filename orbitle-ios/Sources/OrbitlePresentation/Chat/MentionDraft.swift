import Foundation
import OrbitleDomain

/// Упоминания, вставленные в поле. При отправке каждое вхождение `@имя` уходит отметкой
/// `USER_MENTION` со смещением UTF-16 уже по обрезанному тексту.
public struct MentionDraft: Equatable, Sendable {
    public struct Token: Equatable, Sendable {
        public var text: String
        public var userId: String
    }

    public private(set) var tokens: [Token] = []

    public init() {}

    public mutating func insert(text: String, userId: String) {
        guard !text.isEmpty, !userId.isEmpty else { return }
        tokens.append(Token(text: text, userId: userId))
    }

    public mutating func clear() {
        tokens = []
    }

    public mutating func retainPresent(_ text: String) {
        tokens.removeAll { !text.contains($0.text) }
    }

    public func spans(in text: String) -> [TextSpan] {
        guard !tokens.isEmpty, !text.isEmpty else { return [] }
        var userOf: [String: String] = [:]
        for token in tokens where userOf[token.text] == nil {
            userOf[token.text] = token.userId
        }
        let keys = userOf.keys.sorted { $0.utf16.count > $1.utf16.count }
        var spans: [TextSpan] = []
        var index = text.utf16.startIndex
        var offset = 0
        while index < text.utf16.endIndex {
            if let key = keys.first(where: { text.utf16[index...].starts(with: $0.utf16) }) {
                let length = key.utf16.count
                spans.append(TextSpan(kind: .mention, from: offset, length: length, userId: userOf[key]))
                text.utf16.formIndex(&index, offsetBy: length)
                offset += length
            } else {
                text.utf16.formIndex(&index, offsetBy: 1)
                offset += 1
            }
        }
        return spans
    }
}
