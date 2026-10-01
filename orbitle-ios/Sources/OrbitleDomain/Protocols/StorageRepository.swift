import Foundation

/// Кэш на устройстве: сколько занято, очистка по категориям и правила хранения.
public protocol StorageRepository: Sendable {
    /// Размеры по категориям, база и свободное место. Считается обходом папок.
    func usage() async -> StorageUsage
    /// Стереть кэш выбранных категорий. Сообщения и база не трогаются: медиа снова
    /// скачаются, когда понадобятся.
    func clear(_ categories: Set<StorageCategory>) async
    func policy() async -> StoragePolicy
    /// Сохранить правила и сразу применить их.
    func setPolicy(_ policy: StoragePolicy) async
    /// Применить правила: удалить давно не открытое и самое старое сверх предела.
    func trim() async
}
