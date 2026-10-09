import Foundation
import OrbitleData
import OrbitleDomain
import MaxlyCore

/// Фото, видео, файлы и карточки контактов через `MaxIosClient` (docs/attachments.md).
extension MaxIosCore {
    /// Один `sendMedia` ядра: загрузка всех файлов и одно сообщение. Отмена задачи Swift
    /// отменяет корутину ядра, ответ тогда приходит с `CANCELLED`.
    func sendMedia(chatId: String, items: [CoreOutgoingMedia], caption: String, replyTo: String,
                   progress: @escaping @Sendable (Double) -> Void) async throws -> CoreMessage {
        let media = items.map { IosOutgoingMedia(path: $0.path, kind: $0.kind, fileName: $0.fileName) }
        let running = RunningTask()
        return try await withTaskCancellationHandler {
            try await call("sendMedia") { done in
                let task = self.client.sendMedia(
                    chatId: chatId,
                    items: media,
                    caption: caption,
                    replyTo: replyTo,
                    onProgress: { step in
                        guard step.total > 0 else { return }
                        progress(min(1, max(0, Double(step.sent) / Double(step.total))))
                    },
                    onResult: { message, kind, key in
                        if let kind {
                            done(.failure(Self.failed(kind: kind, key: key)))
                        } else if let message {
                            done(.success(Self.message(message)))
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

    func sendRecording(chatId: String, path: String, kind: String, durationMs: Int64, wave: [Int], replyTo: String,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> CoreMessage {
        let running = RunningTask()
        let waveHex = wave.map { String(format: "%02x", min(255, max(0, $0))) }.joined()
        return try await withTaskCancellationHandler {
            try await call("sendRecording") { done in
                let onProgress: (IosUploadProgress) -> Void = { step in
                    guard step.total > 0 else { return }
                    progress(min(1, max(0, Double(step.sent) / Double(step.total))))
                }
                let onResult: (IosMessage?, String?, String?) -> Void = { message, kind, key in
                    if let kind {
                        done(.failure(Self.failed(kind: kind, key: key)))
                    } else if let message {
                        done(.success(Self.message(message)))
                    } else {
                        done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                    }
                }
                let task = kind == "voice"
                    ? self.client.sendVoice(chatId: chatId, path: path, durationMs: durationMs, waveHex: waveHex,
                                            replyTo: replyTo, onProgress: onProgress, onResult: onResult)
                    : self.client.sendVideoNote(chatId: chatId, path: path, durationMs: durationMs,
                                                replyTo: replyTo, onProgress: onProgress, onResult: onResult)
                running.set(task)
            }
        } onCancel: {
            running.cancel()
        }
    }

    func sendContact(chatId: String, contactId: String, replyTo: String) async throws -> CoreMessage {
        try await call("sendContact") { done in
            self.client.sendContact(chatId: chatId, contactId: contactId, replyTo: replyTo) { message, kind, key in
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
}

/// Задача ядра, которую может отменить `onCancel`: он бывает раньше, чем задача создана.
final class RunningTask: @unchecked Sendable {
    private let lock = NSLock()
    private var task: IosTask?
    private var cancelled = false

    func set(_ task: IosTask) {
        lock.lock()
        self.task = task
        let cancelNow = cancelled
        lock.unlock()
        if cancelNow { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }
}
