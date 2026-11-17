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

struct PaneMoveTests {
    @Test func centerDropExchangesLeftAndRightPanes() {
        let drop = GridLayout.dropping(from: 0, onto: 2, edge: .center, columns: [2, 1])
        #expect(drop.order == [2, 1, 0])
        #expect(drop.columns == [2, 1])
    }

    @Test func bottomDropMovesStackToRightColumn() {
        for from in 0...1 {
            let drop = GridLayout.dropping(from: from, onto: 2, edge: .below, columns: [2, 1])
            #expect(drop.order == [1 - from, 2, from])
            #expect(drop.columns == [1, 2])
        }
    }

    @Test func topDropAndReverseSplit() {
        let top = GridLayout.dropping(from: 1, onto: 2, edge: .above, columns: [2, 1])
        #expect(top.order == [0, 1, 2] && top.columns == [1, 2])
        let left = GridLayout.dropping(from: 2, onto: 0, edge: .below, columns: [1, 2])
        #expect(left.order == [0, 2, 1] && left.columns == [2, 1])
        let vertical = GridLayout.dropping(from: 0, onto: 1, edge: .below, columns: [1, 1])
        #expect(vertical.order == [1, 0] && vertical.columns == [2])
    }

    @Test func everyDropKeepsAllPanesAndAtMostTwoRows() {
        for columns in [[1], [1, 1], [2], [2, 1], [1, 2], [2, 2], [2, 2, 1], [2, 2, 2]] {
            let count = columns.reduce(0, +)
            for from in 0..<count {
                for target in 0..<count {
                    for edge: GridLayout.DropEdge in [.center, .above, .below] {
                        let drop = GridLayout.dropping(from: from, onto: target, edge: edge, columns: columns)
                        #expect(drop.order.sorted() == Array(0..<count))
                        #expect(drop.columns.reduce(0, +) == count)
                        #expect(drop.columns.allSatisfy { (1...2).contains($0) })
                    }
                }
            }
        }
    }

    @Test func movingLastToFirstShiftsTheOthersOn() {
        // Three panes: 1 and 2 stacked left, 3 right. Drop 3 on 1's place: 1 moves down, 2 goes right.
        #expect(GridLayout.moving([1, 2, 3], from: 2, to: 0) == [3, 1, 2])
    }

    @Test func movingForwardAndInPlace() {
        #expect(GridLayout.moving([1, 2, 3, 4], from: 0, to: 2) == [2, 3, 1, 4])
        #expect(GridLayout.moving([1, 2, 3], from: 1, to: 1) == [1, 2, 3])
        #expect(GridLayout.moving([1, 2, 3], from: 5, to: 0) == [1, 2, 3])
    }

    @Test func slotUnderPoint() {
        let f = GridLayout.frames(count: 3, in: CGRect(x: 0, y: 0, width: 1000, height: 600), gap: 1)
        #expect(GridLayout.slot(at: CGPoint(x: 100, y: 500), in: f) == 0)
        #expect(GridLayout.slot(at: CGPoint(x: 100, y: 100), in: f) == 1)
        #expect(GridLayout.slot(at: CGPoint(x: 900, y: 300), in: f) == 2)
        #expect(GridLayout.slot(at: CGPoint(x: 1200, y: 300), in: f) == nil)
    }
}
