/// Keeps only the newest of overlapping background refreshes: a slow, older result that lands
/// after a newer refresh started is dropped.
public struct RefreshGate: Sendable {
    private var latest = 0
    private var applied = 0

    public init() {}

    public var isRefreshing: Bool { applied < latest }

    public mutating func begin() -> Int {
        latest += 1
        return latest
    }

    /// True exactly once, for the newest token.
    public mutating func accept(_ token: Int) -> Bool {
        guard token == latest, applied < token else { return false }
        applied = token
        return true
    }
}
