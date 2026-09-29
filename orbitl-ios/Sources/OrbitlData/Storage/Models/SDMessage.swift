import Foundation
import SwiftData

/// SwiftData-модель для `Message`. Наружу из OrbitlData не выходит.
// TODO: поля и маппинг в доменную модель.
@Model
final class SDMessage {
    @Attribute(.unique) var id: String

    init(id: String) {
        self.id = id
    }
}
