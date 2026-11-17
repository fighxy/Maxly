package app.maxly.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Весь список чатов догружается один раз на аккаунт, а не только когда стор пуст. */
class ChatListPagingTest {
    @Test
    fun firstRefreshAfterLoginLoadsTheWholeList() {
        // Стор после входа уже содержит первые чаты из LOGIN: это не мешает догрузить остальные.
        assertTrue(CoreChatRepository.needsFullList(me = 7L, fullListFor = null))
    }

    @Test
    fun laterRefreshesAskOnlyTheFirstPage() {
        assertFalse(CoreChatRepository.needsFullList(me = 7L, fullListFor = 7L))
    }

    @Test
    fun anotherAccountLoadsItsWholeListAgain() {
        assertTrue(CoreChatRepository.needsFullList(me = 8L, fullListFor = 7L))
    }

    @Test
    fun beforeLoginTheWholeListIsAskedAgainLater() {
        assertTrue(CoreChatRepository.needsFullList(me = null, fullListFor = null))
        assertTrue(CoreChatRepository.needsFullList(me = null, fullListFor = 7L))
    }
}
