import Foundation
import SwiftData

/// SwiftData-модель для `Chat`. Наружу из OrbitlData не выходит.
// TODO: поля и маппинг в доменную модель.
@Model
final class SDChat {
    @Attribute(.unique) var id: String

    init(id: String) {
        self.id = id
    }
}
