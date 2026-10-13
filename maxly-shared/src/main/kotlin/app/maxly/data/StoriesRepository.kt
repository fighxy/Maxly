package app.maxly.data

import app.maxly.domain.MaxlyError
import app.maxly.domain.OutgoingStory
import app.maxly.domain.StoryFlags
import app.maxly.domain.Story
import app.maxly.domain.StoryAudience
import app.maxly.domain.StoryMedia
import app.maxly.domain.StoryOwner
import app.maxly.domain.StoryRing
import com.maxly.core.api.StoryPreview
import com.maxly.core.events.MaxEvent
import com.maxly.core.media.UploadProgress
import com.maxly.core.state.MaxState
import com.maxly.shared.MaxClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.map
import com.maxly.core.api.Story as CoreStory
import com.maxly.core.api.StoryAudience as CoreAudience
import com.maxly.core.api.StoryOwner as CoreOwner

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

    /**
     * Страница своего архива историй (`STORIES_HISTORY_GET_BY_OWNER_ID` 219, по 30). [marker]
     * `null` — первая страница.
     */
    suspend fun ownArchive(marker: Long?): app.maxly.domain.StoryArchive = app.maxly.domain.StoryArchive(emptyList(), null)

    /** Лайк истории [emoji] или снять его (`null`). `false` — сервер не принял. */
    suspend fun react(story: Story, emoji: String?): Boolean = false

    /** Ответ на историю: сообщение в чат с автором со ссылкой на историю. */
    suspend fun reply(story: Story, text: String) {}

    /** Скрыть истории автора у себя (или показать снова). */
    suspend fun setHidden(owner: StoryOwner, hidden: Boolean) {}

    /** Причины жалобы на историю. */
    suspend fun reportReasons(): List<ComplaintChoice> = emptyList()

    /** Пожаловаться на историю. `false` — сервер не принял. */
    suspend fun report(story: Story, reasonId: Int): Boolean = false

    /** Сохранить фото или видео истории в галерею (телефон) или «Загрузки» (компьютер). */
    suspend fun download(story: Story): Boolean = false
}

class CoreStoriesRepository(
    private val client: MaxClient,
    /** Кэш файлов и папка сохранения для «Скачать»; без них скачивание недоступно. */
    private val files: app.maxly.presentation.chat.MessageFiles? = null,
    private val saver: app.maxly.presentation.chat.MediaSaver? = null,
) : StoriesRepository {
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

    /** Через ядро: при скрытых отметках о прочтении оно просмотр не отправляет. */
    override suspend fun markSeen(owner: StoryOwner, storyId: String) {
        val id = storyId.toLongOrNull() ?: return
        MaxCoreGateway.call { client.markStorySeen(coreOwner(owner), id) }
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

    override suspend fun ownArchive(marker: Long?): app.maxly.domain.StoryArchive {
        val page = MaxCoreGateway.read { client.ownStoryArchive(marker) }
        return app.maxly.domain.StoryArchive(page.stories.map(::story), page.marker)
    }

    override suspend fun react(story: Story, emoji: String?): Boolean {
        val id = story.id.toLongOrNull() ?: return false
        return MaxCoreGateway.call { client.api.stories.react(coreOwner(story.owner), id, emoji) }
    }

    override suspend fun reply(story: Story, text: String) {
        val id = story.id.toLongOrNull() ?: return
        val owner = coreOwner(story.owner)
        // С человеком — его диалог (`свой id xor id автора`), у группы и канала — сам чат.
        val chatId = if (owner.type == CoreOwner.Type.USER) {
            val me = client.store.state.value.me ?: throw MaxlyError.Rejected("Нет входа в аккаунт")
            me xor owner.ownerId
        } else {
            owner.ownerId
        }
        val sent = MaxCoreGateway.call { client.api.messages.sendStoryReply(chatId, text.trim(), owner, id, story.expiresAtMs) }
        client.store.putSentMessage(chatId, sent)
    }

    override suspend fun setHidden(owner: StoryOwner, hidden: Boolean) {
        val core = coreOwner(owner)
        MaxCoreGateway.call {
            if (core.type == CoreOwner.Type.USER) client.api.users.setStoriesHidden(core.ownerId, hidden) else client.api.chats.setStoriesHidden(core.ownerId, hidden)
        }
    }

    override suspend fun reportReasons(): List<ComplaintChoice> = MaxCoreGateway.readNow {
        client.api.complaints.reasons()[com.maxly.core.api.ComplaintsApi.STORY].orEmpty().map { ComplaintChoice(it.reasonId, it.reasonTitle) }
    }

    override suspend fun report(story: Story, reasonId: Int): Boolean {
        val id = story.id.toLongOrNull() ?: return false
        val owner = story.owner.id.toLongOrNull() ?: return false
        return MaxCoreGateway.call { client.api.complaints.send(reasonId, com.maxly.core.api.ComplaintsApi.STORY, listOf(id), owner) }
    }

    override suspend fun download(story: Story): Boolean {
        val files = files ?: return false
        val saver = saver ?: return false
        val media = story.media ?: return false
        val ext = if (media.isVideo) "mp4" else "jpg"
        val path = files.download(media.url, "story-${story.id}", "story-${story.id}.$ext") {}
        val name = app.maxly.presentation.chat.SaveNaming.name(story.timeMs, 0, if (media.isVideo) "mp4" else app.maxly.presentation.chat.SaveNaming.imageExtension(header(path)))
        saver.save(path, name, if (media.isVideo) app.maxly.presentation.chat.SavedKind.VIDEO else app.maxly.presentation.chat.SavedKind.IMAGE)
        return true
    }

    private fun header(path: String): ByteArray = runCatching {
        java.io.File(path).inputStream().use { input -> ByteArray(16).let { buf -> buf.copyOf(maxOf(0, input.read(buf))) } }
    }.getOrDefault(ByteArray(0))

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
                name = (if (user != null) state.displayName(id) else null)?.takeIf { it.isNotBlank() } ?: chat?.title.orEmpty(),
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
                audience = if (core.settings and StoryFlags.VISIBLE_FOR_CONTACTS != 0) StoryAudience.CONTACTS else StoryAudience.EVERYONE,
                media = media?.url?.let { StoryMedia(media.isVideo, it, media.thumbnailUrl, media.width, media.height, media.durationMs) },
                reaction = core.reaction,
                settings = core.settings,
                viewsCount = core.viewsCount,
            )
        }
    }
}
