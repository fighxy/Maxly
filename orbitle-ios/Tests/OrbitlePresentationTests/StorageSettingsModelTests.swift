import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

private actor FakeStorage: StorageRepository {
    private(set) var bytes: [StorageCategory: Int64]
    private(set) var saved = StoragePolicy.standard
    private(set) var cleared: [Set<StorageCategory>] = []

    init(_ bytes: [StorageCategory: Int64]) { self.bytes = bytes }

    func usage() async -> StorageUsage {
        StorageUsage(categories: bytes, database: 1_000, deviceFree: 50_000, deviceTotal: 100_000)
    }

    func clear(_ categories: Set<StorageCategory>) async {
        cleared.append(categories)
        for category in categories { bytes[category] = 0 }
    }

    func policy() async -> StoragePolicy { saved }

    func setPolicy(_ policy: StoragePolicy) async { saved = policy }

    func trim() async {}
}

@MainActor
private final class Notified {
    var sets: [Set<StorageCategory>] = []
}

@Suite("Данные и память")
@MainActor
struct StorageSettingsModelTests {
    @Test("Непустые категории от большей к меньшей, доли в сумме дают единицу")
    func categories() async {
        let model = StorageSettingsModel(storage: FakeStorage([.photos: 300, .voice: 100, .files: 600, .videos: 0]))
        await model.load()
        #expect(model.categories == [.files, .photos, .voice])
        #expect(model.share(.files) == 0.6)
        #expect(abs(model.categories.map(model.share).reduce(0, +) - 1) < 0.0001)
        #expect(model.usage?.total == 2_000)
        #expect(model.isEmpty == false)
    }

    @Test("Очищается только отмеченное и непустое, приложение узнаёт что именно")
    func clearSelected() async {
        let storage = FakeStorage([.photos: 300, .voice: 100, .files: 600])
        let notified = Notified()
        let model = StorageSettingsModel(storage: storage) { notified.sets.append($0) }
        await model.load()
        model.toggle(.files)
        #expect(!model.isSelected(.files))
        #expect(model.selectedBytes == 400)

        await model.clearSelected()
        #expect(await storage.cleared == [[.photos, .voice]])
        #expect(notified.sets == [[.photos, .voice]])
        #expect(model.categories == [.files])
        #expect(model.isClearing == false)
    }

    @Test("Пустой кэш: категорий нет, очищать нечего")
    func empty() async {
        let storage = FakeStorage([:])
        let model = StorageSettingsModel(storage: storage)
        await model.load()
        #expect(model.isEmpty)
        await model.clearSelected()
        #expect(await storage.cleared.isEmpty)
    }

    @Test("Срок хранения и предел сохраняются")
    func policy() async {
        let storage = FakeStorage([.photos: 1])
        let model = StorageSettingsModel(storage: storage)
        await model.load()
        await model.setKeepMedia(.threeDays)
        await model.setSizeLimit(.unlimited)
        #expect(model.policy == StoragePolicy(keepMedia: .threeDays, sizeLimit: .unlimited))
        #expect(await storage.saved == StoragePolicy(keepMedia: .threeDays, sizeLimit: .unlimited))
    }

    @Test("Проценты: меньше одного — «<1 %»")
    func percent() {
        #expect(StorageSettingsModel.percent(0.3) == "<1 %")
        #expect(StorageSettingsModel.percent(0) == "0 %")
        #expect(StorageSettingsModel.percent(12.6) == "13 %")
    }
}
