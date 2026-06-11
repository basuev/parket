import Testing

@testable import ParketCore

@Suite("Workspace state")
struct WorkspaceStateTests {
    @Test func workspaceCountIsClampedToOneThroughNine() {
        #expect(WorkspaceBounds.clampedCount(-4) == 1)
        #expect(WorkspaceBounds.clampedCount(0) == 1)
        #expect(WorkspaceBounds.clampedCount(4) == 4)
        #expect(WorkspaceBounds.clampedCount(14) == 9)
    }

    @Test func switchToTracksPreviousWorkspace() {
        var state = WorkspaceState(count: 9)
        let switched = state.switchTo(3)
        #expect(switched)
        #expect(state.active == 3)
        #expect(state.previousActive == 0)
        let sameWorkspace = state.switchTo(3)
        let outOfBounds = state.switchTo(9)
        #expect(!sameWorkspace)
        #expect(!outOfBounds)
    }

    @Test func resizeKeepsActiveWorkspaceValid() {
        var state = WorkspaceState(count: 9, active: 8, previousActive: 7)
        state.resize(to: 4)
        #expect(state.count == 4)
        #expect(state.active == 3)
        #expect(state.previousActive == 3)
    }
}
