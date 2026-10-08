import Foundation

/// Разметка текста сообщения (`elements` сервера) и поля ввода. Смещения — в единицах UTF-16,
/// как у сервера. Общие с Kotlin правила и сценарии — `test-fixtures/formatting`.
///
/// - Чтение: `from` нет — 0, `length` нет — до конца текста, пустые и вышедшие за текст
///   отрезки выпадают, хвост за концом обрезается. `CODE` читается как моноширинный.
///   Незнакомые типы сохраняются как есть (`unknown`: тип и остальные ключи) и при правке
///   уходят обратно; показ их не рисует. `LINK` без адреса и элемент без типа пропускаются.
/// - Запись: отрезки одного вида, которые пересекаются или стоят вплотную, сливаются
///   (ссылки — только с одинаковым адресом); порядок — по началу, затем по виду ([order]),
///   затем по длине. Правка всегда шлёт весь список, пустой `[]` снимает разметку.
public enum MessageMarkup {
    /// «До конца текста», когда длина текста неизвестна. Не `Int.max`: сумма с `from` не переполнится.
    public static let toEnd = Int(Int32.max)

    /// Порядок видов в списке.
    public static let order: [TextSpan.Kind] = [
        .strong, .emphasized, .underline, .strikethrough, .monospaced, .heading, .quote, .link, .mention, .animoji,
    ]

    /// Кнопки панели форматирования, по порядку.
    public static let toolbar: [TextSpan.Kind] = [.strong, .emphasized, .underline, .strikethrough, .monospaced, .link]

    /// Тип сервера → вид. `CODE` — моноширинный.
    public static func kind(type: String) -> TextSpan.Kind? {
        switch type.uppercased() {
        case "STRONG": .strong
        case "EMPHASIZED": .emphasized
        case "UNDERLINE": .underline
        case "STRIKETHROUGH": .strikethrough
        case "MONOSPACED", "CODE": .monospaced
        case "HEADING": .heading
        case "QUOTE": .quote
        case "LINK": .link
        case "USER_MENTION": .mention
        case "ANIMOJI": .animoji
        default: nil
        }
    }

    /// Вид → тип сервера.
    public static func type(of kind: TextSpan.Kind) -> String {
        switch kind {
        case .strong: "STRONG"
        case .emphasized: "EMPHASIZED"
        case .underline: "UNDERLINE"
        case .strikethrough: "STRIKETHROUGH"
        case .monospaced: "MONOSPACED"
        case .heading: "HEADING"
        case .quote: "QUOTE"
        case .link: "LINK"
        case .mention: "USER_MENTION"
        case .animoji: "ANIMOJI"
        case .unknown: "UNKNOWN"
        }
    }

    // MARK: Чтение

    /// `elements` сервера в отрезки. [text] — текст сообщения: по нему `length` без значения
    /// становится «до конца», а отрезки обрезаются. Без текста (`nil`) — [toEnd] и без обрезки.
    public static func parse(_ value: Any?, text: String?) -> [TextSpan] {
        guard let list = value as? [Any] else { return [] }
        let total = text.map { $0.utf16.count }
        return list.compactMap { item -> TextSpan? in
            guard let map = item as? [String: Any], let type = map["type"] as? String,
                  !type.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let kind = kind(type: type) ?? .unknown
            let from = number(map["from"]) ?? 0
            guard from >= 0 else { return nil }
            let rawLength: Int
            if let given = number(map["length"]) {
                rawLength = given
            } else if let total {
                rawLength = total - from
            } else {
                rawLength = toEnd
            }
            guard rawLength > 0 else { return nil }
            var length = rawLength
            if let total {
                guard from < total else { return nil }
                length = min(length, total - from)
            }
            let attributes = map["attributes"] as? [String: Any]
            switch kind {
            case .link:
                guard let url = attributes?["url"] as? String, !url.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                return TextSpan(kind: .link, from: from, length: length, url: url)
            case .animoji:
                guard let id = identifier(map["entityId"]) else { return nil }
                let lottie = (attributes?["animojiLottieUrl"] as? String) ?? (attributes?["lottieUrl"] as? String)
                return TextSpan(kind: .animoji, from: from, length: length, url: lottie, entityId: id)
            case .mention:
                return TextSpan(kind: .mention, from: from, length: length,
                                userId: identifier(map["entityId"]) ?? identifier(attributes?["userId"]))
            case .unknown:
                return TextSpan(kind: .unknown, from: from, length: length, type: type, extra: extraJSON(map))
            default:
                return TextSpan(kind: kind, from: from, length: length)
            }
        }
    }

    // MARK: Запись

    /// Отрезки по тексту длиной [length] (UTF-16): вышедшее за конец обрезано, пустые выпадают.
    public static func clip(_ span: TextSpan, length: Int) -> TextSpan? {
        let from = min(max(span.from, 0), length)
        let to = min(max(span.from + span.length, from), length)
        guard to > from else { return nil }
        var copy = span
        copy.from = from
        copy.length = to - from
        return copy
    }

    /// Слить пересекающиеся и смежные отрезки одного вида (ссылки — с одним адресом) и
    /// упорядочить. Упоминания и анимодзи не сливаются: у каждого свои данные.
    public static func normalize(_ spans: [TextSpan]) -> [TextSpan] {
        let valid = spans.filter { $0.length > 0 && $0.from >= 0 }
        let separate: Set<TextSpan.Kind> = [.animoji, .mention, .unknown]
        var result = valid.filter { separate.contains($0.kind) }
        let mergeable = valid.filter { !separate.contains($0.kind) }
        var groups: [String: [TextSpan]] = [:]
        var keys: [String] = []
        for span in mergeable {
            let key = "\(span.kind.rawValue)|\(span.url ?? "")"
            if groups[key] == nil { keys.append(key) }
            groups[key, default: []].append(span)
        }
        for key in keys {
            var current: TextSpan?
            for span in groups[key, default: []].sorted(by: { $0.from < $1.from }) {
                if var open = current, span.from <= open.from + open.length {
                    open.length = max(open.from + open.length, span.from + span.length) - open.from
                    current = open
                } else {
                    if let open = current { result.append(open) }
                    current = span
                }
            }
            if let open = current { result.append(open) }
        }
        return sorted(result)
    }

    /// Порядок списка: по началу, по виду ([order]), по длине.
    public static func sorted(_ spans: [TextSpan]) -> [TextSpan] {
        spans.sorted { lhs, rhs in
            if lhs.from != rhs.from { return lhs.from < rhs.from }
            let l = order.firstIndex(of: lhs.kind) ?? order.count
            let r = order.firstIndex(of: rhs.kind) ?? order.count
            if l != r { return l < r }
            return lhs.length < rhs.length
        }
    }

    /// Элемент для сервера.
    public struct Element: Hashable, Sendable {
        public var type: String
        public var from: Int
        public var length: Int
        public var url: String?
        public var entityId: String?
        /// Остальные ключи незнакомого типа объектом JSON — уходят как пришли.
        public var extra: String?

        public init(type: String, from: Int, length: Int, url: String? = nil, entityId: String? = nil, extra: String? = nil) {
            self.type = type
            self.from = from
            self.length = length
            self.url = url
            self.entityId = entityId
            self.extra = extra
        }

        /// JSON-объект в форме сервера: `{type, from, length}` и `attributes.url` у ссылки,
        /// `entityId` у упоминания и анимодзи.
        public var json: [String: Any] {
            var map: [String: Any] = ["type": type, "from": from, "length": length]
            if type == "LINK", let url { map["attributes"] = ["url": url] }
            if type == "ANIMOJI", let url { map["attributes"] = ["animojiLottieUrl": url] }
            if let entityId { map["entityId"] = Int64(entityId).map { $0 as Any } ?? entityId }
            if let extra, let data = extra.data(using: .utf8),
               let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                for (key, value) in object where map[key] == nil { map[key] = value }
            }
            return map
        }
    }

    /// Что уйдёт на сервер для текста [text]: отрезки обрезаны по нему, слиты и упорядочены.
    /// Пустой список — разметки нет (при правке его и нужно слать, чтобы снять разметку).
    public static func elements(_ spans: [TextSpan], text: String) -> [Element] {
        let total = text.utf16.count
        return normalize(spans.compactMap { clip($0, length: total) }).map { span in
            switch span.kind {
            case .link: Element(type: "LINK", from: span.from, length: span.length, url: span.url)
            case .mention: Element(type: "USER_MENTION", from: span.from, length: span.length, entityId: span.userId)
            case .animoji: Element(type: "ANIMOJI", from: span.from, length: span.length, url: span.url, entityId: span.entityId)
            case .unknown: Element(type: span.type ?? "UNKNOWN", from: span.from, length: span.length, extra: span.extra)
            default: Element(type: type(of: span.kind), from: span.from, length: span.length)
            }
        }
    }

    /// Ключи элемента, кроме `type`, `from` и `length`, объектом JSON с упорядоченными ключами;
    /// `nil` — других ключей нет.
    public static func extraJSON(_ element: [String: Any]) -> String? {
        let rest = element.filter { !["type", "from", "length"].contains($0.key) }
        guard !rest.isEmpty, JSONSerialization.isValidJSONObject(rest),
              let data = try? JSONSerialization.data(withJSONObject: rest, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// [elements] строкой JSON (для моста ядра). Пустой список — `[]`.
    public static func json(_ elements: [Element]) -> String {
        let objects = elements.map(\.json)
        guard let data = try? JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    /// Текст поля без пробелов и переводов строк по краям и отрезки по нему: начало сдвинуто
    /// на срезанное, вышедшее за края обрезано.
    public static func trimmed(_ draft: String, spans: [TextSpan]) -> (text: String, spans: [TextSpan]) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ("", []) }
        let lead = draft.range(of: text).map { draft[draft.startIndex..<$0.lowerBound].utf16.count } ?? 0
        let total = text.utf16.count
        let shifted = spans.compactMap { span -> TextSpan? in
            var copy = span
            copy.from = span.from - lead
            let end = span.from + span.length - lead
            let from = max(copy.from, 0)
            let to = min(end, total)
            guard to > from else { return nil }
            copy.from = from
            copy.length = to - from
            return copy
        }
        return (text, shifted)
    }

    /// Правка сообщения (`MSG_EDIT` 67): обрезанный текст и весь список разметки (пустой —
    /// `[]`, он снимает разметку). `nil` — текст и разметка не изменились, запрос не нужен.
    public static func editRequest(originalText: String, originalSpans: [TextSpan], draft: String, spans: [TextSpan]) -> (text: String, elements: [Element])? {
        let edited = trimmed(draft, spans: spans)
        let before = trimmed(originalText, spans: originalSpans)
        let fresh = elements(edited.spans, text: edited.text)
        if edited.text == before.text, fresh == elements(before.spans, text: before.text) { return nil }
        return (edited.text, fresh)
    }

    // MARK: Поле ввода

    /// Весь `[start, end)` накрыт отрезками вида [kind]. Пустой отрезок не накрыт.
    public static func covers(_ spans: [TextSpan], kind: TextSpan.Kind, start: Int, end: Int) -> Bool {
        guard start < end else { return false }
        var reached = start
        for span in spans.filter({ $0.kind == kind }).sorted(by: { $0.from < $1.from }) {
            if span.from > reached { break }
            reached = max(reached, span.from + span.length)
            if reached >= end { return true }
        }
        return false
    }

    /// Кнопка панели: размеченное целиком `[start, end)` — снять (отрезок режется), иначе
    /// разметить весь `[start, end)`, сливаясь с соседями того же вида. Ссылку ставит [setLink].
    public static func toggle(_ spans: [TextSpan], kind: TextSpan.Kind, start: Int, end: Int) -> [TextSpan] {
        guard start < end, kind != .link, kind != .mention, kind != .animoji, kind != .unknown else { return spans }
        if covers(spans, kind: kind, start: start, end: end) {
            return normalize(subtract(spans, kind: kind, start: start, end: end))
        }
        return normalize(spans + [TextSpan(kind: kind, from: start, length: end - start)])
    }

    /// Ссылка [url] на `[start, end)` вместо прежних ссылок там; `nil` — убрать ссылку.
    public static func setLink(_ spans: [TextSpan], start: Int, end: Int, url: String?) -> [TextSpan] {
        guard start < end else { return spans }
        let rest = subtract(spans, kind: .link, start: start, end: end)
        guard let url else { return normalize(rest) }
        return normalize(rest + [TextSpan(kind: .link, from: start, length: end - start, url: url)])
    }

    /// Адрес ссылки, которая целиком накрывает `[start, end)`.
    public static func link(in spans: [TextSpan], start: Int, end: Int) -> String? {
        guard start < end else { return nil }
        return spans.first { $0.kind == .link && $0.from <= start && $0.from + $0.length >= end }?.url
    }

    /// Убрать формат [kind] (или всё оформление панели, если `nil`) с `[start, end)`.
    public static func clear(_ spans: [TextSpan], kind: TextSpan.Kind? = nil, start: Int, end: Int) -> [TextSpan] {
        let kinds = kind.map { [$0] } ?? toolbar
        var result = spans
        for item in kinds { result = subtract(result, kind: item, start: start, end: end) }
        return normalize(result)
    }

    /// Правка текста: на месте [at] убрано [removed] и вставлено [inserted] единиц UTF-16.
    /// Вставка до отрезка или в его начало сдвигает его, внутри — растягивает, в конце и дальше —
    /// не трогает. Удалённое вырезается из отрезков, пустые выпадают; замена внутри отрезка
    /// размечается так же.
    public static func replace(_ spans: [TextSpan], at: Int, removed: Int, inserted: Int) -> [TextSpan] {
        guard removed != 0 || inserted != 0 else { return spans }
        return normalize(spans.compactMap { shift($0, at: at, removed: removed, inserted: inserted) })
    }

    /// Правка между двумя состояниями текста: общее начало и конец (UTF-16). [cursor] — курсор
    /// после правки (`nil` — неизвестен), уточняет место среди одинаковых знаков.
    public static func diff(old: String, new: String, cursor: Int? = nil) -> (at: Int, removed: Int, inserted: Int) {
        let a = Array(old.utf16)
        let b = Array(new.utf16)
        let shorter = min(a.count, b.count)
        var prefix = 0
        while prefix < shorter, a[prefix] == b[prefix] { prefix += 1 }
        var suffixLimit = shorter - prefix
        if let cursor, cursor >= 0, cursor <= b.count {
            let grown = max(b.count - a.count, 0)
            prefix = min(prefix, max(cursor - grown, 0))
            suffixLimit = min(shorter - prefix, b.count - cursor)
        }
        var suffix = 0
        while suffix < suffixLimit, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        return (prefix, a.count - prefix - suffix, b.count - prefix - suffix)
    }

    /// Адрес из поля «Ссылка»: без пробелов по краям, без схемы — `https://`. `nil` — пусто
    /// или в адресе пробелы.
    public static func normalizeURL(_ raw: String) -> String? {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !url.contains(where: \.isWhitespace) else { return nil }
        let lower = url.lowercased()
        if url.contains("://") || lower.hasPrefix("mailto:") || lower.hasPrefix("tel:") { return url }
        return "https://" + url
    }

    // MARK: Внутреннее

    private static func shift(_ span: TextSpan, at: Int, removed: Int, inserted: Int) -> TextSpan? {
        let start = span.from
        let end = span.from + span.length
        let cut = at + removed
        let delta = inserted - removed
        let from: Int
        let to: Int
        if removed == 0 {
            if at <= start { (from, to) = (start + delta, end + delta) }
            else if at < end { (from, to) = (start, end + delta) }
            else { (from, to) = (start, end) }
        } else if cut <= start {
            (from, to) = (start + delta, end + delta)
        } else if at >= end {
            (from, to) = (start, end)
        } else if at >= start, cut <= end {
            (from, to) = (start, end + delta)
        } else if at <= start, cut >= end {
            return nil
        } else if at < start {
            (from, to) = (at + inserted, at + inserted + (end - cut))
        } else {
            (from, to) = (start, at)
        }
        guard to > from else { return nil }
        var copy = span
        copy.from = from
        copy.length = to - from
        return copy
    }

    private static func subtract(_ spans: [TextSpan], kind: TextSpan.Kind, start: Int, end: Int) -> [TextSpan] {
        spans.flatMap { span -> [TextSpan] in
            let from = span.from
            let to = span.from + span.length
            if span.kind != kind || to <= start || from >= end { return [span] }
            var parts: [TextSpan] = []
            if from < start {
                var head = span
                head.length = start - from
                parts.append(head)
            }
            if to > end {
                var tail = span
                tail.from = end
                tail.length = to - end
                parts.append(tail)
            }
            return parts
        }
    }

    static func number(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            // JSON `true`/`false` — тоже NSNumber (тип `c`), но это не смещение.
            if String(cString: number.objCType) == "c" { return nil }
            let double = number.doubleValue
            guard double == double.rounded(), abs(double) < Double(Int32.max) else { return nil }
            return number.intValue
        case let int as Int: return int
        case let string as String: return Int(string)
        default: return nil
        }
    }

    static func identifier(_ value: Any?) -> String? {
        switch value {
        case let string as String: string.isEmpty ? nil : string
        case let number as NSNumber: number.int64Value.description
        default: nil
        }
    }
}
