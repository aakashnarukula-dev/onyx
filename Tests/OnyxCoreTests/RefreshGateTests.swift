import Testing
@testable import OnyxCore

struct RefreshGateTests {
    @Test func onlyLatestResultIsAccepted() {
        var gate = RefreshGate()
        let first = gate.begin()
        let second = gate.begin()
        let staleAccepted = gate.accept(first)   // A's slow job lands after B started
        let newAccepted = gate.accept(second)
        let again = gate.accept(second)          // each result applies once
        #expect(!staleAccepted)
        #expect(newAccepted)
        #expect(!again)
    }

    @Test func pendingWhileRefreshing() {
        var gate = RefreshGate()
        #expect(!gate.isRefreshing)
        let t = gate.begin()
        #expect(gate.isRefreshing)
        _ = gate.accept(t)
        #expect(!gate.isRefreshing)
    }
}
