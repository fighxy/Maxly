import Foundation
import Testing
@testable import OrbitleDomain

/// Общие с Kotlin константы из `test-fixtures/client-rules/constants.json`: правила отметки
/// прочтения на iOS (`ReadMarkRules`) те же, что в файле.
@Suite("Правила клиентов: общие константы")
struct ClientRulesFixtureTests {
    static let folder = SharedFixtureFolder(folder: "client-rules")

    @Test("readMarks: ровно debounceMs и minVisibleFraction, и они равны ReadMarkRules")
    func readMarks() throws {
        let fixture = try Self.folder.load("constants")
        let rules = try FixtureValue.object(fixture["readMarks"], "constants/readMarks")
        #expect(Set(rules.keys) == ["debounceMs", "minVisibleFraction"], "ключи: \(rules.keys.sorted())")

        let debounce = try FixtureValue.long(rules["debounceMs"], "constants/readMarks/debounceMs")
        #expect(ReadMarkRules.delay == .milliseconds(debounce))
        #expect(debounce == 200)

        let fraction = try #require((rules["minVisibleFraction"] as? NSNumber)?.doubleValue, "minVisibleFraction — не число")
        #expect(ReadMarkRules.minVisibleFraction == fraction)
        #expect(fraction == 0.3)
    }
}
