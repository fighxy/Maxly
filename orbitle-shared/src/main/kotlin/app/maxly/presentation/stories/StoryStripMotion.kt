package app.maxly.presentation.stories

import app.maxly.domain.StoryOwner
import app.maxly.domain.StoryRing

/** Кольца историй на аватарах списка. Жест полосы — в `ChatListHeaderGeometry`. */
object StoryStripMotion {
    /** Кольцо на аватаре чата: у человека любое, у группы и канала — только их тип. */
    fun ringMatches(ring: StoryRing?, ownerType: StoryOwner.Type): Boolean {
        ring ?: return false
        return ownerType == StoryOwner.Type.USER || ring.owner.type == ownerType
    }
}
