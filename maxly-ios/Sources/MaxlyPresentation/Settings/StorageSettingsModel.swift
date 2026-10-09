import Foundation
import Observation
import MaxlyDomain

/// Экран «Данные и память»: сколько места занимает
/// кэш по категориям, очистка выбранного, срок хранения медиа и предел размера кэша.
///
/// Кэш — копии медиа из облака Max. После очистки они снова скачаются, когда понадобятся;
/// сообщения и база не трогаются.
@MainActor
@Observable
public final class StorageSettingsModel {
    public private(set) var usage: StorageUsage?
    public private(set) var policy: StoragePolicy = .standard
    /// Отмеченные для очистки категории. По умолчанию отмечено всё.
    public private(set) var selection: Set<StorageCategory> = Set(StorageCategory.allCases)
    public private(set) var isClearing = false

    @ObservationIgnored private let storage: any StorageRepository
    @ObservationIgnored private let onCleared: @MainActor (Set<StorageCategory>) -> Void

    /// - Parameter onCleared: стёрты категории; приложение забывает их копии в памяти.
    public init(storage: any StorageRepository, onCleared: @escaping @MainActor (Set<StorageCategory>) -> Void = { _ in }) {
        self.storage = storage
        self.onCleared = onCleared
    }

    public func load() async {
        policy = await storage.policy()
        usage = await storage.usage()
    }

    /// Непустые категории, от большей к меньшей. Пустые не показываются.
    public var categories: [StorageCategory] {
        guard let usage else { return [] }
        return StorageCategory.allCases
            .filter { usage.bytes($0) > 0 }
            .sorted { usage.bytes($0) > usage.bytes($1) }
    }

    public var isEmpty: Bool { usage != nil && categories.isEmpty }

    public func bytes(_ category: StorageCategory) -> Int64 { usage?.bytes(category) ?? 0 }

    /// Доля категории в кэше, 0…1.
    public func share(_ category: StorageCategory) -> Double {
        guard let usage, usage.cache > 0 else { return 0 }
        return Double(usage.bytes(category)) / Double(usage.cache)
    }

    public func isSelected(_ category: StorageCategory) -> Bool { selection.contains(category) }

    public func toggle(_ category: StorageCategory) {
        if selection.contains(category) {
            selection.remove(category)
        } else {
            selection.insert(category)
        }
    }

    /// Что сотрёт «Очистить»: отмеченные и непустые.
    public var clearable: Set<StorageCategory> { selection.intersection(categories) }

    public var selectedBytes: Int64 { clearable.reduce(0) { $0 + bytes($1) } }

    public func clearSelected() async {
        await clear(clearable)
    }

    public func clear(_ categories: Set<StorageCategory>) async {
        guard !categories.isEmpty, !isClearing else { return }
        isClearing = true
        await storage.clear(categories)
        onCleared(categories)
        usage = await storage.usage()
        isClearing = false
    }

    public func setKeepMedia(_ period: KeepMediaPeriod) async {
        guard period != policy.keepMedia else { return }
        policy.keepMedia = period
        await apply()
    }

    public func setSizeLimit(_ limit: CacheSizeLimit) async {
        guard limit != policy.sizeLimit else { return }
        policy.sizeLimit = limit
        await apply()
    }

    private func apply() async {
        await storage.setPolicy(policy)
        usage = await storage.usage()
    }

    // MARK: Подписи

    /// «Maxly занимает 1,2 ГБ — 3 % памяти устройства».
    public var summary: String? {
        guard let usage else { return nil }
        var text = "Maxly занимает \(Self.format(usage.total))"
        if let total = usage.deviceTotal, total > 0 {
            let percent = Double(usage.total) / Double(total) * 100
            text += " — \(Self.percent(percent)) памяти устройства"
        }
        return text
    }

    /// «Свободно 23,4 ГБ».
    public var freeSpace: String? {
        usage?.deviceFree.map { "Свободно \(Self.format($0))" }
    }

    public static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Меньше процента — «<1 %», иначе целые проценты.
    public static func percent(_ value: Double) -> String {
        if value > 0, value < 1 { return "<1 %" }
        return "\(Int(value.rounded())) %"
    }
}

extension StorageCategory {
    public var title: String {
        switch self {
        case .photos: "Фото"
        case .videos: "Видео"
        case .videoNotes: "Видеосообщения"
        case .voice: "Голосовые сообщения"
        case .files: "Файлы"
        case .other: "Прочее"
        }
    }
}

extension KeepMediaPeriod {
    public var title: String {
        switch self {
        case .threeDays: "3 дня"
        case .week: "1 неделя"
        case .month: "1 месяц"
        case .forever: "Всегда"
        }
    }
}

extension CacheSizeLimit {
    public var title: String {
        switch self {
        case .gb1: "1 ГБ"
        case .gb5: "5 ГБ"
        case .gb20: "20 ГБ"
        case .unlimited: "Без ограничений"
        }
    }
}
