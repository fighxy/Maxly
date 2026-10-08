import Foundation
import OrbitleData
import OrbitleDomain
import MaxIos

/// Истории через `MaxIosClient` (схема Komet `feature/FullStack`, docs/protocol.md ядра).
extension MaxIosCore {
    func loadStoriesFeed() async throws -> [StoryRing] {
        try await call("loadStoriesFeed") { done in
            self.client.loadStoriesFeed { rings, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success(rings.map(Self.ring)))
                }
            }
        }
    }

    func loadOwnerStories(owner: StoryOwner) async throws -> OwnerStories {
        try await call("loadOwnerStories") { done in
            self.client.loadOwnerStories(ownerId: owner.id, type: Int32(owner.kind.rawValue)) { reply, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else if let reply {
                    done(.success(OwnerStories(ring: reply.preview.map(Self.ring), stories: reply.stories.map(Self.story))))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func markStorySeen(owner: StoryOwner, storyId: String) async throws {
        let _: Void = try await call("markStorySeen") { done in
            self.client.markStorySeen(ownerId: owner.id, type: Int32(owner.kind.rawValue), storyId: storyId) { kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success(()))
                }
            }
        }
    }

    func publishStory(path: String, isVideo: Bool, durationMs: Int64, audience: Int,
                      progress: @escaping @Sendable (Double) -> Void) async throws -> OwnerStories {
        let running = RunningTask()
        return try await withTaskCancellationHandler {
            try await call("publishStory") { done in
                let task = self.client.publishStory(
                    path: path,
                    kind: isVideo ? "video" : "photo",
                    durationMs: durationMs,
                    audience: Int32(audience),
                    onProgress: { step in
                        guard step.total > 0 else { return }
                        progress(min(1, max(0, Double(step.sent) / Double(step.total))))
                    },
                    onResult: { published, kind, key in
                        if let kind {
                            done(.failure(Self.failed(kind: kind, key: key)))
                        } else if let published {
                            done(.success(OwnerStories(ring: published.preview.map(Self.ring), stories: published.stories.map(Self.story))))
                        } else {
                            done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                        }
                    }
                )
                running.set(task)
            }
        } onCancel: {
            running.cancel()
        }
    }

    func deleteStories(ids: [String]) async throws {
        let _: Void = try await call("deleteStories") { done in
            self.client.deleteStories(storyIds: ids) { kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success(()))
                }
            }
        }
    }

    /// Пуши колец приходят событием `stories`: владелец в `chatId`, его тип в `chatType`,
    /// время кольца в `timeMs`, непросмотренные в `unread`, всего историй в `text`.
    func storyUpdates() -> AsyncStream<StoryRing> {
        AsyncStream { continuation in
            let watch = WatchBox(client.watchEvents { event in
                guard event.kind == "stories", !event.chatId.isEmpty else { return }
                let total = Int(event.text) ?? 0
                let unread = max(0, Int(event.unread))
                continuation.yield(StoryRing(
                    owner: StoryOwner(id: event.chatId, kind: StoryOwner.Kind(rawValue: Int(event.chatType) ?? 0) ?? .user),
                    name: "",
                    updatedAt: Date(unixMillis: event.timeMs),
                    total: total,
                    read: max(0, total - unread)
                ))
            })
            continuation.onTermination = { _ in watch.cancel() }
        }
    }

    private static func ring(_ preview: IosStoryPreview) -> StoryRing {
        StoryRing(
            owner: StoryOwner(id: preview.ownerId, kind: StoryOwner.Kind(rawValue: Int(preview.ownerType)) ?? .user),
            name: preview.name,
            avatarURL: webURL(preview.avatarUrl),
            updatedAt: Date(unixMillis: preview.updateTimeMs),
            total: Int(preview.totalCount),
            read: Int(preview.readCount),
            expiresAt: preview.expiresAtMs > 0 ? Date(unixMillis: preview.expiresAtMs) : nil
        )
    }

    private static func story(_ story: IosStory) -> Story {
        let media: StoryMedia? = webURL(story.url).flatMap { url in
            guard story.mediaKind == "photo" || story.mediaKind == "video" else { return nil }
            return StoryMedia(
                isVideo: story.mediaKind == "video",
                url: url,
                thumbnailURL: webURL(story.thumbnailUrl),
                width: story.width > 0 ? Int(story.width) : nil,
                height: story.height > 0 ? Int(story.height) : nil,
                duration: story.durationMs > 0 ? Double(story.durationMs) / 1000 : nil
            )
        }
        return Story(
            id: story.id,
            owner: StoryOwner(id: story.ownerId, kind: StoryOwner.Kind(rawValue: Int(story.ownerType)) ?? .user),
            time: Date(unixMillis: story.timeMs),
            expiresAt: story.expiresAtMs > 0 ? Date(unixMillis: story.expiresAtMs) : nil,
            audience: story.audience == Int32(StoryAudience.contacts.rawValue) ? .contacts : .everyone,
            media: media
        )
    }
}
