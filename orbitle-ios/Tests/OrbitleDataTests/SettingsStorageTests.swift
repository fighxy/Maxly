import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

@Suite("Настройки оформления на устройстве")
struct AppearanceStoreTests {
    @Test("Без записи — по умолчанию, запись читается новым хранилищем")
    @MainActor
    func roundTrip() throws {
        let suite = "orbitle.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsAppearanceStore(defaults: defaults)
        #expect(store.load() == .standard)
        store.save(AppearancePreferences(textSize: .xxLarge, theme: .dark))
        #expect(defaults.string(forKey: UserDefaultsAppearanceStore.textSizeKey) == "xxLarge")
        #expect(defaults.string(forKey: UserDefaultsAppearanceStore.themeKey) == "dark")
        let again = UserDefaultsAppearanceStore(defaults: defaults)
        #expect(again.load() == AppearancePreferences(textSize: .xxLarge, theme: .dark))
    }

    @Test("Обои сохраняются именем; старая запись без обоев и незнакомое имя — без обоев")
    @MainActor
    func wallpaper() throws {
        let suite = "orbitle.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Запись до обоев: только размер и тема.
        defaults.set("small", forKey: UserDefaultsAppearanceStore.textSizeKey)
        defaults.set("dark", forKey: UserDefaultsAppearanceStore.themeKey)
        let store = UserDefaultsAppearanceStore(defaults: defaults)
        #expect(store.load() == AppearancePreferences(textSize: .small, theme: .dark, wallpaper: .plain))
        store.save(AppearancePreferences(textSize: .small, theme: .dark, wallpaper: .autumnAuto))
        #expect(defaults.string(forKey: UserDefaultsAppearanceStore.wallpaperKey) == "autumnAuto")
        #expect(UserDefaultsAppearanceStore(defaults: defaults).load().wallpaper == .autumnAuto)
        defaults.set("winter", forKey: UserDefaultsAppearanceStore.wallpaperKey)
        #expect(UserDefaultsAppearanceStore(defaults: defaults).load() == AppearancePreferences(textSize: .small, theme: .dark))
    }

    @Test("Незнакомые значения читаются как значения по умолчанию")
    @MainActor
    func unknownValues() throws {
        let suite = "orbitle.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("huge", forKey: UserDefaultsAppearanceStore.textSizeKey)
        defaults.set("sepia", forKey: UserDefaultsAppearanceStore.themeKey)
        #expect(UserDefaultsAppearanceStore(defaults: defaults).load() == .standard)
        defaults.set("small", forKey: UserDefaultsAppearanceStore.textSizeKey)
        #expect(UserDefaultsAppearanceStore(defaults: defaults).load() == AppearancePreferences(textSize: .small, theme: .system))
    }
}

@Suite("Приватный режим на устройстве")
struct PrivateModeStoreTests {
    @Test("Без записи — выключен, заглушки, кнопка видна; запись читается новым хранилищем")
    @MainActor
    func roundTrip() throws {
        let suite = "orbitle.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPrivateModeStore(defaults: defaults)
        #expect(store.load() == .standard)
        #expect(store.load().showsQuickToggle)
        store.save(PrivateModePreferences(isEnabled: true, style: .blur, showsQuickToggle: false))
        #expect(defaults.bool(forKey: UserDefaultsPrivateModeStore.enabledKey))
        #expect(defaults.string(forKey: UserDefaultsPrivateModeStore.styleKey) == "blur")
        let again = UserDefaultsPrivateModeStore(defaults: defaults)
        #expect(again.load() == PrivateModePreferences(isEnabled: true, style: .blur, showsQuickToggle: false))
    }

    @Test("Незнакомый вид читается как заглушки")
    @MainActor
    func unknownStyle() throws {
        let suite = "orbitle.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: UserDefaultsPrivateModeStore.enabledKey)
        defaults.set("pixelate", forKey: UserDefaultsPrivateModeStore.styleKey)
        #expect(UserDefaultsPrivateModeStore(defaults: defaults).load() == PrivateModePreferences(isEnabled: true))
    }
}

@Suite("Архив отчётов о сбоях")
struct CrashDumpStoreTests {
    private func makeStore(limit: Int = 20) -> CrashDumpStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("crashes-\(UUID().uuidString)", isDirectory: true)
        return CrashDumpStore(directory: directory, limit: limit)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_790_000_000 + seconds)
    }

    @Test("Пустой архив, сохранение, текст и порядок от свежего к старому")
    func saveAndList() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(store.list().isEmpty)
        let old = try #require(store.save("Сбой по сигналу 11\n0 Orbitle 0x1", date: date(0)))
        let new = try #require(store.save("Исключение Objective-C: NSRangeException: index 3\nstack", date: date(60)))
        #expect(store.list().map(\.id) == [new.id, old.id])
        #expect(store.list().first?.date == date(60))
        #expect(store.text(of: old) == "Сбой по сигналу 11\n0 Orbitle 0x1\n")
        #expect(old.id.hasPrefix("crash-") && old.id.hasSuffix(".txt"))
    }

    @Test("Тот же отчёт и его часть не сохраняются второй раз, пустой не сохраняется")
    func deduplicates() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let full = "Сбой 2026-09-29T16:00:00Z, Orbitle 0.1.0 (1)\nKotlin: IllegalStateException\n\nСбой по сигналу 6\n0 Orbitle 0x1"
        let first = try #require(store.save(full, date: date(0)))
        let again = try #require(store.save(full, date: date(30)))
        #expect(again.id == first.id)
        // Следующий запуск без «Продолжить»: отчёт сигнала уже обнулён, осталась часть.
        let part = try #require(store.save("Сбой 2026-09-29T16:00:00Z, Orbitle 0.1.0 (1)\nKotlin: IllegalStateException", date: date(90)))
        #expect(part.id == first.id)
        #expect(store.save("  \n ", date: date(120)) == nil)
        #expect(store.list().count == 1)
    }

    @Test("Хранятся только последние отчёты")
    func limit() throws {
        let store = makeStore(limit: 3)
        defer { try? FileManager.default.removeItem(at: store.directory) }
        for index in 0..<5 {
            store.save("Сбой по сигналу 11\nкадр \(index)", date: date(TimeInterval(index)))
        }
        let dumps = store.list()
        #expect(dumps.count == 3)
        #expect(dumps.map(\.date) == [date(4), date(3), date(2)])
    }

    @Test("Удаление одного отчёта и всех")
    func remove() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let a = try #require(store.save("a", date: date(0)))
        store.save("b", date: date(1))
        store.save("c", date: date(2))
        store.remove(a)
        #expect(store.list().count == 2)
        #expect(store.text(of: a) == nil)
        store.removeAll()
        #expect(store.list().isEmpty)
    }

    @Test("Краткая строка: без заголовка журнала, с именем сигнала, не длиннее 160")
    func summary() {
        #expect(CrashDumpStore.summary(of: "Сбой 2026-09-29T16:00:00Z, Orbitle 0.1.0 (1)\nИсключение Objective-C: NSGenericException: boom\nstack") == "Исключение Objective-C: NSGenericException: boom")
        #expect(CrashDumpStore.summary(of: "Сбой по сигналу 11\n0 Orbitle") == "Сбой по сигналу 11 (SIGSEGV)")
        #expect(CrashDumpStore.summary(of: "Сбой по сигналу 6") == "Сбой по сигналу 6 (SIGABRT)")
        #expect(CrashDumpStore.summary(of: "Сбой по сигналу 30") == "Сбой по сигналу 30")
        #expect(CrashDumpStore.summary(of: "\n\n  Kotlin: ошибка  \n") == "Kotlin: ошибка")
        let long = CrashDumpStore.summary(of: String(repeating: "x", count: 500))
        #expect(long.count == 160)
        #expect(long.hasSuffix("…"))
    }

    @Test("Имя файла хранит дату, хэш одинаковый для одинакового текста")
    func naming() {
        let stamp = CrashDumpStore.stamp(date(0))
        #expect(CrashDumpStore.date(fromName: "crash-\(stamp)-0123456789abcdef.txt") == date(0))
        #expect(CrashDumpStore.date(fromName: "last-crash.txt") == nil)
        #expect(CrashDumpStore.hash("отчёт") == CrashDumpStore.hash("отчёт"))
        #expect(CrashDumpStore.hash("отчёт") != CrashDumpStore.hash("отчёт 2"))
        #expect(CrashDumpStore.hash("").count == 16)
    }

    @Test("Отчёты попадают в ZIP журнала отдельной папкой")
    func inLogArchive() throws {
        let logs = FileManager.default.temporaryDirectory.appendingPathComponent("logs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: logs) }
        let dumps = CrashDumpStore(logsDirectory: logs)
        dumps.save("Сбой по сигналу 11", date: date(0))
        let store = FileLogStore(directory: logs)
        store.write(Log.Entry(date: date(0), level: .info, category: .app, message: "запуск"))
        let archive = try store.makeArchive(info: "Orbitle test")
        defer { try? FileManager.default.removeItem(at: archive) }
        let data = try Data(contentsOf: archive)
        #expect(data.range(of: Data("Crashes/crash-".utf8)) != nil)
        // Очистка журнала отчёты не трогает.
        store.clear()
        #expect(dumps.list().count == 1)
    }
}

@Suite("Отметка нового сеанса на устройстве")
struct AccountLimitsStoreTests {
    @Test("Без записи — отметки нет, запись читается новым хранилищем, пустая отметка стирает ключи")
    @MainActor
    func roundTrip() throws {
        let suite = "orbitle.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsAccountLimitsStore(defaults: defaults)
        #expect(store.load() == nil)
        let limits = AccountLimits(entry: .login, grantedAt: Date(timeIntervalSince1970: 1_790_000_000), isShown: true)
        store.save(limits)
        #expect(defaults.string(forKey: UserDefaultsAccountLimitsStore.entryKey) == "login")
        #expect(UserDefaultsAccountLimitsStore(defaults: defaults).load() == limits)
        store.save(nil)
        #expect(UserDefaultsAccountLimitsStore(defaults: defaults).load() == nil)
        #expect(defaults.object(forKey: UserDefaultsAccountLimitsStore.grantedAtKey) == nil)
    }

    @Test("Незнакомый способ входа или запись без времени — отметки нет")
    @MainActor
    func unknownValues() throws {
        let suite = "orbitle.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("guest", forKey: UserDefaultsAccountLimitsStore.entryKey)
        defaults.set(1_790_000_000.0, forKey: UserDefaultsAccountLimitsStore.grantedAtKey)
        #expect(UserDefaultsAccountLimitsStore(defaults: defaults).load() == nil)
        defaults.set("registration", forKey: UserDefaultsAccountLimitsStore.entryKey)
        defaults.removeObject(forKey: UserDefaultsAccountLimitsStore.grantedAtKey)
        #expect(UserDefaultsAccountLimitsStore(defaults: defaults).load() == nil)
    }
}
