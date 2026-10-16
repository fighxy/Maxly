import Foundation
import Testing
@testable import MaxlyData

/// Pingback и жалобы gifka.me.
@Suite("gifka.me: pingback")
struct GifkaPingbackTests {
    actor Recorder {
        var batches: [[GifkaEvent]] = []
        func add(_ events: [GifkaEvent]) { batches.append(events) }
    }

    @Test("Тело pingback: только mediaId и kind")
    func payload() throws {
        let body = try #require(GifkaClient.pingbackBody([
            GifkaEvent(mediaId: "oa9phkxg03cc", kind: .view),
            GifkaEvent(mediaId: "b", kind: .click),
            GifkaEvent(mediaId: "c", kind: .send),
            GifkaEvent(mediaId: "", kind: .send),
        ]))
        let root = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Array(root.keys) == ["events"])
        let events = try #require(root["events"] as? [[String: String]])
        #expect(events == [
            ["mediaId": "oa9phkxg03cc", "kind": "view"],
            ["mediaId": "b", "kind": "click"],
            ["mediaId": "c", "kind": "send"],
        ])
        #expect(GifkaClient.pingbackBody([]) == nil)
    }

    @Test("Запрос pingback: POST с ключом, без ключа не отправляется")
    func request() throws {
        let events = [GifkaEvent(mediaId: "a", kind: .view)]
        #expect(GifkaClient(apiKey: nil).pingbackRequest(events) == nil)
        #expect(GifkaPingback(client: GifkaClient(apiKey: nil)) == nil)
        let request = try #require(GifkaClient(apiKey: "k").pingbackRequest(events))
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.gifka.me/v1/pingback")
        #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "k")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(!(request.url?.absoluteString.contains("k=") ?? true))
    }

    @Test("Тело жалобы: причина и обрезанный комментарий")
    func reportBody() throws {
        let plain = try JSONSerialization.jsonObject(with: GifkaClient.reportBody(reason: .wrongDescription)) as? [String: String]
        #expect(plain == ["reason": "wrong_description"])
        let long = String(repeating: "я", count: 600)
        let full = try JSONSerialization.jsonObject(with: GifkaClient.reportBody(reason: .spam, details: "  \(long) ")) as? [String: String]
        #expect(full?["reason"] == "spam")
        #expect(full?["details"]?.count == 500)
    }

    @Test("Показы дедуплицируются и уходят одной пачкой")
    func batching() async throws {
        let recorder = Recorder()
        let pingback = GifkaPingback(delay: .seconds(60)) { await recorder.add($0) }
        await pingback.views(["a", "b"])
        await pingback.views(["b", "c", "a"])
        await pingback.click("a")
        await pingback.send("a")
        await pingback.flush()
        try await waitFor { await recorder.batches.count == 1 }
        let batch = await recorder.batches[0]
        #expect(batch.map(\.mediaId) == ["a", "b", "c", "a", "a"])
        #expect(batch.map(\.kind) == [.view, .view, .view, .click, .send])
        await pingback.views(["a"])
        await pingback.flush()
        try await Task.sleep(for: .milliseconds(50))
        #expect(await recorder.batches.count == 1)
    }

    @Test("Набрав maxBatch, очередь уходит сразу пачками не больше maxBatch")
    func maxBatch() async throws {
        let recorder = Recorder()
        let pingback = GifkaPingback(delay: .seconds(60), maxBatch: 3) { await recorder.add($0) }
        await pingback.views(["a", "b", "c", "d"])
        try await waitFor { await recorder.batches.count == 2 }
        let sizes = await recorder.batches.map(\.count).sorted()
        #expect(sizes == [1, 3])
    }

    @Test("Без flush пачка уходит по таймеру")
    func timer() async throws {
        let recorder = Recorder()
        let pingback = GifkaPingback(delay: .milliseconds(30)) { await recorder.add($0) }
        await pingback.click("x")
        try await waitFor { await recorder.batches.count == 1 }
        #expect(await recorder.batches[0] == [GifkaEvent(mediaId: "x", kind: .click)])
    }

    private func waitFor(_ condition: @Sendable () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("условие не выполнилось")
    }
}
