import Foundation

/// Отметки прочтения: своя и собеседников. Отметка — серверное время (мс): всё, что
/// отправлено не позже неё, прочитано. Поэтому она сравнивается со временем сообщения,
/// а не со временем последнего события чата (его двигают и правки, и реакции).
enum ReadMarks {
    /// Время, с которым сравниваются отметки строки: последнего сообщения, а если оно
    /// неизвестно (`0`), — последнего события чата, как раньше.
    static func readTime(lastMessageAt: Int64, updatedAt: Date) -> Int64 {
        lastMessageAt > 0 ? lastMessageAt : updatedAt.unixMillis
    }

    /// Собеседник прочитал сообщение, отправленное в `messageTime`.
    static func isReadByPeer(peerMark: Int64, messageTime: Int64) -> Bool {
        peerMark > 0 && peerMark >= messageTime
    }

    /// Ответ на свою отметку `mark` не старее уже применённой (`known`). Ответы на две
    /// отметки подряд могут прийти в обратном порядке: запоздавший ответ на старую не должен
    /// откатывать новую и возвращать счётчик непрочитанных.
    static func isFresh(_ mark: Int64, known: Int64) -> Bool {
        mark > 0 && mark >= known
    }

    /// Сколько непрочитанных оставить после ответа сервера на отметку. Ответ точнее
    /// локального счётчика, только если с запроса в чат ничего не пришло (последнее сообщение
    /// то же, `lastBefore`) и он меньше. `nil` — оставить как есть.
    static func unreadAfterRead(local: Int, lastNow: String?, lastBefore: String?, server: Int) -> Int? {
        guard server >= 0, lastNow == lastBefore, server < local else { return nil }
        return server
    }
}
