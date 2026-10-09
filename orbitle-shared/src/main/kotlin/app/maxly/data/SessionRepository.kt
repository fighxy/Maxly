package app.maxly.data

import com.max.core.api.SessionInfo
import com.max.shared.MaxClient

/** Сеанс аккаунта на одном устройстве. */
data class DeviceSession(
    val id: String,
    val title: String,
    val subtitle: String,
    val isCurrent: Boolean,
    /** Последняя активность (мс), 0 — неизвестно. */
    val lastActiveMs: Long,
)

/** «Устройства»: активные сеансы и завершение всех, кроме текущего. */
interface SessionRepository {
    suspend fun sessions(): List<DeviceSession>
    suspend fun closeOthers()
    /** Подтвердить вход на другом устройстве по ссылке из его QR-кода. */
    suspend fun approveQrLogin(link: String): Unit = throw app.maxly.domain.MaxlyError.Rejected("Вход по QR-коду недоступен")
}

class CoreSessionRepository(private val client: MaxClient) : SessionRepository {
    override suspend fun sessions(): List<DeviceSession> =
        MaxCoreGateway.call { client.loadSessions() }.mapIndexed { index, info -> session(info, index) }
            .sortedWith(compareByDescending<DeviceSession> { it.isCurrent }.thenByDescending { it.lastActiveMs })

    override suspend fun closeOthers() {
        MaxCoreGateway.call { client.closeOtherSessions() }
    }

    override suspend fun approveQrLogin(link: String) {
        MaxCoreGateway.call { client.approveQrLogin(link) }
    }

    companion object {
        /** Название — устройство или клиент, вторая строка — платформа, версия и место. */
        fun session(info: SessionInfo, index: Int): DeviceSession {
            val raw = info.raw
            val client = (raw["client"] as? String)?.trim().orEmpty()
            val device = info.deviceName?.trim().orEmpty()
            val title = device.ifEmpty { client }.ifEmpty { info.platform?.trim().orEmpty() }.ifEmpty { "Неизвестное устройство" }
            val details = listOfNotNull(
                client.takeIf { it.isNotEmpty() && it != title },
                info.platform?.trim()?.takeIf { it.isNotEmpty() && it != title },
                info.appVersion?.trim()?.takeIf { it.isNotEmpty() },
                (raw["info"] as? String)?.trim()?.takeIf { it.isNotEmpty() },
                info.location?.trim()?.takeIf { it.isNotEmpty() },
            ).distinct()
            val last = listOfNotNull(info.lastActivity, ChatMapping.longOf(raw["time"]), info.updated).firstOrNull { it > 0 } ?: 0L
            return DeviceSession(
                id = info.id ?: info.deviceId ?: "session-$index",
                title = title,
                subtitle = details.joinToString(" · "),
                isCurrent = info.current,
                lastActiveMs = if (last in 1 until 100_000_000_000L) last * 1000 else last,
            )
        }
    }
}
