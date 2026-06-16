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

    @Test func newWindowUsesSingleExistingAppWorkspaceOwner() {
        let owner = WorkspacePlacementTarget(monitorIndex: 1, workspaceIndex: 2)
        let current = WorkspacePlacementTarget(monitorIndex: 0, workspaceIndex: 0)

        let target = NewWindowPlacement.target(existingAppWindows: [owner, owner], current: current)

        #expect(target == owner)
    }

    @Test func newWindowFallsBackToCurrentWorkspaceWhenAppSpansWorkspaces() {
        let current = WorkspacePlacementTarget(monitorIndex: 0, workspaceIndex: 0)

        let target = NewWindowPlacement.target(
            existingAppWindows: [
                WorkspacePlacementTarget(monitorIndex: 0, workspaceIndex: 1),
                WorkspacePlacementTarget(monitorIndex: 0, workspaceIndex: 2),
            ],
            current: current
        )

        #expect(target == current)
    }

    @Test func newWindowFallsBackToCurrentWorkspaceWithoutExistingAppWindows() {
        let current = WorkspacePlacementTarget(monitorIndex: 0, workspaceIndex: 3)

        let target = NewWindowPlacement.target(existingAppWindows: [], current: current)

        #expect(target == current)
    }

    @Test func removedMonitorActiveWorkspaceMovesToTargetActiveWorkspace() {
        let target = RemovedMonitorWindowMigration.targetWorkspace(
            sourceWorkspaceIndex: 3,
            sourceActive: 3,
            targetActive: 1,
            workspaceCount: 9
        )

        #expect(target == 1)
    }

    @Test func removedMonitorInactiveWorkspaceKeepsItsWorkspaceIndex() {
        let target = RemovedMonitorWindowMigration.targetWorkspace(
            sourceWorkspaceIndex: 4,
            sourceActive: 3,
            targetActive: 1,
            workspaceCount: 9
        )

        #expect(target == 4)
    }

    @Test func removedMonitorInvalidWorkspaceFallsBackToTargetActiveWorkspace() {
        let target = RemovedMonitorWindowMigration.targetWorkspace(
            sourceWorkspaceIndex: 12,
            sourceActive: 3,
            targetActive: 1,
            workspaceCount: 9
        )

        #expect(target == 1)
    }

    @Test func screenChangeEmptySnapshotWithTrackedWindowsDefers() {
        #expect(
            ScreenChangeEmptySnapshotPolicy.shouldDefer(
                windowsAreEmpty: true,
                hasTrackedWindows: true,
                isScreenChangeSettling: true
            ))
    }

    @Test func nonemptyScreenChangeSnapshotDoesNotDefer() {
        #expect(
            !ScreenChangeEmptySnapshotPolicy.shouldDefer(
                windowsAreEmpty: false,
                hasTrackedWindows: true,
                isScreenChangeSettling: true
            ))
    }

    @Test func emptySnapshotWithoutTrackedWindowsDoesNotDefer() {
        #expect(
            !ScreenChangeEmptySnapshotPolicy.shouldDefer(
                windowsAreEmpty: true,
                hasTrackedWindows: false,
                isScreenChangeSettling: true
            ))
    }

    @Test func emptySnapshotOutsideScreenChangeDoesNotDefer() {
        #expect(
            !ScreenChangeEmptySnapshotPolicy.shouldDefer(
                windowsAreEmpty: true,
                hasTrackedWindows: true,
                isScreenChangeSettling: false
            ))
    }

    @Test func screenChangeVisibilityPlanRehidesInactiveWorkspaces() {
        #expect(
            ScreenChangeVisibilityPlan.hiddenWorkspaceIndices(
                workspaceCount: 4,
                active: 0
            ) == [1, 2, 3])
        #expect(
            ScreenChangeVisibilityPlan.hiddenWorkspaceIndices(
                workspaceCount: 4,
                active: 2
            ) == [0, 1, 3])
    }

    @Test func windowLocationBoundsRejectStaleIndices() {
        let current = WindowLocation(monitorIndex: 1, workspaceIndex: 2, windowIndex: 3)
        #expect(WindowLocationBounds.containsMonitor(current, monitorCount: 2))
        #expect(WindowLocationBounds.containsWorkspace(current, workspaceCount: 4))
        #expect(WindowLocationBounds.containsWindow(current, windowCount: 4))

        #expect(!WindowLocationBounds.containsMonitor(current, monitorCount: 1))
        #expect(!WindowLocationBounds.containsWorkspace(current, workspaceCount: 2))
        #expect(!WindowLocationBounds.containsWindow(current, windowCount: 3))
    }

}
