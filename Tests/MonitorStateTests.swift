import Testing

@testable import ParketCore

@Suite("Monitor state")
struct MonitorStateTests {
    @Test func resizeGrowPreservesExistingWorkspaces() {
        var state = MonitorWorkspaceState(
            workspaces: [[1], [2]],
            layouts: [.tile, .monocle],
            focusedIndices: [0, 0],
            active: 1,
            previousActive: 0
        )

        state.resize(to: 4)

        #expect(state.workspaces == [[1], [2], [], []])
        #expect(state.layouts == [.tile, .monocle, .tile, .tile])
        #expect(state.focusedIndices == [0, 0, 0, 0])
        #expect(state.active == 1)
        #expect(state.previousActive == 0)
    }

    @Test func resizeShrinkMovesOverflowToActiveWorkspace() {
        var state = MonitorWorkspaceState(
            workspaces: [[1], [2], [3], [4]],
            layouts: [.tile, .tile, .monocle, .tile],
            focusedIndices: [0, 0, 0, 0],
            active: 3,
            previousActive: 2
        )

        state.resize(to: 2)

        #expect(state.workspaces == [[1], [2, 3, 4]])
        #expect(state.layouts == [.tile, .tile])
        #expect(state.focusedIndices == [0, 0])
        #expect(state.active == 1)
        #expect(state.previousActive == 1)
    }
}
