import Foundation

/// Адрес фото профиля для просмотра на весь экран.
///
/// У человека сервер присылает `baseUrl` (квадрат под кружок) и `baseRawUrl` (снимок целиком,
/// без обрезки), у группы и канала — `baseIconUrl` и `baseRawIconUrl`. Размер задаёт запрос
/// `fn` (`sqr_N` у квадрата, `w_N` у снимка), адрес без `fn` — оригинал. Ядро дописывает
/// размер как `&fn=…`, даже когда `?` в адресе нет.
///
/// Оригинал (`avatarFullUrl` ядра) просмотр пробует первым. Если он не загрузился, идут
/// размеры сервера от большего к меньшему (`avatarViewerUrls`, начиная с `w_1440`).
public enum ProfilePhotoURL {
    /// Оригинал: снимок целиком, если ядро его дало, иначе аватар без `fn`.
    public static func full(avatar: URL?, raw: URL?) -> URL? {
        if let raw { return withoutSize(raw) }
        return avatar.map(withoutSize)
    }

    /// По порядку, что загружать: оригинал, потом размеры сервера. Повторы убраны.
    /// Маленький аватар сюда не входит: он только виден, пока грузится первый удачный.
    public static func candidates(avatar: URL?, raw: URL?, viewer: [URL]) -> [URL] {
        var seen = Set<URL>()
        return ([full(avatar: avatar, raw: raw)].compactMap { $0 } + viewer).filter { seen.insert($0).inserted }
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
