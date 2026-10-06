package app.orbitle.data

import app.orbitle.domain.OutgoingStory
import app.orbitle.domain.Story
import app.orbitle.domain.StoryAudience
import app.orbitle.domain.StoryMedia
import app.orbitle.domain.StoryOwner
import app.orbitle.domain.StoryRing
import com.max.core.api.StoryPreview
import com.max.core.events.MaxEvent
import com.max.core.media.UploadProgress
import com.max.core.state.MaxState
import com.max.shared.MaxClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.map
import com.max.core.api.Story as CoreStory
import com.max.core.api.StoryAudience as CoreAudience
import com.max.core.api.StoryOwner as CoreOwner

/** Истории владельца: свежее кольцо (`null` — историй больше нет) и сами истории, от старых к новым. */
data class OwnerStories(val ring: StoryRing?, val stories: List<Story>)

/** Истории (сторис): лента колец, истории владельца, просмотр, публикация и удаление своих. */
interface StoriesRepository {
    /** Свой id: своё кольцо в ленте — «Ваша история». */
    val currentUserId: String?

    /** Пуши об изменении колец. Пустое кольцо — у владельца историй не осталось. */
    val updates: Flow<StoryRing>

    /** Первая страница ленты: по кольцу на владельца, пустые не входят. */
    suspend fun feed(): List<StoryRing>

    /** Истории [owner]: их ждёт пользователь, открывший кольцо. */
    suspend fun stories(owner: StoryOwner): OwnerStories

    suspend fun markSeen(owner: StoryOwner, storyId: String)

    /** Публикует историю на сутки; ответ — своё новое кольцо, если сервер его прислал. */
    suspend fun publish(story: OutgoingStory, audience: StoryAudience, progress: (Float) -> Unit): StoryRing?

    /** Удаляет свои истории. */
    suspend fun delete(storyIds: List<String>)
}

class CoreStoriesRepository(private val client: MaxClient) : StoriesRepository {
    override val currentUserId: String? get() = client.store.state.value.me?.toString()

    override val updates: Flow<StoryRing> = client.events.all
        .filterIsInstance<MaxEvent.StoriesUpdated>()
        .map { event ->
            resolve(listOf(event.preview))
            ring(event.preview, client.store.state.value)
        }

    override suspend fun feed(): List<StoryRing> {
        // Ядро не читает курсор следующей страницы, поэтому это одна страница.
        val previews = MaxCoreGateway.read { client.api.stories.feed(FEED_PAGE) }.filterNot { it.isEmpty }
        resolve(previews)
        val state = client.store.state.value
        return previews.map { ring(it, state) }
    }

    override suspend fun stories(owner: StoryOwner): OwnerStories {
        val core = coreOwner(owner)
        val reply = MaxCoreGateway.readNow { client.api.stories.byOwners(listOf(core)) }
        val preview = reply.previews.firstOrNull { it.owner.ownerId == core.ownerId && !it.isEmpty }
        preview?.let { resolve(listOf(it)) }
        val state = client.store.state.value
        return OwnerStories(
            ring = preview?.let { ring(it, state) },
            stories = reply.storiesOf(core).orEmpty().map(::story).sortedBy { it.timeMs },
        )
    }

    override suspend fun markSeen(owner: StoryOwner, storyId: String) {
        val id = storyId.toLongOrNull() ?: return
        MaxCoreGateway.call { client.api.stories.mark(coreOwner(owner), id) }
    }

    override suspend fun publish(story: OutgoingStory, audience: StoryAudience, progress: (Float) -> Unit): StoryRing? {
        val who = if (audience == StoryAudience.CONTACTS) CoreAudience.CONTACTS else CoreAudience.EVERYONE
        val upload = UploadProgress { sent, total -> if (total > 0) progress((sent.toFloat() / total).coerceIn(0f, 1f)) }
        val published = MaxCoreGateway.call {
            if (story.isVideo) {
                val token = client.media.uploadStoryVideo(story.path, upload)
                client.api.stories.publishVideo(token, story.durationMs?.takeIf { it > 0 }, who)
            } else {
                client.api.stories.publishPhoto(client.media.uploadStoryPhoto(story.path, upload), who)
            }
        }
        return published.preview?.takeIf { !it.isEmpty }?.let { ring(it, client.store.state.value) }
    }

    override suspend fun delete(storyIds: List<String>) {
        val ids = storyIds.mapNotNull { it.toLongOrNull() }
        if (ids.isEmpty()) return
        MaxCoreGateway.call { client.api.stories.delete(ids) }
    }

    /** Подгружает неизвестных владельцев-людей. Без имён кольца всё равно показываются. */
    private suspend fun resolve(previews: List<StoryPreview>) {
        val known = client.store.state.value.users
        val missing = previews.filter { it.owner.type == CoreOwner.Type.USER }
            .map { it.owner.ownerId }
            .filter { it !in known }
            .distinct()
        if (missing.isNotEmpty()) runCatching { missing.chunked(100).forEach { MaxCoreGateway.read { client.loadUsers(it) } } }
    }

    companion object {
        fun coreOwner(owner: StoryOwner): CoreOwner = CoreOwner(
            owner.id.toLong(),
            CoreOwner.Type.entries.firstOrNull { it.code == owner.type.code } ?: CoreOwner.Type.USER,
        )

        fun owner(core: CoreOwner): StoryOwner = StoryOwner(
            core.ownerId.toString(),
            StoryOwner.Type.entries.firstOrNull { it.code == core.type.code } ?: StoryOwner.Type.USER,
        )

        /** Кольцо с именем и аватаром владельца из стора: человек — из профилей, группа или канал — из чатов. */
        fun ring(preview: StoryPreview, state: MaxState): StoryRing {
            val id = preview.owner.ownerId
            val user = if (preview.owner.type == CoreOwner.Type.USER) state.users[id] else null
            val chat = state.chats[id]
            return StoryRing(
                owner = owner(preview.owner),
                name = user?.displayName?.takeIf { it.isNotBlank() } ?: chat?.title.orEmpty(),
                avatarUrl = user?.baseUrl?.takeIf { it.isNotBlank() } ?: (chat?.raw?.get("baseIconUrl") as? String)?.takeIf { it.isNotBlank() },
                updatedAtMs = preview.updateTime,
                total = preview.totalCount,
                read = preview.readCount,
                expiresAtMs = preview.lastStoryExpirationTime,
            )
        }

        const val FEED_PAGE = 100

        fun story(core: CoreStory): Story {
            val media = core.media
            return Story(
                id = core.id.toString(),
                owner = owner(core.owner),
                timeMs = core.time,
                expiresAtMs = core.expiration,
                audience = if (core.settings == StoryAudience.CONTACTS.code) StoryAudience.CONTACTS else StoryAudience.EVERYONE,
                media = media?.url?.let { StoryMedia(media.isVideo, it, media.thumbnailUrl, media.width, media.height, media.durationMs) },
            )
        }
    }
}
