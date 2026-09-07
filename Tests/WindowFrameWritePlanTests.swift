import CoreGraphics
import Testing

@testable import ParketCore

@Suite("Window frame write plan")
struct WindowFrameWritePlanTests {
    @Test func shrinkingRunsSizeBeforeMoveWithoutRepeatingWrites() {
        let current = CGRect(x: 1408, y: 970, width: 1176, height: 705)
        let target = CGRect(x: 1408, y: 970, width: 1152, height: 470)

        #expect(
            WindowFrameWritePlan.operations(current: current, target: target) == [
                .size,
                .position,
            ])
    }

    @Test func growingMovesBeforeSizeWithoutTerminalPositionWrite() {
        let current = CGRect(x: 1408, y: 970, width: 1152, height: 470)
        let target = CGRect(x: 413, y: 1472, width: 1512, height: 950)

        #expect(
            WindowFrameWritePlan.operations(current: current, target: target) == [
                .position,
                .size,
            ])
    }

    @Test func settleMovesBeforeRetryingSize() {
        let current = CGRect(x: 450, y: 322, width: 900, height: 600)
        let target = CGRect(x: 0, y: 39, width: 900, height: 1130)

        #expect(
            WindowFrameSettlePlan.operation(current: current, target: target, tolerance: 2) == .position
        )
    }

    @Test func settleRetriesSizeAfterPositionMatches() {
        let current = CGRect(x: 0, y: 39, width: 900, height: 600)
        let target = CGRect(x: 0, y: 39, width: 900, height: 1130)

        #expect(WindowFrameSettlePlan.operation(current: current, target: target, tolerance: 2) == .size)
    }

    @Test func settleStopsAfterFrameMatches() {
        let target = CGRect(x: 0, y: 39, width: 900, height: 1130)

        #expect(WindowFrameSettlePlan.operation(current: target, target: target, tolerance: 2) == nil)
    }

    @Test func settleStopsAfterRejectedSizeWrite() {
        let current = CGRect(x: 900, y: 39, width: 900, height: 600)
        let target = CGRect(x: 900, y: 39, width: 900, height: 226)
        let previousAttempt = WindowFrameSettleAttempt(operation: .size, frame: current)

        #expect(
            WindowFrameSettlePlan.operation(
                current: current,
                target: target,
                tolerance: 2,
                previousAttempt: previousAttempt
            ) == nil
        )
    }
}
