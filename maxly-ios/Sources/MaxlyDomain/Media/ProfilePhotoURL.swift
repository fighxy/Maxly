import Foundation

/// Адрес фото профиля для просмотра на весь экран.
///
/// У человека сервер присылает `baseUrl` (квадрат под кружок) и `baseRawUrl` (снимок целиком,
/// без обрезки), у группы и канала — `baseIconUrl` и `baseRawIconUrl`. Размер задаёт запрос
/// `fn` (`sqr_N` у квадрата, `w_N` у снимка), адрес без `fn` — оригинал. Ядро дописывает
/// размер как `&fn=…`, даже когда `?` в адресе нет.
public enum ProfilePhotoURL {
    /// Что открыть на весь экран: снимок целиком, если ядро его дало, иначе оригинал аватара.
    /// Маленькую картинку из кэша просмотр показывает, пока грузится эта.
    public static func full(avatar: URL?, raw: URL?) -> URL? {
        if let raw { return withoutSize(raw) }
        return avatar.map(withoutSize)
    }

    /// Тот же адрес без запроса `fn`. Остальные параметры (подпись, срок) остаются.
    public static func withoutSize(_ url: URL) -> URL {
        guard !url.isFileURL else { return url }
        var pieces: [(separator: Character?, body: String)] = []
        var separator: Character?
        var body = ""
        for character in url.absoluteString {
            if character == "?" || character == "&" {
                pieces.append((separator, body))
                separator = character
                body = ""
            } else {
                body.append(character)
            }
        }
        pieces.append((separator, body))
        guard pieces.dropFirst().contains(where: { $0.body.hasPrefix("fn=") }) else { return url }

        let kept = [pieces[0]] + pieces.dropFirst().filter { !$0.body.hasPrefix("fn=") }
        let hadQuery = pieces.contains { $0.separator == "?" }
        var keptQuery = kept.contains { $0.separator == "?" }
        var text = ""
        for piece in kept {
            if var mark = piece.separator {
                // Убрали `?fn=…`: первый оставшийся параметр открывает запрос.
                if hadQuery, !keptQuery, mark == "&" {
                    mark = "?"
                    keptQuery = true
                }
                text.append(mark)
            }
            text += piece.body
        }
        return URL(string: text) ?? url
    }
}
