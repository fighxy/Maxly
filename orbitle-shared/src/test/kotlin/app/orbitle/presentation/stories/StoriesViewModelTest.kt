package app.orbitle.presentation.stories

import app.orbitle.MainDispatcherRule
import app.orbitle.data.OwnerStories
import app.orbitle.data.StoriesRepository
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.OutgoingStory
import app.orbitle.domain.Story
import app.orbitle.domain.StoryAudience
import app.orbitle.domain.StoryMedia
import app.orbitle.domain.StoryOwner
import app.orbitle.domain.StoryRing
import kotlinx.coroutines.flow.MutableSharedFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

private class FakeStories : StoriesRepository {
    override var currentUserId: String? = "1"
    override val updates = MutableSharedFlow<StoryRing>(extraBufferCapacity = 8)
    var feed: List<StoryRing> = emptyList()
    val owners = mutableMapOf<String, OwnerStories>()
    val marked = mutableListOf<String>()
    val deleted = mutableListOf<List<String>>()
    val published = mutableListOf<Pair<OutgoingStory, StoryAudience>>()
    var storyRequests = 0
    var failure: Throwable? = null
    var publishReply: StoryRing? = null

    override suspend fun feed(): List<StoryRing> = feed
    override suspend fun stories(owner: StoryOwner): OwnerStories {
        storyRequests++
        failure?.let { throw it }
        return owners[owner.id] ?: OwnerStories(null, emptyList())
    }
    override suspend fun markSeen(owner: StoryOwner, storyId: String) {
        marked += storyId
    }
    override suspend fun publish(story: OutgoingStory, audience: StoryAudience, progress: (Float) -> Unit): StoryRing? {
        failure?.let { throw it }
        progress(0.5f)
        published += story to audience
        return publishReply
    }
    override suspend fun delete(storyIds: List<String>) {
        failure?.let { throw it }
        deleted += storyIds
    }
}

class StoriesViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val repo = FakeStories()

    private fun ring(id: String, total: Int, read: Int, at: Long, name: String = "u$id") =
        StoryRing(StoryOwner(id), name, null, at, total, read)

    private fun story(owner: String, id: String, at: Long, media: Boolean = true) =
        Story(id, StoryOwner(owner), at, media = if (media) StoryMedia(false, "https://i/$id") else null)

    @Test
    fun feedPutsUnseenFirstThenFreshAndKeepsOwnApart() {
        repo.feed = listOf(ring("2", 2, 2, 300), ring("3", 1, 0, 100), ring("4", 3, 1, 200), ring("1", 1, 0, 50), ring("5", 0, 0, 900))
        val model = StoriesViewModel(repo)
        val state = model.state.value
        assertEquals(listOf("4", "3", "2"), state.rings.map { it.owner.id })
        assertEquals("1", state.own?.owner?.id)
        assertEquals("3", state.ringOf("3")?.owner?.id)
        assertNull(state.ringOf("5"))
        assertNull(state.ringOf("0"))
    }

    @Test
    fun viewerResumesAtFirstUnseenMarksOnceAndPagesOwners() {
        repo.feed = listOf(ring("4", 3, 1, 200), ring("3", 1, 0, 100))
        repo.owners["4"] = OwnerStories(ring("4", 3, 1, 200), listOf(story("4", "41", 1), story("4", "42", 2), story("4", "43", 3)))
        repo.owners["3"] = OwnerStories(ring("3", 1, 0, 100), listOf(story("3", "31", 5)))
        val model = StoriesViewModel(repo)
        model.open("4")
        var viewer = model.state.value.viewer!!
        assertEquals("42", viewer.story?.id)
        assertEquals(listOf("42"), repo.marked)
        assertEquals(2, model.state.value.ringOf("4")?.read)
        model.previous()
        // Просмотренная до открытия история не отмечается снова.
        assertEquals("41", model.state.value.viewer?.story?.id)
        assertEquals(listOf("42"), repo.marked)
        model.next()
        model.next()
        assertEquals("43", model.state.value.viewer?.story?.id)
        assertEquals(listOf("42", "43"), repo.marked)
        assertEquals(3, model.state.value.ringOf("4")?.read)
        model.next()
        viewer = model.state.value.viewer!!
        assertEquals("3", viewer.ring.owner.id)
        assertEquals("31", viewer.story?.id)
        model.next()
        assertNull(model.state.value.viewer)
        // Оба кольца погасли: порядок теперь только по свежести.
        assertEquals(listOf("4", "3"), model.state.value.rings.map { it.owner.id })
        assertTrue(model.state.value.rings.none { it.hasUnread })
    }

    @Test
    fun cachedStoriesAreNotAskedAgainAndEmptyOwnersAreSkipped() {
        repo.feed = listOf(ring("4", 1, 0, 200), ring("3", 1, 0, 100))
        repo.owners["4"] = OwnerStories(ring("4", 1, 0, 200), listOf(story("4", "41", 1, media = false)))
        repo.owners["3"] = OwnerStories(ring("3", 1, 0, 100), listOf(story("3", "31", 1)))
        val model = StoriesViewModel(repo)
        model.open("4")
        assertEquals("31", model.state.value.viewer?.story?.id)
        model.close()
        model.open("3")
        assertEquals(2, repo.storyRequests)
    }

    @Test
    fun ownStoriesAreNotMarkedAndCanBeDeleted() {
        repo.feed = listOf(ring("1", 2, 0, 100), ring("3", 1, 0, 100))
        repo.owners["1"] = OwnerStories(ring("1", 2, 0, 100), listOf(story("1", "11", 1), story("1", "12", 2)))
        val model = StoriesViewModel(repo)
        model.open("1")
        val viewer = model.state.value.viewer!!
        assertTrue(viewer.isOwn)
        assertEquals(1, viewer.queue.size)
        assertTrue(repo.marked.isEmpty())
        model.deleteCurrent()
        assertEquals(listOf(listOf("11")), repo.deleted)
        assertEquals("12", model.state.value.viewer?.story?.id)
        assertEquals(1, model.state.value.own?.total)
        model.deleteCurrent()
        assertNull(model.state.value.viewer)
        assertNull(model.state.value.own)
    }

    @Test
    fun pushesUpdateAndDropRings() {
        repo.feed = listOf(ring("3", 1, 0, 100, name = "Анна"))
        val model = StoriesViewModel(repo)
        repo.updates.tryEmit(ring("3", 2, 1, 400, name = ""))
        assertEquals("Анна", model.state.value.ringOf("3")?.name)
        assertEquals(2, model.state.value.ringOf("3")?.total)
        repo.updates.tryEmit(ring("7", 1, 0, 500))
        assertEquals(listOf("7", "3"), model.state.value.rings.map { it.owner.id })
        repo.updates.tryEmit(ring("3", 0, 0, 600))
        assertNull(model.state.value.ringOf("3"))
    }

    @Test
    fun ringOutsideTheFeedIsAskedOnceForAProfile() {
        repo.owners["9"] = OwnerStories(ring("9", 1, 0, 100), listOf(story("9", "91", 1)))
        val model = StoriesViewModel(repo)
        model.loadRing("9")
        model.loadRing("9")
        model.loadRing("0")
        assertEquals(1, repo.storyRequests)
        assertNotNull(model.state.value.ringOf("9"))
        model.open("9")
        assertEquals(1, model.state.value.viewer?.queue?.size)
        assertEquals("91", model.state.value.viewer?.story?.id)
        assertEquals(1, repo.storyRequests)
    }

    @Test
    fun publishShowsProgressAndAddsOwnRing() {
        val model = StoriesViewModel(repo, now = { 777 })
        model.publish(OutgoingStory("/tmp/a.jpg", isVideo = false), StoryAudience.CONTACTS)
        assertEquals(StoryAudience.CONTACTS, repo.published.single().second)
        val state = model.state.value
        assertNull(state.publishProgress)
        assertEquals(1, state.own?.total)
        assertEquals(777L, state.own?.updatedAtMs)
        assertEquals("История опубликована", state.message)
        repo.publishReply = ring("1", 5, 0, 900)
        model.publish(OutgoingStory("/tmp/b.mp4", isVideo = true, durationMs = 3000), StoryAudience.EVERYONE)
        assertEquals(5, model.state.value.own?.total)
    }

    @Test
    fun failuresBecomeMessages() {
        repo.feed = listOf(ring("3", 1, 0, 100))
        val model = StoriesViewModel(repo)
        repo.failure = OrbitleError.NetworkUnavailable
        model.open("3")
        assertNull(model.state.value.viewer)
        assertEquals("Нет соединения с сервером", model.state.value.message)
        model.consumeMessage()
        model.publish(OutgoingStory("/tmp/a.jpg", isVideo = false), StoryAudience.EVERYONE)
        assertNull(model.state.value.publishProgress)
        assertEquals("Нет соединения с сервером", model.state.value.message)
    }

    @Test
    fun resumeIndexFollowsReadCount() {
        assertEquals(0, StoriesViewModel.resumeIndex(ring("1", 3, 0, 0), 3))
        assertEquals(2, StoriesViewModel.resumeIndex(ring("1", 3, 2, 0), 3))
        assertEquals(0, StoriesViewModel.resumeIndex(ring("1", 3, 3, 0), 3))
    }
}
