import Foundation

/// Вид полосы папок на этом устройстве: вкладку «Все» можно скрыть. Сервер такого не хранит.
@MainActor
public protocol FolderDisplayStore: AnyObject {
    var hidesAllChats: Bool { get set }
}

/// Настройка только в памяти: для тестов и превью.
@MainActor
public final class InMemoryFolderDisplayStore: FolderDisplayStore {
    public var hidesAllChats: Bool

    public init(hidesAllChats: Bool = false) {
        self.hidesAllChats = hidesAllChats
    }
}
