import Testing

@testable import ParketCore

@Suite("Workspace focus restoration")
struct WorkspaceFocusRestorationTests {
    @Test func savedWindowWinsOverFirstWindowInMixedAppWorkspace() throws {
        let processes = [10, 20, 10]
        let index = try #require(WorkspaceFocusRestoration.index(savedIndex: 1, windowCount: processes.count))

        #expect(index == 1)
        #expect(processes[index] == 20)
    }

    @Test func savedWindowWithinSameProcessIsPreserved() {
        #expect(WorkspaceFocusRestoration.index(savedIndex: 2, windowCount: 3) == 2)
    }

    @Test func removedSavedWindowFallsBackToLastSurvivor() {
        #expect(WorkspaceFocusRestoration.index(savedIndex: 4, windowCount: 2) == 1)
    }

    @Test func emptyWorkspaceDoesNotRestoreFocus() {
        #expect(WorkspaceFocusRestoration.index(savedIndex: 0, windowCount: 0) == nil)
    }

    @Test func invalidNegativeIndexFallsBackToFirstWindow() {
        #expect(WorkspaceFocusRestoration.index(savedIndex: -1, windowCount: 2) == 0)
    }
}
