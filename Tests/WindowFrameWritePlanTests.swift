import CoreGraphics
import Testing

@testable import ParketCore

@Suite("Window frame write plan")
struct WindowFrameWritePlanTests {
    @Test func shrinkingRunsSizeBeforeMove() {
        let current = CGRect(x: 1408, y: 970, width: 1176, height: 705)
        let target = CGRect(x: 1408, y: 970, width: 1152, height: 470)

        #expect(
            WindowFrameWritePlan.operations(current: current, target: target) == [
                .size,
                .position,
                .size,
                .position,
            ])
    }

    @Test func growingMovesBeforeFinalSize() {
        let current = CGRect(x: 1408, y: 970, width: 1152, height: 470)
        let target = CGRect(x: 413, y: 1472, width: 1512, height: 950)

        #expect(
            WindowFrameWritePlan.operations(current: current, target: target) == [
                .position,
                .size,
                .position,
            ])
    }
}
