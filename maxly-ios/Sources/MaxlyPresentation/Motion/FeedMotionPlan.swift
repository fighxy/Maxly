import Foundation

/// Как лента на `UICollectionView` показывает новый снимок (docs/animations.md, правила 3, 4 и 6).
public enum FeedMotion: Equatable, Sendable {
    /// Сразу, без движения: открытие, история, догонка, команда прокрутки, палец на ленте.
    case instant
    /// Новые сообщения снизу въезжают, лента едет к ним.
    case appear
    /// Удалённые сообщения на экране сжимаются и растворяются, промежуток схлопывается.
    case disappear
    /// Пузырь на экране у низа вырос или сжался: соседи сдвигаются плавно.
    case resize
}

/// Выбор движения ленты по тому, что поменялось и где она стоит. Без UIKit, чтобы его
/// проверяли тесты.
public enum FeedMotionPlan {
    public struct Input: Equatable, Sendable {
        /// Живое изменение: не открытие чата и не восстановление истории.
        public var live: Bool
        /// Лента уже стоит на своём месте с настоящим размером.
        public var settled: Bool
        /// Палец на ленте или она катится по инерции.
        public var interacting: Bool
        /// Команда прокрутки (кнопка «вниз», переход к цитате): лента встаёт сразу.
        public var commanded: Bool
        /// Изменение состава строк сообщений.
        public var change: CollectionChange
        /// Лента держится низом (`FeedFollow.bottom`).
        public var followsBottom: Bool
        /// Последнее сообщение было у нижнего края до изменения.
        public var atBottom: Bool
        /// До низа меньше полутора экранов: въезд к новому ещё короткий.
        public var nearBottom: Bool
        /// Все удалённые строки были на экране.
        public var removedVisible: Bool
        /// Высота сменилась у строки на экране.
        public var resizedVisible: Bool

        public init(
            live: Bool,
            settled: Bool,
            interacting: Bool,
            commanded: Bool,
            change: CollectionChange,
            followsBottom: Bool,
            atBottom: Bool,
            nearBottom: Bool,
            removedVisible: Bool,
            resizedVisible: Bool
        ) {
            self.live = live
            self.settled = settled
            self.interacting = interacting
            self.commanded = commanded
            self.change = change
            self.followsBottom = followsBottom
            self.atBottom = atBottom
            self.nearBottom = nearBottom
            self.removedVisible = removedVisible
            self.resizedVisible = resizedVisible
        }
    }

    public static func motion(_ input: Input) -> FeedMotion {
        guard input.live, input.settled, !input.interacting, !input.commanded else { return .instant }
        switch input.change {
        case .appended(let count):
            // Новое у низа: лента едет к нему. Кто читает историю далеко вверху, остаётся на месте.
            let reachable = input.followsBottom && (input.atBottom || input.nearBottom)
            return count <= CollectionChange.animationLimit && reachable ? .appear : .instant
        case .removed(let count):
            // Удаление вне экрана анимировать нечего, а сдвиг под ним сломал бы место чтения.
            return count <= CollectionChange.animationLimit && input.removedVisible ? .disappear : .instant
        case .none:
            return input.resizedVisible && input.atBottom ? .resize : .instant
        case .initial, .prepended, .trimmed, .updated, .reload:
            return .instant
        }
    }
}
