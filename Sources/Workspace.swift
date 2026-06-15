import AppKit
import ApplicationServices
import Foundation

@MainActor
package final class WorkspaceManager {
    package static let shared = WorkspaceManager()

    private static let screenChangeDebounceDelay: TimeInterval = 0.25
    private static let screenChangeMaxAttempts = 8
    private static let focusFollowRetryDelay: TimeInterval = 0.015
    private static let focusFollowMaxAttempts = 5
    private static let internalFocusSuppressionDelay: TimeInterval = 0.16
    private static let fallbackRegistryRefreshDelay: TimeInterval = 0.02

    private(set) var monitors: [Monitor] = []
    private(set) var focusedMonitorIndex: Int = 0
    package private(set) var isTilingPaused = false
    private var screenChangeWork: DispatchWorkItem?
    private var focusFollowWork: DispatchWorkItem?
    private var registryRefreshWorks: [pid_t: DispatchWorkItem] = [:]
    private var pendingFocusRepairs: [pid_t: ClosedWindowFocusRepair] = [:]
    private var pendingClosedWindowPIDs: Set<pid_t> = []
    private var ignoreExternalFocusUntil: TimeInterval = 0
    private var statusUpdateScheduled = false
    private let windowRegistry = ShadowWindowRegistry()

    var focusedMonitor: Monitor { monitors[focusedMonitorIndex] }

    private init() {}

    package func bootstrap() {
        let screens = NSScreen.screens
        let snapshot = WindowManager.screenSnapshot(for: screens)
        rebuildMonitors(screens: screens, snapshot: snapshot)
        focusedMonitorIndex = 0
        let windows = PerformanceTelemetry.measure(.axSnapshot) {
            WindowManager.allWindows()
        }
        let fallbackDisplayID = primaryDisplayID()
        for window in windows {
            monitorForWindow(window, snapshot: snapshot, fallbackDisplayID: fallbackDisplayID).insertWindow(window)
        }
        if !isTilingPaused {
            for monitor in monitors {
                monitor.retile(validate: false)
            }
        }
        refreshWindowRegistry()
        StatusBar.shared.update()
    }

    func switchTo(_ index: Int) {
        guard !isTilingPaused else { return }
        focusedMonitor.switchTo(index)
        scheduleStatusUpdate()
    }

    func switchToLast() {
        let target = focusedMonitor.previousActive
        guard target != focusedMonitor.active else { return }
        switchTo(target)
    }

    func moveActiveWindowTo(_ index: Int) {
        guard !isTilingPaused else { return }
        if let moved = focusedMonitor.moveActiveWindowTo(index) {
            refreshWindowRegistry(pid: moved.pid)
        }
        StatusBar.shared.update()
    }

    @discardableResult
    func addWindow(_ window: TrackedWindow) -> WindowUpdate {
        for monitor in monitors {
            let result = monitor.updateExistingWindow(window)
            if result != .missing {
                if result == .replaced {
                    refreshWindowRegistry(pid: window.pid)
                }
                return result
            }
        }
        let target = placementTarget(for: window.pid)
        let monitor = monitors.indices.contains(target.monitorIndex) ? monitors[target.monitorIndex] : focusedMonitor
        let result = monitor.addWindow(window, workspaceIndex: target.workspaceIndex)
        if result == .inserted {
            refreshWindowRegistry(pid: window.pid)
            StatusBar.shared.update()
        }
        if result == .replaced {
            refreshWindowRegistry(pid: window.pid)
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
            refreshWindowRegistry(pid: pid)
        }
        let closedWindow = pendingClosedWindowPIDs.remove(pid) != nil
        let repairedFocus = applyPendingFocusRepair(pid: pid)
        if changed || repairedFocus {
            StatusBar.shared.update()
        }
        if PostSyncExternalFocusPolicy.shouldFollow(
            changed: changed,
            closedWindow: closedWindow,
            repairedFocus: repairedFocus
        ) {
            followExternalFocus(pid: pid)
        }
    }

    func removeWindow(pid: pid_t) {
        var changed = false
        for monitor in monitors {
            if monitor.removeWindows(where: { $0.pid == pid }) {
                changed = true
            }
        }
        registryRefreshWorks.removeValue(forKey: pid)?.cancel()
        pendingFocusRepairs.removeValue(forKey: pid)
        pendingClosedWindowPIDs.remove(pid)
        windowRegistry.remove(pid: pid)
        WindowManager.clearExpectedFocus(pid: pid)
        guard changed else { return }
        StatusBar.shared.update()
    }

    func removeWindow(_ window: TrackedWindow) {
        var changed = false
        for monitor in monitors {
            if monitor.removeWindows(where: { $0.hasElement(window) }) {
                changed = true
            }
        }
        guard changed else { return }
        refreshWindowRegistry(pid: window.pid)
        WindowManager.clearExpectedFocus(window)
        StatusBar.shared.update()
    }

    private func removeWindows(where predicate: (TrackedWindow) -> Bool) {
        var changed = false
        for monitor in monitors {
            if monitor.removeWindows(where: predicate) {
                changed = true
            }
        }
        guard changed else { return }
        refreshWindowRegistry()
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
        refreshWindowRegistry(pid: moved.pid)
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

    func suppressExternalFocusFollow() {
        ignoreExternalFocusUntil = max(
            ignoreExternalFocusUntil,
            ProcessInfo.processInfo.systemUptime + Self.internalFocusSuppressionDelay
        )
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

    func handleWindowDestroyed(pid: pid_t, element: AXUIElement) {
        if let removed = windowRegistry.remove(pid: pid, element: element) {
            WindowManager.clearExpectedFocus(removed.window)
            pendingClosedWindowPIDs.insert(pid)
            suppressExternalFocusFollow()
            recordPendingFocusRepair(removed)
        }
        scheduleRegistryRefresh(pid: pid)
    }

    private func performWindowGeometryChange(pid: pid_t, element: AXUIElement) {
        guard !isTilingPaused else { return }
        guard let location = locateWindow(pid: pid, element: element) else { return }
        let monitor = monitors[location.monitorIndex]
        guard !monitor.shouldSuppressGeometryNotification() else { return }
        let window = monitor.workspaces[location.workspaceIndex][location.windowIndex]
        windowRegistry.upsert(window, at: location)
        WindowManager.invalidateAppliedGeometry(window)
        guard monitor.active == location.workspaceIndex else { return }
        monitor.scheduleCorrectiveRetile()
    }

    private func startExternalFocus(pid: pid_t) {
        guard !isTilingPaused else { return }
        guard !shouldSuppressExternalFocusFollow() else { return }
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
            !shouldSuppressExternalFocusFollow(),
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
            windowRegistry.recordFocus(window, at: location)
            WindowManager.recordExpectedFocus(window)
            StatusBar.shared.update()
            return
        }

        focusedMonitorIndex = location.monitorIndex
        monitor.revealWorkspace(location.workspaceIndex, focusing: window)
        refreshWindowRegistry(pid: window.pid)
        if let updatedLocation = locateWindow(window) {
            windowRegistry.recordFocus(window, at: updatedLocation)
        }
        WindowManager.recordExpectedFocus(window)
        StatusBar.shared.update()
    }

    private func retryExternalFocus(pid: pid_t, attempt: Int) {
        guard attempt < Self.focusFollowMaxAttempts else { return }
        scheduleExternalFocus(pid: pid, attempt: attempt + 1)
    }

    private func shouldSuppressExternalFocusFollow() -> Bool {
        ProcessInfo.processInfo.systemUptime < ignoreExternalFocusUntil
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
            let screens = NSScreen.screens
            let snapshot = WindowManager.screenSnapshot(for: screens)
            rebuildMonitors(screens: screens, snapshot: snapshot)

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
            let fallbackDisplayID = primaryDisplayID()
            for (id, oldMonitor) in old where !currentIDs.contains(id) {
                for workspace in oldMonitor.workspaces {
                    for window in workspace {
                        let target = monitorForWindow(window, snapshot: snapshot, fallbackDisplayID: fallbackDisplayID)
                        target.workspaces[0].insert(window, at: 0)
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

            refreshWindowRegistry()
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
        refreshWindowRegistry()
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
        let screens = NSScreen.screens
        rebuildMonitors(screens: screens, snapshot: WindowManager.screenSnapshot(for: screens))
    }

    private func rebuildMonitors(screens: [NSScreen], snapshot: ScreenSnapshot) {
        monitors =
            screens
            .compactMap { screen -> Monitor? in
                let displayID = WindowManager.displayID(for: screen)
                guard let geometry = snapshot.screen(displayID: displayID) else { return nil }
                return Monitor(
                    displayID: displayID,
                    screen: screen,
                    tileFrame: geometry.visibleFrame,
                    offscreenFrame: geometry.frame
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
        if let location = windowRegistry.locate(window) {
            return location
        }
        refreshWindowRegistry()
        return windowRegistry.locate(window)
    }

    private func locateWindow(pid: pid_t, element: AXUIElement) -> WindowLocation? {
        if let location = windowRegistry.locate(pid: pid, element: element) {
            return location
        }
        refreshWindowRegistry()
        return windowRegistry.locate(pid: pid, element: element)
    }

    private func singleTrackedWindow(pid: pid_t) -> (window: TrackedWindow, location: WindowLocation)? {
        if let result = windowRegistry.singleTrackedWindow(pid: pid) {
            return result
        }
        refreshWindowRegistry()
        return windowRegistry.singleTrackedWindow(pid: pid)
    }

    private func placementTarget(for pid: pid_t) -> WorkspacePlacementTarget {
        let current = WorkspacePlacementTarget(
            monitorIndex: focusedMonitorIndex,
            workspaceIndex: focusedMonitor.active
        )
        return NewWindowPlacement.target(existingAppWindows: appWindowTargets(pid: pid), current: current)
    }

    private func appWindowTargets(pid: pid_t) -> [WorkspacePlacementTarget] {
        var result: [WorkspacePlacementTarget] = []
        for monitorIndex in monitors.indices {
            let monitor = monitors[monitorIndex]
            for workspaceIndex in monitor.workspaces.indices {
                if monitor.workspaces[workspaceIndex].contains(where: { $0.pid == pid }) {
                    result.append(
                        WorkspacePlacementTarget(
                            monitorIndex: monitorIndex,
                            workspaceIndex: workspaceIndex
                        ))
                }
            }
        }
        return result
    }

    private func recordPendingFocusRepair(_ removed: RemovedWindowRecord) {
        let location = removed.location
        guard monitors.indices.contains(location.monitorIndex) else { return }
        let monitor = monitors[location.monitorIndex]
        guard monitor.workspaces.indices.contains(monitor.active),
            monitor.focusedIndices.indices.contains(monitor.active)
        else { return }
        guard
            let repair = ClosedWindowFocusRepair(
                removedLocation: location,
                focusedMonitorIndex: focusedMonitorIndex,
                activeWorkspaceIndex: monitor.active,
                focusedWindowIndex: monitor.focusedIndices[monitor.active],
                wasFocused: removed.wasFocused
            )
        else { return }
        pendingFocusRepairs[removed.window.pid] = repair
        suppressExternalFocusFollow()
    }

    private func applyPendingFocusRepair(pid: pid_t) -> Bool {
        guard let repair = pendingFocusRepairs.removeValue(forKey: pid) else { return false }
        let location = repair.location
        guard monitors.indices.contains(location.monitorIndex) else { return false }
        let monitor = monitors[location.monitorIndex]
        guard monitor.active == location.workspaceIndex else { return false }
        guard let target = monitor.restoreFocusAfterClosedWindow(removedWindowIndex: location.windowIndex) else {
            return false
        }
        focusedMonitorIndex = location.monitorIndex
        let targetLocation = WindowLocation(
            monitorIndex: location.monitorIndex,
            workspaceIndex: location.workspaceIndex,
            windowIndex: monitor.focusedIndices[monitor.active]
        )
        windowRegistry.recordFocus(target, at: targetLocation)
        return true
    }

    private func monitorForWindow(
        _ window: TrackedWindow,
        snapshot: ScreenSnapshot? = nil,
        fallbackDisplayID: CGDirectDisplayID? = nil
    ) -> Monitor {
        guard !monitors.isEmpty else {
            rebuildMonitors()
            return monitors[0]
        }
        guard monitors.count > 1, let frame = window.getFrame() else {
            return monitors[0]
        }
        let snapshot = snapshot ?? WindowManager.screenSnapshot()
        let fallback =
            fallbackDisplayID ?? (monitors.indices.contains(focusedMonitorIndex) ? focusedMonitor.displayID : nil)
        guard let displayID = snapshot.displayID(containingCenterOf: frame, fallback: fallback),
            let monitor = monitors.first(where: { $0.displayID == displayID })
        else { return monitors[0] }
        return monitor
    }

    private func refreshWindowRegistry() {
        windowRegistry.rebuild(from: monitors)
    }

    private func refreshWindowRegistry(pid: pid_t) {
        windowRegistry.reconcile(pid: pid, from: monitors)
    }

    private func scheduleStatusUpdate() {
        guard !statusUpdateScheduled else { return }
        statusUpdateScheduled = true
        DispatchQueue.main.async { [self] in
            statusUpdateScheduled = false
            StatusBar.shared.update()
        }
    }

    private func scheduleRegistryRefresh(pid: pid_t) {
        registryRefreshWorks[pid]?.cancel()
        let work = DispatchWorkItem { [self] in
            registryRefreshWorks.removeValue(forKey: pid)
            refreshWindowRegistry(pid: pid)
        }
        registryRefreshWorks[pid] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fallbackRegistryRefreshDelay, execute: work)
    }
}
