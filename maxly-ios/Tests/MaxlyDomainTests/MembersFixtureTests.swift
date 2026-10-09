import Foundation
import Testing
@testable import MaxlyDomain

/// Общие с Kotlin сценарии списка участников из `test-fixtures/members`.
@Suite("Участники: общие сценарии")
struct MembersFixtureTests {
    static let folder = SharedFixtureFolder(folder: "members")
    static let played = ["paging", "roles", "search"]

    @Test("Сценарий проигрывается", arguments: played)
    func play(_ name: String) throws {
        let fixture = try Self.folder.load(name)
        for (label, item) in try Self.folder.cases(fixture, file: name) {
            switch fixture["kind"] as? String {
            case "paging": try Self.paging(item, label)
            case "roles": try Self.roles(item, label)
            case "search": try Self.search(item, label)
            default: Issue.record("\(name): неизвестный kind \(String(describing: fixture["kind"]))")
            }
        }
    }

    @Test("Каждый файл сценария проигрывается")
    func everyFixtureIsPlayed() throws {
        try Self.folder.checkPlayed(Self.played)
    }

    static func members(_ value: Any?, _ label: String) throws -> [ChatMemberEntry] {
        try FixtureValue.objects(value, label).map { 
            ChatMemberEntry(id: FixtureValue.string($0["id"]) ?? "", name: $0["name"] as? String ?? "", mentionName: $0["mentionName"] as? String)
        }
    }

    static func paging(_ item: [String: Any], _ label: String) throws {
        let pages = try FixtureValue.objects(item["pages"], label)
        var requests: [Int64] = []
        var list: [ChatMemberEntry] = []
        var marker: Int64? = ChatMembersRules.firstMarker
        while let current = marker {
            guard requests.count < pages.count else {
                Issue.record("\(label): клиент спросил больше страниц, чем есть")
                break
            }
            requests.append(current)
            let page = pages[requests.count - 1]
            let appended = ChatMembersRules.append(try members(page["members"], label), to: list)
            list = appended.list
            let received = FixtureValue.isNull(page["marker"]) ? nil : try FixtureValue.long(page["marker"], label)
            marker = ChatMembersRules.nextMarker(requested: current, received: received, newMembers: appended.added)
        }
        let expect = try FixtureValue.object(item["expect"], label)
        let wantRequests = (expect["requests"] as? [Any] ?? []).compactMap { MessageReaders.number($0) }
        #expect(requests == wantRequests, "\(label): запросы \(requests)")
        #expect(list.map(\.id) == (expect["ids"] as? [String] ?? []), "\(label): \(list.map(\.id))")
    }

    static func roles(_ item: [String: Any], _ label: String) throws {
        let chat = try FixtureValue.object(item["chat"], label)
        var admins: [String: String?] = [:]
        for (key, value) in (chat["adminParticipants"] as? [String: Any]) ?? [:] {
            admins[key] = (value as? [String: Any])?["alias"] as? String
        }
        let arranged = ChatMembersRules.arrange(try members(item["members"], label), owner: FixtureValue.string(chat["owner"]), admins: admins)
        let want = try FixtureValue.objects(item["expect"], label)
        #expect(arranged.map(\.id) == want.map { FixtureValue.string($0["id"]) ?? "" }, "\(label): порядок \(arranged.map(\.id))")
        #expect(arranged.map(\.badge) == want.map { FixtureValue.string($0["badge"]) }, "\(label): значки \(arranged.map(\.badge))")
    }

    static func search(_ item: [String: Any], _ label: String) throws {
        let found = ChatMembersRules.filter(try members(item["members"], label), query: item["query"] as? String ?? "")
        #expect(found.map(\.id) == (item["expect"] as? [String] ?? []), "\(label): \(found.map(\.id))")
    }
}
