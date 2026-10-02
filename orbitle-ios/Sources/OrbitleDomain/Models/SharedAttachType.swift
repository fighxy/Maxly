import Foundation

/// Тип вложения в запросе общих медиа чата. Значение — имя типа на сервере (`_type`).
public enum SharedAttachType: String, CaseIterable, Hashable, Sendable {
    case photo = "PHOTO"
    case video = "VIDEO"
    case file = "FILE"
    case audio = "AUDIO"
    case share = "SHARE"
}
