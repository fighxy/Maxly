package app.orbitle.presentation.settings

import app.orbitle.domain.AccountLimits
import app.orbitle.presentation.common.PresenceText
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Что рисует экран ограничений: заголовок, пояснение и список ограничений. */
data class AccountLimitsContent(
    val entry: AccountLimits.Entry,
    val title: String,
    val message: String,
    val items: List<Item>,
) {
    data class Item(val icon: Icon, val title: String, val detail: String)

    /** Значок пункта: экран сам выбирает картинку своей платформы. */
    enum class Icon { PASSWORD, SESSIONS, MESSAGES, GROUPS, OTHER }
}

/** Строка «Аккаунт временно ограничен» в настройках, пока ограничения входа действуют. */
data class AccountLimitsRow(val title: String, val subtitle: String)

/** Тексты экрана ограничений. Часы и пояс передаются снаружи, чтобы тесты не зависели от запуска. */
class AccountLimitsText(private val zone: ZoneId = ZoneId.systemDefault()) {

    fun content(limits: AccountLimits, nowMs: Long): AccountLimitsContent = when (limits.entry) {
        AccountLimits.Entry.LOGIN -> AccountLimitsContent(
            entry = limits.entry,
            title = LOGIN_TITLE,
            message = "Вы вошли в Max на этом устройстве. Пока сеанс новый, сервер ограничивает часть настроек безопасности. " +
                liftsSentence(limits, nowMs),
            items = listOf(
                AccountLimitsContent.Item(
                    AccountLimitsContent.Icon.PASSWORD,
                    "Пароль для входа",
                    "Нельзя включить, сменить или отключить пароль.",
                ),
                AccountLimitsContent.Item(
                    AccountLimitsContent.Icon.SESSIONS,
                    "Другие сеансы",
                    "Нельзя завершить сеансы на других устройствах. Это можно сделать с устройства, где вход выполнен давно.",
                ),
            ),
        )
        AccountLimits.Entry.REGISTRATION -> AccountLimitsContent(
            entry = limits.entry,
            title = "Аккаунт может быть ограничен",
            message = "Новым аккаунтам сервер иногда ограничивает часть действий. Ограничения выдают не всем, и сервер снимает их сам.",
            items = listOf(
                AccountLimitsContent.Item(
                    AccountLimitsContent.Icon.MESSAGES,
                    "Сообщения",
                    "Возможно, писать получится только тем, у кого вы уже есть в контактах.",
                ),
                AccountLimitsContent.Item(
                    AccountLimitsContent.Icon.GROUPS,
                    "Группы",
                    "Вступить в группу может не получиться.",
                ),
                AccountLimitsContent.Item(
                    AccountLimitsContent.Icon.OTHER,
                    "Другие действия",
                    "Полного списка сервер не сообщает. Если действие не сработало, попробуйте позже.",
                ),
            ),
        )
    }

    /** Строка в настройках. `null`, если ограничений входа нет или срок уже вышел. */
    fun row(limits: AccountLimits?, nowMs: Long): AccountLimitsRow? {
        if (limits == null || !limits.isActive(nowMs)) return null
        val liftsAt = limits.liftsAtMs ?: return null
        return AccountLimitsRow(LOGIN_TITLE, "Снимутся примерно ${moment(liftsAt, nowMs)}")
    }

    private fun liftsSentence(limits: AccountLimits, nowMs: Long): String {
        val liftsAt = limits.liftsAtMs ?: return ""
        return if (nowMs < liftsAt) "Ограничения снимутся примерно ${moment(liftsAt, nowMs)}." else "Ограничения уже должны были сняться."
    }

    /** «сегодня в 14:30», «завтра в 09:05», иначе «5 октября в 14:30». */
    fun moment(atMs: Long, nowMs: Long): String {
        val at = Instant.ofEpochMilli(atMs).atZone(zone)
        val today = Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate()
        val time = "%02d:%02d".format(at.hour, at.minute)
        return when (ChronoUnit.DAYS.between(today, at.toLocalDate())) {
            0L -> "сегодня в $time"
            1L -> "завтра в $time"
            else -> "${at.dayOfMonth} ${PresenceText.MONTHS_GENITIVE[at.monthValue - 1]} в $time"
        }
    }

    private companion object {
        const val LOGIN_TITLE = "Аккаунт временно ограничен"
    }
}
