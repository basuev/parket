import Foundation
import AppKit
import ApplicationServices

package final class WorkspaceManager {
    package static let shared = WorkspaceManager()

    private struct WindowLocation {
        let monitorIndex: Int
        let workspaceIndex: Int
        let windowIndex: Int
    }

    private static let focusFollowRetryDelay: TimeInterval = 0.015
    private static let focusFollowMaxAttempts = 5

    private(set) var monitors: [Monitor] = []
    private(set) var focusedMonitorIndex: Int = 0
    private var screenChangeWork: DispatchWorkItem?
    private var focusFollowWork: DispatchWorkItem?

    var focusedMonitor: Monitor { monitors[focusedMonitorIndex] }

    private init() {}

    package func bootstrap() {
        rebuildMonitors()
        focusedMonitorIndex = 0
        let windows = WindowManager.allWindows()
        for window in windows {
            monitorForWindow(window).insertWindow(window)
        }
        for monitor in monitors {
            monitor.retile()
        }
        StatusBar.shared.update()
    }

    func switchTo(_ index: Int) {
        focusedMonitor.switchTo(index)
        StatusBar.shared.update()
    }

    func switchToLast() {
        let target = focusedMonitor.previousActive
        guard target != focusedMonitor.active else { return }
        switchTo(target)
    }

    func moveActiveWindowTo(_ index: Int) {
        focusedMonitor.moveActiveWindowTo(index)
        StatusBar.shared.update()
    }

    @discardableResult
    func addWindow(_ window: TrackedWindow) -> WindowUpdate {
        for monitor in monitors {
            let result = monitor.updateExistingWindow(window)
            if result != .missing {
                return result
            }
        }
        let result = focusedMonitor.addWindow(window)
        if result == .inserted {
            StatusBar.shared.update()
        }
        return result
    }

    func syncWindows(pid: pid_t, windows: [TrackedWindow]) {
        var changed = false
        for monitor in monitors {
            if monitor.removeStaleWindows(pid: pid, current: windows) {
                changed = true
            }
        }

        for window in windows {
            let result = addWindow(window)
            changed = changed || result == .inserted || result == .replaced
        }

        if changed {
            StatusBar.shared.update()
        }
    }

    func removeWindow(pid: pid_t) {
        removeWindows { $0.pid == pid }
    }

    func removeWindow(_ window: TrackedWindow) {
        removeWindows { $0.hasElement(window) }
    }

    private func removeWindows(where predicate: (TrackedWindow) -> Bool) {
        var changed = false
        for monitor in monitors {
            if monitor.removeWindows(where: predicate) {
                changed = true
            }
        }
        guard changed else { return }
        StatusBar.shared.update()
    }

    func focusNext() {
        focusedMonitor.focusNext()
    }

    func focusPrev() {
        focusedMonitor.focusPrev()
    }

    func swapMaster() {
        focusedMonitor.swapMaster()
    }

    func toggleLayout() {
        focusedMonitor.toggleLayout()
        StatusBar.shared.update()
    }

    func focusMonitor(offset: Int) {
        guard monitors.count > 1 else { return }
        focusedMonitor.saveFocusedIndex()
        focusedMonitorIndex = (focusedMonitorIndex + offset + monitors.count) % monitors.count
        let target = focusedMonitor
        target.restoreFocusedWindow()
        StatusBar.shared.update()
    }

    func moveWindowToMonitor(offset: Int) {
        guard monitors.count > 1 else { return }
        guard let focused = WindowManager.focusedWindow() else { return }

        let source = focusedMonitor
        guard let i = source.workspaces[source.active].firstIndex(of: focused) else { return }
        let moved = focused.keepingMembers(from: source.workspaces[source.active][i])
        source.workspaces[source.active].remove(at: i)
        source.retile()

        let targetIndex = (focusedMonitorIndex + offset + monitors.count) % monitors.count
        let target = monitors[targetIndex]
        target.insertWindow(moved)
        target.retile()

        focusedMonitorIndex = targetIndex
        moved.focus()
        StatusBar.shared.update()
    }

    func followExternalFocus(pid: pid_t) {
        if Thread.isMainThread {
            startExternalFocus(pid: pid)
        } else {
            DispatchQueue.main.async {
                self.startExternalFocus(pid: pid)
            }
        }
    }

    func handleWindowGeometryChange(pid: pid_t, element: AXUIElement) {
        if Thread.isMainThread {
            performWindowGeometryChange(pid: pid, element: element)
        } else {
            DispatchQueue.main.async {
                self.performWindowGeometryChange(pid: pid, element: element)
            }
        }
    }

    private func performWindowGeometryChange(pid: pid_t, element: AXUIElement) {
        guard let location = locateWindow(pid: pid, element: element) else { return }
        let monitor = monitors[location.monitorIndex]
        guard monitor.active == location.workspaceIndex else { return }
        monitor.scheduleCorrectiveRetile()
    }

    private func startExternalFocus(pid: pid_t) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        focusFollowWork?.cancel()
        performExternalFocus(pid: pid, attempt: 0)
    }

    private func scheduleExternalFocus(pid: pid_t, attempt: Int) {
        focusFollowWork?.cancel()
        let work = DispatchWorkItem { [self] in
            performExternalFocus(pid: pid, attempt: attempt)
        }
        focusFollowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.focusFollowRetryDelay, execute: work)
    }

    private func performExternalFocus(pid: pid_t, attempt: Int) {
        focusFollowWork = nil
        guard !monitors.isEmpty,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        else { return }

        if let focused = WindowManager.focusedWindow(pid: pid),
           let location = locateWindow(focused) {
            revealExternalFocus(focused, at: location)
            return
        }

        if let fallback = singleTrackedWindow(pid: pid) {
            revealExternalFocus(fallback.window, at: fallback.location)
            return
        }

        retryExternalFocus(pid: pid, attempt: attempt)
    }

    private func revealExternalFocus(_ window: TrackedWindow, at location: WindowLocation) {
        let monitor = monitors[location.monitorIndex]
        if monitor.active == location.workspaceIndex {
            focusedMonitorIndex = location.monitorIndex
            if monitor.workspaces[monitor.active].indices.contains(location.windowIndex) {
                monitor.focusedIndices[monitor.active] = location.windowIndex
            }
            monitor.rememberFocusedWindow(window)
            StatusBar.shared.update()
            return
        }

        focusedMonitorIndex = location.monitorIndex
        monitor.revealWorkspace(location.workspaceIndex, focusing: window)
        StatusBar.shared.update()
    }

    private func retryExternalFocus(pid: pid_t, attempt: Int) {
        guard attempt < Self.focusFollowMaxAttempts else { return }
        scheduleExternalFocus(pid: pid, attempt: attempt + 1)
    }

    package func handleScreenChange() {
        screenChangeWork?.cancel()
        let work = DispatchWorkItem { [self] in
            performScreenChange()
        }
        screenChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func performScreenChange() {
        screenChangeWork = nil
        let old = Dictionary(uniqueKeysWithValues: monitors.map { ($0.displayID, $0) })
        let oldPrimaryID = primaryDisplayID()
        let focusedDisplayID = monitors.isEmpty ? 0 : focusedMonitor.displayID
        rebuildMonitors()

        for monitor in monitors {
            if let existing = old[monitor.displayID] {
                monitor.copyState(from: existing)
            }
        }

        let currentIDs = Set(monitors.map { $0.displayID })
        for (id, oldMonitor) in old where !currentIDs.contains(id) {
            let target = monitors[0]
            for ws in oldMonitor.workspaces {
                for window in ws {
                    target.workspaces[target.active].insert(window, at: 0)
                }
            }
        }

        let newPrimaryID = primaryDisplayID()

        if newPrimaryID != oldPrimaryID,
           let newPrimary = monitors.first(where: { $0.displayID == newPrimaryID }),
           let oldPrimary = monitors.first(where: { $0.displayID == oldPrimaryID }),
           newPrimary.workspaces.allSatisfy({ $0.isEmpty }) {
            newPrimary.copyState(from: oldPrimary)
            oldPrimary.resetState()
        }

        if newPrimaryID != oldPrimaryID {
            focusedMonitorIndex = monitors.firstIndex(where: { $0.displayID == newPrimaryID }) ?? 0
        } else {
            focusedMonitorIndex = monitors.firstIndex(where: { $0.displayID == focusedDisplayID }) ?? 0
        }

        for monitor in monitors {
            monitor.retile()
        }
        StatusBar.shared.update()
    }

    package func reloadConfig() {
        Config.load()
        let count = Config.shared.workspaceCount
        for monitor in monitors {
            monitor.resizeWorkspaces(to: count)
            monitor.retile()
        }
        StatusBar.shared.update()
        fputs("parket: config reloaded\n", stderr)
    }

    package func restoreAllWindows() {
        for monitor in monitors {
            monitor.restoreAllWindows()
        }
    }

    private func rebuildMonitors() {
        monitors = NSScreen.screens
            .map { screen in
                Monitor(
                    displayID: WindowManager.displayID(for: screen),
                    screen: screen
                )
            }
            .sorted { $0.screen.frame.origin.x < $1.screen.frame.origin.x }
    }

    private func primaryDisplayID() -> CGDirectDisplayID {
        guard !monitors.isEmpty else { return 0 }
        return monitors.first(where: { $0.screen == NSScreen.main })?.displayID ?? monitors[0].displayID
    }

    private func locateWindow(_ window: TrackedWindow) -> WindowLocation? {
        for monitorIndex in monitors.indices {
            let monitor = monitors[monitorIndex]
            for workspaceIndex in monitor.workspaces.indices {
                if let windowIndex = monitor.workspaces[workspaceIndex].firstIndex(of: window) {
                    return WindowLocation(
                        monitorIndex: monitorIndex,
                        workspaceIndex: workspaceIndex,
                        windowIndex: windowIndex
                    )
                }
            }
        }
        return nil
    }

    private func locateWindow(pid: pid_t, element: AXUIElement) -> WindowLocation? {
        for monitorIndex in monitors.indices {
            let monitor = monitors[monitorIndex]
            for workspaceIndex in monitor.workspaces.indices {
                for windowIndex in monitor.workspaces[workspaceIndex].indices {
                    let window = monitor.workspaces[workspaceIndex][windowIndex]
                    guard window.pid == pid, window.containsElement(element) else { continue }
                    return WindowLocation(
                        monitorIndex: monitorIndex,
                        workspaceIndex: workspaceIndex,
                        windowIndex: windowIndex
                    )
                }
            }
        }
        return nil
    }

    private func singleTrackedWindow(pid: pid_t) -> (window: TrackedWindow, location: WindowLocation)? {
        var result: (window: TrackedWindow, location: WindowLocation)?

        for monitorIndex in monitors.indices {
            let monitor = monitors[monitorIndex]
            for workspaceIndex in monitor.workspaces.indices {
                for windowIndex in monitor.workspaces[workspaceIndex].indices {
                    let window = monitor.workspaces[workspaceIndex][windowIndex]
                    guard window.pid == pid, window.isTileable() else { continue }

                    guard result == nil else { return nil }
                    result = (
                        window,
                        WindowLocation(
                            monitorIndex: monitorIndex,
                            workspaceIndex: workspaceIndex,
                            windowIndex: windowIndex
                        )
                    )
                }
            }
        }

        return result
    }

    private func monitorForWindow(_ window: TrackedWindow) -> Monitor {
        guard monitors.count > 1, let frame = window.getFrame() else {
            return monitors[0]
        }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        for monitor in monitors {
            let rect = WindowManager.screenRect(for: monitor.screen)
            if rect.contains(center) {
                return monitor
            }
        }
        return monitors[0]
    }
}
