import AppKit
import ApplicationServices
import Testing

@testable import ParketCore

@Suite("Shadow window registry")
@MainActor
struct ShadowWindowRegistryTests {
    @Test func insertionByAnotherProcessRepairsInBoundsCachedIndexWithoutAXReads() throws {
        let monitor = try makeMonitor()
        let first = window(1, pid: 10)
        let second = window(2, pid: 20)
        let inserted = window(3, pid: 20)
        monitor.workspaces[0] = [first, second]
        let registry = ShadowWindowRegistry()
        registry.rebuild(from: [monitor])

        monitor.workspaces[0].insert(inserted, at: 0)
        registry.reconcile(pid: 20, from: [monitor])
        let telemetry = PerformanceTelemetry.diagnosticLines()

        #expect(registry.locate(first, in: [monitor]) == location(windowIndex: 1))
        #expect(registry.locate(pid: 10, element: first.element, in: [monitor]) == location(windowIndex: 1))
        #expect(PerformanceTelemetry.diagnosticLines() == telemetry)
    }

    @Test func removalByAnotherProcessRepairsOutOfBoundsCachedIndex() throws {
        let monitor = try makeMonitor()
        let removed = window(1, pid: 10)
        let survivor = window(2, pid: 20)
        monitor.workspaces[0] = [removed, survivor]
        let registry = ShadowWindowRegistry()
        registry.rebuild(from: [monitor])

        monitor.workspaces[0].removeFirst()
        registry.reconcile(pid: 10, from: [monitor])

        #expect(registry.locate(survivor, in: [monitor]) == location(windowIndex: 0))
        #expect(registry.locate(removed, in: [monitor]) == nil)
    }

    @Test func destroyedWindowUsesCurrentIndexAfterMasterSwap() throws {
        let monitor = try makeMonitor()
        let first = window(1, pid: 10)
        let second = window(2, pid: 20)
        monitor.workspaces[0] = [first, second]
        let registry = ShadowWindowRegistry()
        registry.rebuild(from: [monitor])
        registry.recordFocus(first, at: location(windowIndex: 0))

        monitor.workspaces[0].swapAt(0, 1)
        let removed = try #require(registry.remove(pid: 10, element: first.element, from: [monitor]))

        #expect(removed.location == location(windowIndex: 1))
        #expect(removed.wasFocused)
        #expect(removed.window == first)
    }

    @Test func movedWindowResolvesCurrentWorkspaceAndMonitor() throws {
        let source = try makeMonitor()
        let target = try makeMonitor()
        let moved = window(1, pid: 10)
        source.workspaces[0] = [moved]
        let registry = ShadowWindowRegistry()
        registry.rebuild(from: [source, target])

        source.workspaces[0] = []
        target.workspaces[1] = [moved]

        #expect(
            registry.locate(pid: 10, element: moved.element, in: [source, target])
                == WindowLocation(monitorIndex: 1, workspaceIndex: 1, windowIndex: 0)
        )
    }

    @Test func nativeTabMemberResolvesAfterReordering() throws {
        let monitor = try makeMonitor()
        let tab = window(1, pid: 10)
        let other = window(2, pid: 20)
        let member = AXUIElementCreateApplication(-3)
        let group = TrackedWindow(element: tab.element, pid: 10, members: [member], group: tab.group)
        monitor.workspaces[0] = [group, other]
        let registry = ShadowWindowRegistry()
        registry.rebuild(from: [monitor])

        monitor.workspaces[0].swapAt(0, 1)

        #expect(registry.locate(pid: 10, element: member, in: [monitor]) == location(windowIndex: 1))
    }

    @Test func changedNativeTabRepresentativeKeepsLocation() throws {
        let monitor = try makeMonitor()
        let first = window(1, pid: 10)
        let member = AXUIElementCreateApplication(-2)
        let group = TrackedWindow(element: first.element, pid: 10, members: [member], group: first.group)
        let focusedTab = TrackedWindow(
            element: member,
            pid: 10,
            group: WindowGroupKey(pid: 10, identity: .element(2))
        )
        monitor.workspaces[0] = [group]
        let registry = ShadowWindowRegistry()
        registry.rebuild(from: [monitor])

        #expect(group == focusedTab)
        #expect(registry.locate(focusedTab, in: [monitor]) == location(windowIndex: 0))
    }

    private func window(_ id: Int32, pid: pid_t) -> TrackedWindow {
        TrackedWindow(
            element: AXUIElementCreateApplication(-id),
            pid: pid,
            group: WindowGroupKey(pid: pid, identity: .element(UInt(id)))
        )
    }

    private func location(windowIndex: Int) -> WindowLocation {
        WindowLocation(monitorIndex: 0, workspaceIndex: 0, windowIndex: windowIndex)
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
}
