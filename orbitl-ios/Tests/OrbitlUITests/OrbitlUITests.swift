import Testing
@testable import OrbitlUI

@Suite("Аватар")
struct AvatarInitialsTests {
    @Test("Буквы двух слов, одно слово и пустая строка")
    func initials() {
        #expect(AvatarInitials.text(for: "Ann Lee") == "AL")
        #expect(AvatarInitials.text(for: "ann") == "A")
        #expect(AvatarInitials.text(for: "") == "")
    }
}
