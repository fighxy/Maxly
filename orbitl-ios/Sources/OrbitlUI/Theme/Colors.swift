import SwiftUI

public extension Color {
    static let orbitlAccent = Color(red: 0.36, green: 0.42, blue: 0.96)
    static let orbitlOutgoing = Color(red: 0.36, green: 0.42, blue: 0.96)
    #if os(iOS)
    static let orbitlIncoming = Color(uiColor: .secondarySystemBackground)
    #else
    static let orbitlIncoming = Color(red: 0.93, green: 0.93, blue: 0.95)
    #endif
}
