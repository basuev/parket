import ApplicationServices
import CoreGraphics
import Testing

@testable import ParketCore

@Suite("Window geometry writes")
struct WindowGeometryWriteTests {
    @Test func failedMemberDoesNotPreventRemainingTabsFromMoving() {
        var attempted: [Int] = []
        let result = WindowGeometryWriteBatch.apply([0, 1, 2]) { member in
            attempted.append(member)
            return member == 0 ? .invalidUIElement : .success
        }

        #expect(result == .invalidUIElement)
        #expect(attempted == [0, 1, 2])
    }

    @Test func failedShrinkStillMovesEveryMemberOnscreen() {
        let current = CGRect(x: 1919, y: 1079, width: 1200, height: 800)
        let target = CGRect(x: 480, y: 270, width: 960, height: 540)
        var operations: [FrameWriteOperation] = []
        var moved: [Int] = []
        let result = WindowGeometryWriteBatch.apply(
            WindowFrameWritePlan.operations(current: current, target: target)
        ) { operation in
            operations.append(operation)
            return WindowGeometryWriteBatch.apply([0, 1, 2]) { member in
                if operation == .position {
                    moved.append(member)
                    return .success
                }
                return .attributeUnsupported
            }
        }

        #expect(result == .attributeUnsupported)
        #expect(operations == [.size, .position])
        #expect(moved == [0, 1, 2])
    }

    @Test func failedPositionStillAttemptsSize() {
        let target = CGRect(x: 480, y: 270, width: 960, height: 540)
        var attempted: [FrameWriteOperation] = []
        let result = WindowGeometryWriteBatch.apply(
            WindowFrameWritePlan.operations(current: nil, target: target)
        ) { operation in
            attempted.append(operation)
            return operation == .position ? .attributeUnsupported : .success
        }

        #expect(result == .attributeUnsupported)
        #expect(attempted == [.position, .size])
    }

    @Test func successfulWritesAreNotRepeated() {
        let target = CGRect(x: 0, y: 0, width: 960, height: 540)
        var writes = 0
        let result = WindowGeometryWriteBatch.apply(
            WindowFrameWritePlan.operations(current: nil, target: target)
        ) { _ in
            WindowGeometryWriteBatch.apply([0, 1, 2]) { _ in
                writes += 1
                return .success
            }
        }

        #expect(result == .success)
        #expect(writes == 6)
    }

    @Test func unavailableApplicationDoesNotMultiplyTimeoutsAcrossMembersAndOperations() {
        for error in [AXError.cannotComplete, .apiDisabled] {
            let target = CGRect(x: 0, y: 0, width: 960, height: 540)
            var writes = 0
            let result = WindowGeometryWriteBatch.apply(
                WindowFrameWritePlan.operations(current: nil, target: target)
            ) { _ in
                WindowGeometryWriteBatch.apply([0, 1, 2]) { _ in
                    writes += 1
                    return error
                }
            }

            #expect(result == error)
            #expect(writes == 1)
        }
    }

    @Test func timeoutAfterRecoverableFailureStopsRemainingWrites() {
        var attempted: [Int] = []
        let result = WindowGeometryWriteBatch.apply([0, 1, 2]) { member in
            attempted.append(member)
            return member == 0 ? .invalidUIElement : .cannotComplete
        }

        #expect(result == .cannotComplete)
        #expect(attempted == [0, 1])
    }

    @Test func emptyBatchSucceedsWithoutWrites() {
        let result = WindowGeometryWriteBatch.apply([Int]()) { _ in
            Issue.record("Empty batch attempted a write")
            return .failure
        }

        #expect(result == .success)
    }
}
