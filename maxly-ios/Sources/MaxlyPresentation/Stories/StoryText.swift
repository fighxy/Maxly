import Foundation
import MaxlyDomain

/// Подписи и аватары историй.
public enum StoryText {
    public static let yourStory = "Ваша история"
    public static let noName = "Без имени"
    /// Больше этого сегментов кольцо не рисует: при длинной ленте они слились бы в линию.
    public static let maxSegments = 30

    public static func avatar(_ ring: StoryRing) -> ChatAvatar {
        avatar(id: ring.owner.id, name: ring.name, url: ring.avatarURL)
    }

    /// Аватар по id, имени и фото: свой для плитки «Ваша история», чужой для кольца.
    public static func avatar(id: String, name: String, url: URL?) -> ChatAvatar {
        let initials = ChatAvatar.initials(for: name.isEmpty ? noName : name)
        let kind: ChatAvatar.Kind = url.map { .photo($0, initials: initials) } ?? .initials(initials)
        return ChatAvatar(kind: kind, colorIndex: ChatAvatar.colorIndex(for: id))
    }

    public static func title(_ ring: StoryRing, own: Bool) -> String {
        own ? yourStory : (ring.name.isEmpty ? noName : ring.name)
    }

    /// Сколько сегментов у кольца и сколько из них уже просмотрено.
    public static func segments(_ ring: StoryRing) -> (count: Int, read: Int) {
        let count = min(max(ring.total, 1), maxSegments)
        return (count, min(max(ring.read, 0), count))
    }

    /// «только что», «5 мин назад», «3 ч назад»; старше суток — «вчера».
    public static func ago(_ time: Date, now: Date) -> String {
        guard time.timeIntervalSince1970 > 0 else { return "" }
        let minutes = max(0, Int(now.timeIntervalSince(time) / 60))
        switch minutes {
        case ..<1: return "только что"
        case ..<60: return "\(minutes) мин назад"
        case ..<(24 * 60): return "\(minutes / 60) ч назад"
        default: return "вчера"
        }
    }

    /// Сколько показывать историю: фото — 5 секунд, видео — сколько длится (от 1 до 60 с).
    public static func duration(_ story: Story) -> TimeInterval {
        guard let media = story.media, media.isVideo, let length = media.duration, length > 0 else { return 5 }
        return min(max(length, 1), 60)
    }
}
