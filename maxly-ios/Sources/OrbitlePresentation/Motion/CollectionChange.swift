import Foundation

/// Чем новый список отличается от прежнего. По этому экраны решают, анимировать ли
/// изменение: новое сообщение, удаление и перестановка — плавно; первая загрузка,
/// подгрузка истории и полная замена — сразу, без движения и прыжков.
public enum CollectionChange: Equatable, Sendable {
    /// Порядок и состав те же.
    case none
    /// Список был пуст: первая загрузка.
    case initial
    /// В начало добавлено `count` элементов, остальное на месте.
    case prepended(Int)
    /// В конец добавлено `count` элементов. Сверху при этом могли уйти старые:
    /// окно ленты держит последние N сообщений.
    case appended(Int)
    /// Убрано `count` элементов, новых нет, порядок остальных тот же.
    case removed(Int)
    /// Сверху ушли старые элементы, больше ничего не поменялось (окно ленты сузилось).
    case trimmed(Int)
    /// Остальное: вставка в середину, перестановка, удаление вместе с добавлением.
    /// `count` — сколько элементов добавлено, убрано или сдвинуто.
    case updated(Int)
    /// Общих элементов нет или почти нет: другой чат, другая папка, полная пересборка.
    case reload

    /// Больше стольких изменений за раз не анимируются: стена движущихся строк хуже,
    /// чем мгновенная смена.
    public static let animationLimit = 10

    public static func between(_ old: [String], _ new: [String]) -> CollectionChange {
        if old == new { return .none }
        if old.isEmpty { return .initial }
        let oldSet = Set(old)
        let newSet = Set(new)
        let keptOld = old.filter(newSet.contains)
        if keptOld.isEmpty {
            // Удалили последние сообщения чата — это удаление, а не смена списка.
            return new.isEmpty && old.count <= animationLimit ? .removed(old.count) : .reload
        }
        let keptNew = new.filter(oldSet.contains)
        let added = new.count - keptNew.count
        let removedCount = old.count - keptOld.count
        guard keptOld == keptNew else {
            return .updated(added + removedCount + moves(from: keptOld, to: keptNew))
        }
        // Ушедшие элементы — только верх прежнего списка.
        let removedIsHead = removedCount == 0 || Array(old.suffix(keptOld.count)) == keptOld
        if added == 0 {
            return removedIsHead ? .trimmed(removedCount) : .removed(removedCount)
        }
        if removedCount == 0, Array(new.suffix(keptNew.count)) == keptNew {
            return .prepended(added)
        }
        if removedIsHead, Array(new.prefix(keptNew.count)) == keptNew {
            return removedCount > 0 && removedCount + added > animationLimit ? .reload : .appended(added)
        }
        return .updated(added + removedCount)
    }

    /// Сколько элементов сдвинулось: общие элементы минус самая длинная цепочка,
    /// сохранившая прежний порядок.
    private static func moves(from old: [String], to new: [String]) -> Int {
        // Повтор id не должен ронять приложение: берётся первое вхождение.
        let position = Dictionary(old.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        // Самая длинная возрастающая подпоследовательность позиций — O(n log n).
        var tails: [Int] = []
        for id in new {
            guard let value = position[id] else { continue }
            var low = 0
            var high = tails.count
            while low < high {
                let mid = (low + high) / 2
                if tails[mid] < value { low = mid + 1 } else { high = mid }
            }
            if low == tails.count { tails.append(value) } else { tails[low] = value }
        }
        return new.count - tails.count
    }

    /// Лента сообщений: плавно — новые снизу, удаления и правки порядка. Подгрузка
    /// старых страниц сверху, первая загрузка и смена окна — без анимации, чтобы лента
    /// не дёргалась.
    public var animatesTranscript: Bool {
        switch self {
        case .appended(let count), .removed(let count), .updated(let count):
            return count <= Self.animationLimit
        case .none, .initial, .prepended, .trimmed, .reload:
            return false
        }
    }

    /// Список чатов: плавно — новый чат сверху, подъём чата с новым сообщением, удаление.
    /// Подгрузка следующей страницы снизу, первая загрузка и смена папки — сразу.
    public var animatesList: Bool {
        switch self {
        case .prepended(let count), .removed(let count), .updated(let count), .trimmed(let count):
            return count <= Self.animationLimit
        case .none, .initial, .appended, .reload:
            return false
        }
    }
}
