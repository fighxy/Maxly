package app.orbitle.presentation.common

/** Перестановка строк списка (папки, закреплённые чаты): чистые операции над id, без UI и сети. */
object ListOrder {
    /**
     * [ids] с элементом [from], перенесённым на место [to] (зажимается в границы списка).
     * Неизвестный [from] или перенос на то же место возвращают список без изменений.
     */
    fun moved(ids: List<String>, from: Int, to: Int): List<String> {
        if (from !in ids.indices) return ids
        val target = to.coerceIn(0, ids.lastIndex)
        if (target == from) return ids
        val next = ids.toMutableList()
        next.add(target, next.removeAt(from))
        return next
    }

    /** Те же id без повторов, возможно в другом порядке. */
    fun isPermutation(order: List<String>, of: List<String>): Boolean =
        order.size == of.size && order.toSet().size == order.size && order.toSet() == of.toSet()
}
