import Foundation
import SwiftData

/// SwiftData-модель для `MediaItem`. Наружу из OrbitlData не выходит.
// TODO: поля и маппинг в доменную модель.
@Model
final class SDMediaItem {
    @Attribute(.unique) var id: String

    init(id: String) {
        self.id = id
    }
}
