import Foundation
import Testing
@testable import MaxlyDomain

/// Общие с Kotlin сценарии имён и номеров из `test-fixtures/names`.
@Suite("Имена и номера: общие сценарии")
struct NamesFixtureTests {
    static let folder = SharedFixtureFolder(folder: "names")
    static let played = ["phone-normalize", "address-book", "display-name"]

    @Test("Сценарий проигрывается", arguments: played)
    func play(_ name: String) throws {
        let fixture = try Self.folder.load(name)
        for (label, item) in try Self.folder.cases(fixture, file: name) {
            switch fixture["kind"] as? String {
            case "phone":
                let got = PhoneNormalizer.normalize(FixtureValue.string(item["raw"]))
                #expect(got == FixtureValue.string(item["expect"]), "\(label): \(String(describing: got))")
            case "address-book":
                let book = AddressBookNames(entries: try Self.entries(item["entries"], label))
                let want = (item["expect"] as? [String: String]) ?? [:]
                #expect(book.names == want, "\(label): \(book.names)")
            case "display-name":
                let user = try FixtureValue.object(item["user"], label)
                let enabled = item["addressBookEnabled"] as? Bool ?? false
                let book = AddressBookNames(entries: try Self.entries(item["addressBook"], label))
                let phone = FixtureValue.string(user["phone"])
                let names = try FixtureValue.objects(user["names"] ?? [[String: Any]](), label).map { entry in
                    DisplayName.Entry(name: entry["name"] as? String, firstName: entry["firstName"] as? String,
                                      lastName: entry["lastName"] as? String, type: entry["type"] as? String)
                }
                let got = DisplayName.resolve(addressBookName: enabled ? book.name(forPhone: phone) : nil, names: names, phone: phone)
                #expect(got == item["expect"] as? String, "\(label): «\(got)»")
            default:
                Issue.record("\(name): неизвестный kind \(String(describing: fixture["kind"]))")
            }
        }
    }

    @Test("Каждый файл сценария проигрывается")
    func everyFixtureIsPlayed() throws {
        try Self.folder.checkPlayed(Self.played)
    }

    static func entries(_ value: Any?, _ label: String) throws -> [AddressBookNames.Entry] {
        try FixtureValue.objects(value ?? [[String: Any]](), label).map { entry in
            AddressBookNames.Entry(name: entry["name"] as? String ?? "", phones: entry["phones"] as? [String] ?? [])
        }
    }
}
