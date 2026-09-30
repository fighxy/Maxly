import Foundation
import OrbitleDomain

/// Одно сообщение из набора вложений.
public struct AttachmentBatch: Hashable, Sendable {
    public var drafts: [AttachmentDraft]
    /// Подпись этого сообщения, пустая — без неё.
    public var caption: String

    public init(drafts: [AttachmentDraft], caption: String = "") {
        self.drafts = drafts
        self.caption = caption
    }
}

/// Как выбранное в листе вложений делится на сообщения (docs/attachments.md):
/// - подряд идущие фото — одно сообщение, до 10 штук;
/// - каждое видео, каждый файл и каждая карточка контакта — отдельное сообщение;
/// - порядок выбора сохраняется;
/// - подпись идёт с первым сообщением, у которого может быть текст (у контакта его нет).
///   Если в наборе одни контакты, подпись уходит обычным текстом (`trailingText`).
public enum AttachmentBatchPlanner {
    public static let photosPerMessage = 10

    public struct Plan: Hashable, Sendable {
        public var batches: [AttachmentBatch]
        /// Текст, который уходит отдельным сообщением после вложений.
        public var trailingText: String
    }

    public static func plan(_ drafts: [AttachmentDraft], caption: String) -> Plan {
        var batches: [AttachmentBatch] = []
        var photos: [AttachmentDraft] = []
        func flushPhotos() {
            guard !photos.isEmpty else { return }
            batches.append(AttachmentBatch(drafts: photos))
            photos = []
        }
        for draft in drafts {
            switch draft.kind {
            case .photo:
                photos.append(draft)
                if photos.count == photosPerMessage { flushPhotos() }
            case .video, .file, .contact:
                flushPhotos()
                batches.append(AttachmentBatch(drafts: [draft]))
            }
        }
        flushPhotos()

        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return Plan(batches: batches, trailingText: "") }
        if let index = batches.firstIndex(where: { !$0.drafts.contains { $0.kind == .contact } }) {
            batches[index].caption = text
            return Plan(batches: batches, trailingText: "")
        }
        return Plan(batches: batches, trailingText: text)
    }
}
