import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

@Suite("Папки прошлого входа на устройстве")
@MainActor
struct FolderDisplayStoreTests {
    @Test("Свои у каждого аккаунта, с правилами сервера")
    func perAccountRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "FolderDisplayStoreTests-\(UUID().uuidString)"))
        let mine = UserDefaultsFolderDisplayStore(defaults: defaults, account: "7")
        let other = UserDefaultsFolderDisplayStore(defaults: defaults, account: "8")
        #expect(mine.lastFolders == nil)
        let folders = [
            ChatFolder(id: "work", title: "Работа", filter: .chats(["1", "2"])),
            ChatFolder(id: "bots", title: "Боты", filter: .rules(ChatFolderRules(chatIds: ["3"], filters: ["BOT", "0"]))),
        ]
        mine.lastFolders = folders
        #expect(UserDefaultsFolderDisplayStore(defaults: defaults, account: "7").lastFolders == folders)
        #expect(other.lastFolders == nil)
        mine.lastFolders = nil
        #expect(mine.lastFolders == nil)
    }

    @Test("Без аккаунта папки не запоминаются")
    func noAccount() throws {
        let defaults = try #require(UserDefaults(suiteName: "FolderDisplayStoreTests-\(UUID().uuidString)"))
        let store = UserDefaultsFolderDisplayStore(defaults: defaults)
        store.lastFolders = [ChatFolder.all]
        #expect(store.lastFolders == nil)
    }
}
