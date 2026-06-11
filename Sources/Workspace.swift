import AppKit
import ApplicationServices
import Foundation

@MainActor
package final class WorkspaceManager {
    package static let shared = WorkspaceManager()

    private struct WindowLocation {
        let monitorIndex: Int
        let workspaceIndex: Int
        let windowIndex: Int
    }

    private static let screenChangeDebounceDelay: TimeInterval = 0.25
    private static let screenChangeMaxAttempts = 8
    private static let focusFollowRetryDelay: TimeInterval = 0.015
    private static let focusFollowMaxAttempts = 5

    private(set) var monitors: [Monitor] = []
    private(set) var focusedMonitorIndex: Int = 0
    package private(set) var isTilingPaused = false
    private var screenChangeWork: DispatchWorkItem?
    private var focusFollowWork: DispatchWorkItem?

    var focusedMonitor: Monitor { monitors[focusedMonitorIndex] }

    private init() {}

    package func bootstrap() {
        rebuildMonitors()
        focusedMonitorIndex = 0
        let windows = PerformanceTelemetry.measure(.axSnapshot) {
            WindowManager.allWindows()
        }
        for window in windows {
            monitorForWindow(window).insertWindow(window)
        }
        if !isTilingPaused {
            for monitor in monitors {
                monitor.retile(validate: false)
            }
        }
        StatusBar.shared.update()
    }

    func switchTo(_ index: Int) {
        guard !isTilingPaused else { return }
        focusedMonitor.switchTo(index)
        StatusBar.shared.update()
    }

    func switchToLast() {
        let target = focusedMonitor.previousActive
        guard target != focusedMonitor.active else { return }
        switchTo(target)
    }

    func moveActiveWindowTo(_ index: Int) {
        guard !isTilingPaused else { return }
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
        guard !isTilingPaused else { return }
        focusedMonitor.swapMaster()
    }

    func toggleLayout() {
        guard !isTilingPaused else { return }
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
        guard !isTilingPaused else { return }
        guard monitors.count > 1 else { return }
        guard let focused = WindowManager.focusedWindow() else { return }

        let source = focusedMonitor
        guard let i = source.workspaces[source.active].firstIndex(of: focused) else { return }
        let moved = focused.keepingMembers(from: source.workspaces[source.active][i])
        source.workspaces[source.active].remove(at: i)
        source.retile(validate: false)

        let targetIndex = (focusedMonitorIndex + offset + monitors.count) % monitors.count
        let target = monitors[targetIndex]
        target.insertWindow(moved)
        target.retile(validate: false)

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
        guard !isTilingPaused else { return }
        guard let location = locateWindow(pid: pid, element: element) else { return }
        let monitor = monitors[location.monitorIndex]
        WindowManager.invalidateAppliedGeometry(monitor.workspaces[location.workspaceIndex][location.windowIndex])
        guard monitor.active == location.workspaceIndex else { return }
        monitor.scheduleCorrectiveRetile()
    }

    private func startExternalFocus(pid: pid_t) {
        guard !isTilingPaused else { return }
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
        guard !isTilingPaused,
            !monitors.isEmpty,
            NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        else { return }

        if let focused = WindowManager.focusedWindow(pid: pid),
            let location = locateWindow(focused)
        {
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
        scheduleScreenChange(signature: WindowManager.screenTopologySignature(), attempt: 0)
    }

    private func scheduleScreenChange(signature: String, attempt: Int) {
        screenChangeWork?.cancel()
        let work = DispatchWorkItem { [self] in
            performStableScreenChange(expectedSignature: signature, attempt: attempt)
        }
        screenChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.screenChangeDebounceDelay, execute: work)
    }

    private func performStableScreenChange(expectedSignature: String, attempt: Int) {
        let currentSignature = WindowManager.screenTopologySignature()
        guard currentSignature == expectedSignature || attempt >= Self.screenChangeMaxAttempts else {
            scheduleScreenChange(signature: currentSignature, attempt: attempt + 1)
            return
        }
        performScreenChange()
    }

    private func performScreenChange() {
        PerformanceTelemetry.measure(.screenChange) {
            screenChangeWork = nil
            let old = Dictionary(uniqueKeysWithValues: monitors.map { ($0.displayID, $0) })
            let focusedDisplayID = monitors.isEmpty ? 0 : focusedMonitor.displayID
            rebuildMonitors()

            guard !monitors.isEmpty else {
                focusedMonitorIndex = 0
                StatusBar.shared.update()
                return
            }

            for monitor in monitors {
                if let existing = old[monitor.displayID] {
                    monitor.copyState(from: existing)
                }
            }

            let currentIDs = Set(monitors.map { $0.displayID })
            for (id, oldMonitor) in old where !currentIDs.contains(id) {
                for workspace in oldMonitor.workspaces {
                    for window in workspace {
                        monitorForWindow(window).workspaces[0].insert(window, at: 0)
                    }
                }
            }

            if let index = monitors.firstIndex(where: { $0.displayID == focusedDisplayID }) {
                focusedMonitorIndex = index
            } else {
                focusedMonitorIndex = monitors.firstIndex(where: { $0.displayID == primaryDisplayID() }) ?? 0
            }

            if !isTilingPaused {
                for monitor in monitors {
                    monitor.retile(validate: true)
                }
            }

            StatusBar.shared.update()
        }
    }

    package func applyCurrentConfig() {
        let count = Config.shared.workspaceCount
        for monitor in monitors {
            monitor.resizeWorkspaces(to: count)
            if !isTilingPaused {
                monitor.retile(validate: true)
            }
        }
        StatusBar.shared.update()
    }

    package func setTilingPaused(_ paused: Bool) {
        guard isTilingPaused != paused else { return }
        isTilingPaused = paused
        if paused {
            for monitor in monitors {
                monitor.cancelPendingRetile()
            }
        } else {
            retileNow()
        }
        StatusBar.shared.update()
    }

    package func toggleTilingPaused() {
        setTilingPaused(!isTilingPaused)
    }

    package func retileNow() {
        for monitor in monitors {
            monitor.retile(force: true)
        }
        StatusBar.shared.update()
    }

    package func pauseTilingAndRestoreAllWindows() {
        setTilingPaused(true)
        restoreAllWindows()
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
            .sorted { lhs, rhs in
                let lhsFrame = lhs.screen.frame
                let rhsFrame = rhs.screen.frame
                if abs(lhsFrame.origin.y - rhsFrame.origin.y) > 0.5 {
                    return lhsFrame.origin.y > rhsFrame.origin.y
                }
                if abs(lhsFrame.origin.x - rhsFrame.origin.x) > 0.5 {
                    return lhsFrame.origin.x < rhsFrame.origin.x
                }
                return lhs.displayID < rhs.displayID
            }
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
        guard !monitors.isEmpty else {
            rebuildMonitors()
            return monitors[0]
        }
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
