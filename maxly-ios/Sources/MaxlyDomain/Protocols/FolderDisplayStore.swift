import Foundation

/// Вид полосы папок на этом устройстве: вкладку «Все» можно скрыть. Сервер такого не хранит.
///
/// Здесь же последние папки с сервера: ядро держит их только в памяти и узнаёт после входа,
/// а без них полоса папок при запуске появлялась бы через секунду и сдвигала список.
@MainActor
public protocol FolderDisplayStore: AnyObject {
    var hidesAllChats: Bool { get set }
    /// Папки сервера с прошлого входа (без «Все»); `nil` — ещё не было.
    var lastFolders: [ChatFolder]? { get set }
}

/// Настройка только в памяти: для тестов и превью.
@MainActor
public final class InMemoryFolderDisplayStore: FolderDisplayStore {
    public var hidesAllChats: Bool
    public var lastFolders: [ChatFolder]?

    public init(hidesAllChats: Bool = false, lastFolders: [ChatFolder]? = nil) {
        self.hidesAllChats = hidesAllChats
        self.lastFolders = lastFolders
    }
}
