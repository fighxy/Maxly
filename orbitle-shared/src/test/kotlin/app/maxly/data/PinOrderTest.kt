package app.maxly.data

import org.junit.Assert.assertEquals
import org.junit.Test

class PinOrderTest {
    @Test
    fun wantedOrderGoesFirstAndTheRestKeepTheirPlaces() {
        assertEquals(listOf(3L, 1L, 2L), CoreChatRepository.pinOrder(listOf(1L, 2L, 3L), listOf("3", "1", "2")))
        // Закреплённый в архиве (его нет в списке экрана) остаётся после переставленных.
        assertEquals(listOf(2L, 1L, 9L), CoreChatRepository.pinOrder(listOf(9L, 1L, 2L), listOf("2", "1")))
    }

    @Test
    fun unknownRepeatedAndUnpinnedIdsAreDropped() {
        assertEquals(listOf(2L, 1L), CoreChatRepository.pinOrder(listOf(1L, 2L), listOf("2", "2", "x", "5", "1")))
        assertEquals(emptyList<Long>(), CoreChatRepository.pinOrder(emptyList(), listOf("1")))
    }
}
