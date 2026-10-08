import Foundation
import OrbitleData
import OrbitleDomain
import MaxIos

/// Стикеры и анимодзи через `MaxIosClient` (docs/stickers.md).
extension MaxIosCore {
    func sendSticker(chatId: String, stickerId: String, replyTo: String) async throws -> CoreMessage {
        try await call("sendSticker") { done in
            self.client.sendSticker(chatId: chatId, stickerId: stickerId, replyTo: replyTo) { message, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else if let message {
                    done(.success(Self.message(message)))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func sendText(chatId: String, text: String, replyTo: String, animoji: [CoreAnimojiMark]) async throws -> CoreMessage {
        let marks = animoji.map {
            IosAnimojiMark(from: Int32($0.from), length: Int32($0.length), animojiId: $0.animojiId, lottieUrl: $0.lottieURL)
        }
        return try await call("sendText") { done in
            self.client.sendText(chatId: chatId, text: text, replyTo: replyTo, animoji: marks) { message, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else if let message {
                    done(.success(Self.message(message)))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func loadStickerCatalog() async throws -> StickerCatalog {
        try await call("loadStickerCatalog") { done in
            self.client.loadStickerCatalog { catalog, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else if let catalog {
                    done(.success(StickerCatalog(
                        sets: catalog.sets.map {
                            StickerSet(
                                id: $0.id,
                                name: $0.name,
                                iconURL: Self.webURL($0.iconUrl),
                                stickerIds: $0.stickerIds,
                                link: $0.link.isEmpty ? nil : $0.link,
                                isFavorite: $0.isFavorite
                            )
                        },
                        recentStickerIds: catalog.recentStickerIds
                    )))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func loadStickers(ids: [String]) async throws -> [Sticker] {
        try await call("loadStickers") { done in
            self.client.loadStickers(ids: ids) { list, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success(list.map {
                        Sticker(
                            id: $0.id,
                            url: Self.webURL($0.url),
                            lottieURL: Self.webURL($0.lottieUrl),
                            setId: $0.setId.isEmpty ? nil : $0.setId,
                            width: $0.width > 0 ? Int($0.width) : nil,
                            height: $0.height > 0 ? Int($0.height) : nil,
                            tags: $0.tags
                        )
                    }))
                }
            }
        }
    }

    func loadAnimatedEmoji() async throws -> [AnimatedEmoji] {
        try await call("loadAnimojis") { done in
            self.client.loadAnimojis { list, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success(list.map {
                        AnimatedEmoji(id: $0.id, emoji: $0.emoji, iconURL: Self.webURL($0.iconUrl), lottieURL: Self.webURL($0.lottieUrl))
                    }))
                }
            }
        }
    }

    /// Пустая строка и адрес без схемы — «нет адреса».
    static func webURL(_ text: String) -> URL? {
        guard !text.isEmpty, let url = URL(string: text), url.scheme != nil else { return nil }
        return url
    }
}
