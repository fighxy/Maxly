package app.orbitle.presentation.stories

import app.orbitle.domain.StoryOwner
import app.orbitle.domain.StoryRing

/**
 * Жест полосы историй над списком чатов.
 * Палец вверх — отрицательный [dragPx]. Полоса полностью открыта при доле 1.
 * Список не у верхнего края жест не принимает: листаются чаты.
 * Шапка (поиск и папки) передаёт `atTop = true` всегда: её можно потянуть и из середины списка.
 */
object StoryStripMotion {
    /** Порог, после которого отпущенный жест доводится до конца. */
    const val THRESHOLD_DP = 48f

    fun reveal(expanded: Boolean, dragPx: Float, heightPx: Float, atTop: Boolean): Float {
        if (heightPx <= 0f) return if (expanded) 1f else 0f
        if (!atTop) return if (expanded) 1f else 0f
        val base = if (expanded) 1f else 0f
        val moved = when {
            expanded && dragPx < 0f -> dragPx
            !expanded && dragPx > 0f -> dragPx
            else -> 0f
        }
        return (base + moved / heightPx).coerceIn(0f, 1f)
    }

    /** Каким останется флаг «открыта» после отпускания. */
    fun settledExpanded(wasExpanded: Boolean, dragPx: Float, atTop: Boolean, thresholdPx: Float): Boolean {
        if (!atTop) return wasExpanded
        return if (wasExpanded) dragPx > -thresholdPx else dragPx >= thresholdPx
    }

    /** Потянуть список вниз обновляет чаты только у уже открытой полосы. */
    fun refreshesOnPull(expanded: Boolean): Boolean = expanded

    /** Кольцо на аватаре чата: у человека любое, у группы и канала — только их тип. */
    fun ringMatches(ring: StoryRing?, ownerType: StoryOwner.Type): Boolean {
        ring ?: return false
        return ownerType == StoryOwner.Type.USER || ring.owner.type == ownerType
    }
}
