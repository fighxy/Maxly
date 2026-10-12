import Foundation

/// One owner for explicit scroll commands. Geometry, not a timer or estimated contentSize,
/// decides whether a target has been reached. A replaced/cancelled command cannot finish.
public struct TranscriptScrollController: Equatable, Sendable {
    public struct Request: Equatable, Sendable {
        public let token: Int
        public let id: String
        public let anchor: Double
        public let latest: Bool
    }
    public private(set) var request: Request?
    private var generation = 0
    public init() {}

    public mutating func start(id: String, anchor: Double, latest: Bool) {
        generation += 1
        request = Request(token: generation, id: id, anchor: anchor, latest: latest)
    }
    public mutating func cancel() { request = nil }
    @discardableResult public mutating func finish(_ token: Int) -> Bool {
        guard request?.token == token else { return false }
        request = nil
        return true
    }

    /// Both rectangles must be measured in the same coordinate space.
    public static func reached(anchor: Double, rowMin: Double, rowMax: Double, viewportMin: Double, viewportMax: Double) -> Bool {
        guard [anchor, rowMin, rowMax, viewportMin, viewportMax].allSatisfy({ $0.isFinite }),
              rowMax > rowMin, viewportMax > viewportMin,
              rowMax > viewportMin, rowMin < viewportMax else { return false }
        let rowPoint = rowMin + (rowMax - rowMin) * anchor
        let viewportPoint = viewportMin + (viewportMax - viewportMin) * anchor
        return abs(rowPoint - viewportPoint) <= 24
    }
}
