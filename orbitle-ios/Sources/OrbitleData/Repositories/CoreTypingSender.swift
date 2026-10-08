import Foundation
import OrbitleDomain

/// «Я печатаю» через ядро (`MSG_TYPING` 65). Когда и что слать, решает `TypingSendPolicy`;
/// здесь только кадр.
public struct CoreTypingSender: TypingSender {
    private let core: any MaxCore

    public init(core: any MaxCore) {
        self.core = core
    }

    public func sendTyping(chatId: String, type: String, postId: String?) async throws {
        core.sendTyping(chatId: chatId, type: type, postId: postId ?? "")
    }
}
