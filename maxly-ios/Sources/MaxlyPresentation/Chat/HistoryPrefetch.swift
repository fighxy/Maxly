import Foundation

/// Когда подгружать старую историю до края ленты.
///
/// Android (`ChatFeed.PAGE_TRIGGER = 20`) спрашивает страницу за ~20 строк до верха.
/// На iOS раньше ждали появления шапки «Загрузить предыдущие» — на длинном скролле
/// страница приходила уже после остановки. Тот же порог: видна любая из первых
/// `trigger` строк или сама шапка.
public enum HistoryPrefetch: Sendable {
    public static let triggerRows = 20

    /// `visiblePrefix` — наименьший индекс строки ленты, у которой есть пересечение
    /// с viewport (`nil`, если ни одна строка ещё не измерена).
    public static func shouldLoadOlder(
        canLoadOlder: Bool,
        isLoadingOlder: Bool,
        isRestoringHistory: Bool,
        isOpening: Bool,
        headerVisible: Bool,
        visiblePrefix: Int?,
        trigger: Int = triggerRows
    ) -> Bool {
        guard canLoadOlder, !isLoadingOlder, !isRestoringHistory, !isOpening else { return false }
        if headerVisible { return true }
        guard let visiblePrefix else { return false }
        return visiblePrefix < max(1, trigger)
    }
}
