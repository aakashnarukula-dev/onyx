import CoreGraphics
import Testing
@testable import OnyxCore

struct GridLayoutTests {
    @Test func columns() {
        #expect(GridLayout.columns(for: 0) == [])
        #expect(GridLayout.columns(for: 1) == [1])
        #expect(GridLayout.columns(for: 2) == [1, 1])
        #expect(GridLayout.columns(for: 3) == [2, 1])
        #expect(GridLayout.columns(for: 4) == [2, 2])
        #expect(GridLayout.columns(for: 5) == [2, 2, 1])
        #expect(GridLayout.columns(for: 6) == [2, 2, 2])
        #expect(GridLayout.columns(for: 7) == [2, 2, 2])
    }

    @Test func threeFrames() {
        let f = GridLayout.frames(count: 3, in: CGRect(x: 0, y: 0, width: 1000, height: 600), gap: 0)
        #expect(f[0] == CGRect(x: 0, y: 300, width: 500, height: 300))
        #expect(f[1] == CGRect(x: 0, y: 0, width: 500, height: 300))
        #expect(f[2] == CGRect(x: 500, y: 0, width: 500, height: 600))
    }

    @Test func gapSubtractsBetweenPanes() {
        let f = GridLayout.frames(count: 2, in: CGRect(x: 0, y: 0, width: 1001, height: 600), gap: 1)
        #expect(f[0].width == 500)
        #expect(f[1].minX == 501)
    }

    @Test func fiveFramesKeepOrder() {
        let f = GridLayout.frames(count: 5, in: CGRect(x: 0, y: 0, width: 900, height: 600), gap: 0)
        #expect(f.count == 5)
        #expect(f[2] == CGRect(x: 300, y: 300, width: 300, height: 300))
        #expect(f[4] == CGRect(x: 600, y: 0, width: 300, height: 600))
    }
}
