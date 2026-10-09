package app.maxly.presentation.stories

import app.maxly.MainDispatcherRule
import app.maxly.data.OwnerStories
import app.maxly.data.StoriesRepository
import app.maxly.domain.MaxlyError
import app.maxly.domain.OutgoingStory
import app.maxly.domain.Story
import app.maxly.domain.StoryArchive
import app.maxly.domain.StoryAudience
import app.maxly.domain.StoryOwner
import app.maxly.domain.StoryRing
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class MyStoriesViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private fun story(id: Int) = Story(id.toString(), StoryOwner("1"), timeMs = id * 1_000L, media = null)

    private class Archive(val pages: MutableMap<Long?, StoryArchive>) : StoriesRepository {
        val asked = mutableListOf<Long?>()
        var failure: Exception? = null
        override val currentUserId: String? = "1"
        override val updates: Flow<StoryRing> = emptyFlow()
        override suspend fun feed(): List<StoryRing> = emptyList()
        override suspend fun stories(owner: StoryOwner) = OwnerStories(null, emptyList())
        override suspend fun markSeen(owner: StoryOwner, storyId: String) {}
        override suspend fun publish(story: OutgoingStory, audience: StoryAudience, progress: (Float) -> Unit): StoryRing? = null
        override suspend fun delete(storyIds: List<String>) {}
        override suspend fun ownArchive(marker: Long?): StoryArchive {
            asked += marker
            failure?.let { throw it }
            return pages.getValue(marker)
        }
    }

    @Test
    fun pagingAppendsUntilTheMarkerRunsOut() {
        val repo = Archive(mutableMapOf(null to StoryArchive(listOf(story(3), story(2)), 88L), 88L to StoryArchive(listOf(story(2), story(1)), null)))
        val model = MyStoriesViewModel(repo)
        assertEquals(listOf("3", "2"), model.state.value.stories.map { it.id })
        assertTrue(model.state.value.canLoadMore)
        model.loadMore()
        assertEquals(listOf("3", "2", "1"), model.state.value.stories.map { it.id })
        assertTrue(model.state.value.end)
        model.loadMore()
        assertEquals(listOf<Long?>(null, 88L), repo.asked)
    }

    @Test
    fun emptyArchiveShowsTheCreateState() {
        val model = MyStoriesViewModel(Archive(mutableMapOf(null to StoryArchive(emptyList(), null))))
        assertTrue(model.state.value.isEmpty)
        assertFalse(model.state.value.canLoadMore)
    }

    @Test
    fun failureKeepsListAndAllowsRetry() {
        val repo = Archive(mutableMapOf(null to StoryArchive(listOf(story(1)), 5L)))
        repo.failure = MaxlyError.Rejected("Нет сети")
        val model = MyStoriesViewModel(repo)
        assertFalse(model.state.value.loaded)
        assertEquals("Нет сети", model.state.value.error)
        repo.failure = null
        model.reload()
        assertEquals(listOf("1"), model.state.value.stories.map { it.id })
        assertNull(model.state.value.error)
    }

    @Test
    fun zeroMarkerMeansTheEnd() {
        val state = StoryArchivePaging.apply(StoryArchiveState(), StoryArchive(listOf(story(1)), 0L), first = true)
        assertTrue(state.end)
        assertNull(state.marker)
    }
}
