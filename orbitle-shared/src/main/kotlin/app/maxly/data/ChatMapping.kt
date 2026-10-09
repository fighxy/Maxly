package app.maxly.data

import app.maxly.domain.Chat
import app.maxly.domain.ChatLastMessage
import app.maxly.domain.ChatType
import app.maxly.domain.DeliveryState
import app.maxly.domain.MessageMediaKind
import app.maxly.domain.ServerFolder
import com.max.core.api.AccountConfig
import com.max.core.api.ChatFolders
import com.max.core.api.MaxMessage
import com.max.core.state.MaxState
import com.max.core.api.Chat as CoreChat

/** Чаты и папки ядра в моделях приложения. */
object ChatMapping {

    /** Список чатов без тех, где аккаунт больше не участвует ([isActive]). */
    fun chats(state: MaxState, config: AccountConfig?, nowMs: Long, mutes: ChatMutes? = null): List<Chat> {
        val pins = state.pinnedChatIds.orEmpty().withIndex().associate { (i, id) -> id to i }
        return state.chats.values.filter(::isActive).map { chat(it, state, config, nowMs, pins[it.id], mutes) }
    }

    /**
     * Аккаунт участвует в чате: `status` пуст или `ACTIVE`. Покинутый или закрытый чат сервер не
     * даёт ни покинуть, ни удалить (`chat.denied`), а историю отдаёт отказом `too.many.requests`,
     * поэтому в списке такого чата нет.
     */
    fun isActive(chat: CoreChat): Boolean {
        val status = chat.raw["status"] as? String
        return status.isNullOrEmpty() || status == "ACTIVE"
    }

    fun chat(chat: CoreChat, state: MaxState, config: AccountConfig?, nowMs: Long, pinOrder: Int? = null, mutes: ChatMutes? = null): Chat {
        val last = chat.lastMessage
        val updated = when {
            chat.lastEventTime > 0 -> chat.lastEventTime
            last != null -> last.time
            else -> 0L
        }
        val me = state.me
        val peerId = dialogPeer(chat, me)
        val peer = peerId?.let { state.users[it] }
        val title = chat.title?.takeIf { it.isNotBlank() } ?: peerId?.let(state::displayLabel).orEmpty()
        val avatar = (chat.raw["baseIconUrl"] as? String)?.takeIf { it.isNotBlank() } ?: peer?.baseUrl?.takeIf { it.isNotBlank() }
        val forwarded = forwardedOf(last)
        val attaches = last?.attaches?.takeIf { it.isNotEmpty() } ?: (forwarded?.get("attaches") as? List<*>).orEmpty()
        val media = attachmentKind(attaches)
        val outgoing = last?.sender != null && me != null && last.sender == me
        // Отметка собеседника — и из карточки чата, и из пушей прочтения: пуш карточку не меняет.
        val peerRead = ReadMarks.peer(chat, state)
        val lastMessage = if (last != null && (outgoing || last.sender != null || media != null)) {
            var delivery = if (outgoing) DeliveryState.SENT else null
            // Собеседник прочитал всё до своей отметки: отправленное не позже неё прочитано. Сравнивается
            // время самого сообщения: время последнего события чата двигают и правки, и реакции.
            if (delivery == DeliveryState.SENT && peerRead > 0 && peerRead >= last.time) delivery = DeliveryState.READ
            ChatLastMessage(
                authorId = last.sender?.toString(),
                authorName = last.sender?.let(state::displayName),
                isOutgoing = outgoing,
                delivery = delivery,
                media = media,
                thumbnailUrl = attachmentThumb(attaches),
                isForwarded = forwarded != null,
            )
        } else {
            null
        }
        val options = chat.raw["options"] as? Map<*, *>
        val peerOptions = peer?.options.orEmpty()
        val presence = peerId?.let { state.presence[it] }
        return Chat(
            id = chat.id.toString(),
            title = title,
            type = ChatType.fromCore(chat.type),
            lastMessageId = last?.id?.toString(),
            unreadCount = chat.newMessages,
            updatedAtMs = updated,
            preview = (last?.text?.takeIf { it.isNotEmpty() } ?: forwarded?.get("text") as? String)?.takeIf { it.isNotEmpty() },
            lastMessage = lastMessage,
            avatarUrl = avatar,
            pinOrder = pinOrder,
            isMuted = mutes?.isMuted(chat.id, config, nowMs) ?: (config?.chatMuteState(chat.id, nowMs) ?: false),
            isBot = "BOT" in peerOptions,
            hasWebApp = chat.hasWebApp,
            isVerified = "OFFICIAL" in peerOptions || options?.get("OFFICIAL") == true,
            isOnline = PresenceTime.isOnline(presence),
            commentsEnabled = when (options?.get("COMMENTS")) {
                true -> true
                false -> false
                else -> null
            },
            canWrite = canWrite(chat, state),
            peerId = peerId?.toString(),
        )
    }

    fun folders(folders: ChatFolders?): List<ServerFolder> {
        folders ?: return emptyList()
        val all = folders.allChats?.id
        return folders.folders.map { f ->
            ServerFolder(
                id = f.id,
                title = f.title,
                chatIds = f.include.map { it.toString() },
                filters = f.filters.mapNotNull { v ->
                    when (v) {
                        null -> null
                        is Number -> v.toLong().toString()
                        else -> v.toString()
                    }
                },
                isAllChats = f.id == all,
            )
        }
    }

    /** Собеседник `DIALOG` (ключи `participants`, кроме себя). Диалог с собой — «Избранное». */
    fun dialogPeer(chat: CoreChat, me: Long?): Long? {
        if (chat.type != "DIALOG") return null
        val ids = (chat.raw["participants"] as? Map<*, *>).orEmpty().keys.mapNotNull(::longOf)
        return ids.firstOrNull { it != me }
    }

    /** Свежая отметка прочтения других участников (мс). У каналов её нет. */
    fun peerReadMark(chat: CoreChat, me: Long?): Long {
        if (chat.type == "CHANNEL") return 0L
        val participants = chat.raw["participants"] as? Map<*, *> ?: return 0L
        var newest = 0L
        for ((key, value) in participants) {
            val id = longOf(key) ?: continue
            if (id == me) continue
            val mark = longOf(value) ?: continue
            if (mark > newest) newest = mark
        }
        return newest
    }

    /**
     * Можно ли писать в чат: не в покинутый (`status` не `ACTIVE`), в канал только владельцу или
     * админу, и не в диалог со служебным аккаунтом (`OFFICIAL` без `BOT`).
     */
    fun canWrite(chat: CoreChat, state: MaxState): Boolean {
        val status = chat.raw["status"] as? String
        if (!status.isNullOrEmpty() && status != "ACTIVE") return false
        val me = state.me
        if (chat.type == "CHANNEL") {
            if (me == null) return false
            if (longOf(chat.raw["owner"]) == me) return true
            val admins = (chat.raw["admins"] as? List<*>).orEmpty().mapNotNull(::longOf) +
                (chat.raw["adminParticipants"] as? Map<*, *>).orEmpty().keys.mapNotNull(::longOf)
            return me in admins
        }
        val peer = dialogPeer(chat, me)?.let { state.users[it] } ?: return true
        return !("OFFICIAL" in peer.options && "BOT" !in peer.options)
    }

    /** Пересланное сообщение ссылки `FORWARD` или `null`. */
    fun forwardedOf(message: MaxMessage?): Map<*, *>? {
        val link = message?.link ?: return null
        if ((link["type"] as? String)?.uppercase() != "FORWARD") return null
        return link["message"] as? Map<*, *>
    }

    /** Первое вложение так, как его называет список чатов. `null`, если его нет или тип незнаком. */
    fun attachmentKind(attaches: List<*>): MessageMediaKind? {
        val attach = attaches.firstOrNull() as? Map<*, *> ?: return null
        return when ((attach["_type"] as? String)?.uppercase()) {
            "PHOTO" -> if (attach["gif"] == true) MessageMediaKind.GIF else MessageMediaKind.PHOTO
            "VIDEO" -> if ((attach["videoType"] as? Number)?.toInt() == 1) MessageMediaKind.VIDEO_MESSAGE else MessageMediaKind.VIDEO
            "AUDIO" -> MessageMediaKind.VOICE
            "FILE" -> MessageMediaKind.FILE
            "STICKER" -> MessageMediaKind.STICKER
            "CONTACT" -> MessageMediaKind.CONTACT
            "LOCATION" -> MessageMediaKind.LOCATION
            "POLL" -> MessageMediaKind.POLL
            // Групповой звонок несёт ссылку для входа.
            "CALL" -> if ((attach["joinLink"] as? String).isNullOrBlank()) MessageMediaKind.CALL else MessageMediaKind.GROUP_CALL
            else -> null
        }
    }

    fun attachmentThumb(attaches: List<*>): String? {
        val attach = attaches.firstOrNull() as? Map<*, *> ?: return null
        val url = when ((attach["_type"] as? String)?.uppercase()) {
            "PHOTO" -> attach["baseUrl"] as? String
            "VIDEO" -> attach["thumbnail"] as? String
            else -> null
        }
        return url?.takeIf { it.isNotBlank() }
    }

    fun longOf(value: Any?): Long? = when (value) {
        is Number -> value.toLong()
        is String -> value.toLongOrNull()
        else -> null
    }
}
