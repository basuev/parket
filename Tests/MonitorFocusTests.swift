import AppKit
import ApplicationServices
import Testing

@testable import ParketCore

@Suite("Monitor focus", .serialized)
@MainActor
struct MonitorFocusTests {
    @Test func moveSuccessorIsRememberedWithoutExternalFocusNotification() async throws {
        let monitor = try makeMonitor()
        let a1 = window(1, pid: -10)
        let a2 = window(2, pid: -10)
        let a3 = window(3, pid: -10)
        let b1 = window(4, pid: -20)
        let b2 = window(5, pid: -20)
        monitor.workspaces[0] = [b1, a1, a3]
        monitor.workspaces[1] = [b2, a2]
        monitor.focusedIndices[0] = 2
        monitor.focusedIndices[1] = 1
        let readsBefore = axReadCount()

        monitor.focusAfterWindowRemoval(b1)

        #expect(monitor.focusedIndices[0] == 0)
        #expect(axReadCount() == readsBefore)
        monitor.active = 1
        monitor.restoreFocusedWindow(afterWorkspaceSwitch: true)
        #expect(WindowManager.isExpectedFocused(a2))
        monitor.active = 0
        monitor.restoreFocusedWindow(afterWorkspaceSwitch: true)
        #expect(WindowManager.isExpectedFocused(b1))

        await drainFocusRetry()
        WindowManager.clearExpectedFocus(pid: -10)
        WindowManager.clearExpectedFocus(pid: -20)
    }

    @Test func successorAtNonzeroIndexKeepsNativeTabMembers() async throws {
        let monitor = try makeMonitor()
        let first = window(1, pid: -10)
        let representative = window(2, pid: -20)
        let member = AXUIElementCreateApplication(-3)
        let tab = TrackedWindow(
            element: representative.element,
            pid: -20,
            members: [member],
            group: representative.group
        )
        monitor.workspaces[0] = [first, tab]
        monitor.focusedIndices[0] = 0

        monitor.focusAfterWindowRemoval(tab)

        #expect(monitor.focusedIndices[0] == 1)
        #expect(monitor.workspaces[0][1].hasSameMembers(tab))
        #expect(monitor.workspaces[0][1].containsElement(member))
        monitor.restoreFocusedWindow(afterWorkspaceSwitch: true)
        #expect(WindowManager.isExpectedFocused(tab))

        await drainFocusRetry()
        WindowManager.clearExpectedFocus(pid: -10)
        WindowManager.clearExpectedFocus(pid: -20)
    }

    private func window(_ id: Int32, pid: pid_t) -> TrackedWindow {
        TrackedWindow(
            element: AXUIElementCreateApplication(-id),
            pid: pid,
            group: WindowGroupKey(pid: pid, identity: .element(UInt(id)))
        )
    }

    private func makeMonitor() throws -> Monitor {
        let screen = try #require(NSScreen.screens.first)
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        return Monitor(
            displayID: 1,
            screen: screen,
            tileFrame: frame,
            offscreenContext: OffscreenWindowPlacementContext(screen: frame, visibleScreens: [frame])
        )
    }

    private func axReadCount() -> String? {
        PerformanceTelemetry.diagnosticLines().first { $0.hasPrefix("performance_ax_reads:") }
    }

    private func drainFocusRetry() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
