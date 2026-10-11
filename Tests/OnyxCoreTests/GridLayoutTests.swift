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

struct DividerDragTests {
    @Test func dragMovesSpaceBetweenNeighbours() {
        let f = GridLayout.drag(fractions: [0.5, 0.5], divider: 0, by: 100, total: 1000, min: 200)
        #expect(abs(f[0] - 0.6) < 1e-9 && abs(f[1] - 0.4) < 1e-9)
    }

    @Test func dragClampsToMinimum() {
        let f = GridLayout.drag(fractions: [0.5, 0.25, 0.25], divider: 1, by: 500, total: 1000, min: 200)
        #expect(abs(f[1] - 0.3) < 1e-9 && abs(f[2] - 0.2) < 1e-9)
        #expect(abs(f[0] - 0.5) < 1e-9)
    }

    @Test func dragLeftClampsToo() {
        let f = GridLayout.drag(fractions: [0.5, 0.5], divider: 0, by: -450, total: 1000, min: 200)
        #expect(abs(f[0] - 0.2) < 1e-9 && abs(f[1] - 0.8) < 1e-9)
    }
}
