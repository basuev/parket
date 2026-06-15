import Testing

@testable import ParketCore

@Suite("Close focus repair")
struct CloseFocusRepairTests {
    @Test func focusedWindowOnActiveWorkspaceRecordsRepair() {
        let location = WindowLocation(monitorIndex: 1, workspaceIndex: 2, windowIndex: 0)

        let repair = ClosedWindowFocusRepair(
            removedLocation: location,
            focusedMonitorIndex: 1,
            activeWorkspaceIndex: 2,
            focusedWindowIndex: 0,
            wasFocused: false
        )

        #expect(repair?.location == location)
    }

    @Test func registryFocusedWindowRecordsRepairWhenSavedIndexIsStale() {
        let location = WindowLocation(monitorIndex: 1, workspaceIndex: 2, windowIndex: 0)

        let repair = ClosedWindowFocusRepair(
            removedLocation: location,
            focusedMonitorIndex: 0,
            activeWorkspaceIndex: 2,
            focusedWindowIndex: 3,
            wasFocused: true
        )

        #expect(repair?.location == location)
    }

    @Test func unfocusedWindowDoesNotRecordRepair() {
        let repair = ClosedWindowFocusRepair(
            removedLocation: WindowLocation(monitorIndex: 1, workspaceIndex: 2, windowIndex: 0),
            focusedMonitorIndex: 1,
            activeWorkspaceIndex: 2,
            focusedWindowIndex: 1,
            wasFocused: false
        )

        #expect(repair == nil)
    }

    @Test func inactiveWorkspaceDoesNotRecordRepair() {
        let repair = ClosedWindowFocusRepair(
            removedLocation: WindowLocation(monitorIndex: 1, workspaceIndex: 2, windowIndex: 0),
            focusedMonitorIndex: 1,
            activeWorkspaceIndex: 3,
            focusedWindowIndex: 0,
            wasFocused: true
        )

        #expect(repair == nil)
    }

    @Test func targetIndexUsesPreviousSlotOrLastRemainingWindow() {
        #expect(ClosedWindowFocusRepair.targetIndex(removedWindowIndex: 0, remainingCount: 2) == 0)
        #expect(ClosedWindowFocusRepair.targetIndex(removedWindowIndex: 1, remainingCount: 2) == 1)
        #expect(ClosedWindowFocusRepair.targetIndex(removedWindowIndex: 2, remainingCount: 2) == 1)
        #expect(ClosedWindowFocusRepair.targetIndex(removedWindowIndex: 0, remainingCount: 0) == nil)
    }

    @Test func closedWindowSyncDoesNotFollowExternalFocus() {
        #expect(
            !PostSyncExternalFocusPolicy.shouldFollow(
                changed: true,
                closedWindow: true,
                repairedFocus: false
            ))
    }

    @Test func repairedCloseFocusDoesNotFollowExternalFocus() {
        #expect(
            !PostSyncExternalFocusPolicy.shouldFollow(
                changed: true,
                closedWindow: true,
                repairedFocus: true
            ))
    }

    @Test func newWindowSyncCanFollowExternalFocus() {
        #expect(
            PostSyncExternalFocusPolicy.shouldFollow(
                changed: true,
                closedWindow: false,
                repairedFocus: false
            ))
    }
}
