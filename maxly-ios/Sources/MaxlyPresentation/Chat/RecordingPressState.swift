/// Tracks a physical touch independently from recorder state. Cancelling a recording
/// must not turn subsequent movements of the same finger into a new recording.
public struct RecordingPressState {
    public private(set) var generation = 0
    public private(set) var active = false
    public init() {}

    public mutating func begin() -> Bool {
        guard !active else { return false }
        generation &+= 1
        active = true
        return true
    }

    @discardableResult
    public mutating func end(generation: Int) -> Bool {
        guard active, self.generation == generation else { return false }
        active = false
        return true
    }
}
