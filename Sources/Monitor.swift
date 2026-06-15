import AppKit

enum WindowUpdate {
    case missing
    case inserted
    case replaced
    case unchanged
}

@MainActor
package final class Monitor {
    private static let geometryDebounceDelay: TimeInterval = 0.08
    private static let geometrySuppressionDelay: TimeInterval = 0.20
    private static let scheduledRetileDelay: TimeInterval = 0.025
    private static let frameTolerance: CGFloat = 2.0
    private static let singleWindowSettleStepDelay: TimeInterval = 0.055
    private static let singleWindowSettleMaxAttempts = 4

    let displayID: CGDirectDisplayID
    var screen: NSScreen
    private let tileFrame: CGRect
    private let offscreenFrame: CGRect
    var workspaces: [[TrackedWindow]] = Array(repeating: [], count: Config.shared.workspaceCount)
    var layouts: [Layout] = Array(repeating: .tile, count: Config.shared.workspaceCount)
    var focusedIndices: [Int] = Array(repeating: 0, count: Config.shared.workspaceCount)
    var active: Int = 0
    var previousActive: Int = 0
    private var retileScheduled = false
    private var geometryRetileWork: DispatchWorkItem?
    private var ignoreGeometryUntil: TimeInterval = 0
    private var geometryOperationGeneration: UInt64 = 0
    private var focusRestoreGeneration: UInt64 = 0
    private var moveFocusGeneration: UInt64 = 0

    init(displayID: CGDirectDisplayID, screen: NSScreen, tileFrame: CGRect, offscreenFrame: CGRect) {
        self.displayID = displayID
        self.screen = screen
        self.tileFrame = tileFrame
        self.offscreenFrame = offscreenFrame
    }

    func switchTo(_ index: Int) {
        guard !WorkspaceManager.shared.isTilingPaused else { return }
        guard index >= 0, index < Config.shared.workspaceCount, index != active else { return }

        PerformanceTelemetry.measure(.workspaceSwitch) {
            let previous = active
            previousActive = previous
            active = index

            suppressGeometryNotifications()
            PerformanceTelemetry.traceSubspan("retile") {
                retile(validate: false)
            }
            PerformanceTelemetry.traceSubspan("hide") {
                PerformanceTelemetry.measure(.hideWorkspace) {
                    for win in workspaces[previous] {
                        win.hideOffscreen(offscreenFrame)
                    }
                }
            }
            PerformanceTelemetry.traceSubspan("focus") {
                if activeWorkspaceHasMultipleProcesses() {
                    PerformanceTelemetry.measure(.focusRestore) {
                        restoreFocusedWindow(afterWorkspaceSwitch: true)
                    }
                } else {
                    scheduleFocusedWindowRestore(activeWorkspace: index)
                }
            }
        }
    }

    func revealWorkspace(_ index: Int, focusing focused: TrackedWindow) {
        guard !WorkspaceManager.shared.isTilingPaused else { return }
        guard index >= 0, index < Config.shared.workspaceCount else { return }

        if index != active {
            let previous = active
            previousActive = previous
            active = index

            suppressGeometryNotifications()
            PerformanceTelemetry.measure(.hideWorkspace) {
                for win in workspaces[previous] {
                    win.hideOffscreen(offscreenFrame)
                }
            }
        }

        guard rememberFocusedWindow(focused) else { return }
        retile(validate: false)
        guard rememberFocusedWindow(focused) else { return }

        let target = workspaces[active][focusedIndices[active]]
        PerformanceTelemetry.measure(.focusRestore) {
            target.focus()
        }
    }

    @discardableResult
    func moveActiveWindowTo(_ index: Int) -> TrackedWindow? {
        guard !WorkspaceManager.shared.isTilingPaused else { return nil }
        guard index >= 0, index < Config.shared.workspaceCount, index != active else { return nil }
        guard let focused = WindowManager.focusedWindow() else { return nil }

        guard let i = workspaces[active].firstIndex(of: focused) else { return nil }
        let moved = focused.keepingMembers(from: workspaces[active][i])
        workspaces[active].remove(at: i)
        workspaces[index].insert(moved, at: 0)

        retile(validate: false)
        moved.hideOffscreen(offscreenFrame)
        WindowManager.invalidateAppliedGeometry(moved)

        let next = workspaces[active].first(where: { $0.pid == moved.pid }) ?? workspaces[active].first
        if let next {
            focusAfterWindowRemoval(next)
        }
        return moved
    }

    @discardableResult
    func insertWindow(_ window: TrackedWindow) -> Bool {
        guard updateExistingWindow(window) == .missing else { return false }
        workspaces[active].insert(window, at: 0)
        return true
    }

    @discardableResult
    func addWindow(_ window: TrackedWindow) -> WindowUpdate {
        addWindow(window, workspaceIndex: active)
    }

    @discardableResult
    func addWindow(_ window: TrackedWindow, workspaceIndex: Int) -> WindowUpdate {
        let existing = updateExistingWindow(window)
        guard existing == .missing else { return existing }
        let target = workspaces.indices.contains(workspaceIndex) ? workspaceIndex : active
        workspaces[target].insert(window, at: 0)
        if target == active {
            scheduleRetile()
        } else {
            window.hideOffscreen(offscreenFrame)
            WindowManager.invalidateAppliedGeometry(window)
        }
        return .inserted
    }

    func adoptWindowFromRemovedMonitor(
        _ window: TrackedWindow,
        sourceWorkspaceIndex: Int,
        sourceActive: Int
    ) {
        let target = RemovedMonitorWindowMigration.targetWorkspace(
            sourceWorkspaceIndex: sourceWorkspaceIndex,
            sourceActive: sourceActive,
            targetActive: active,
            workspaceCount: workspaces.count
        )
        guard updateExistingWindow(window) == .missing else { return }
        workspaces[target].insert(window, at: 0)
        if target != active {
            window.hideOffscreen(offscreenFrame)
            WindowManager.invalidateAppliedGeometry(window)
        }
    }

    func updateExistingWindow(_ window: TrackedWindow) -> WindowUpdate {
        for ws in 0..<workspaces.count {
            guard let i = workspaces[ws].firstIndex(of: window) else { continue }
            let current = workspaces[ws][i]
            if current.hasElement(window) {
                if current.group != window.group || !current.hasSameMembers(window) {
                    workspaces[ws][i] = window
                    return .replaced
                }
                return .unchanged
            }
            if current.isTileable() {
                if current.group == window.group && !current.hasSameMembers(window) {
                    workspaces[ws][i] = window
                    return .replaced
                }
                return .unchanged
            }
            workspaces[ws][i] = window
            return .replaced
        }
        return .missing
    }

    func removeWindows(where predicate: (TrackedWindow) -> Bool) -> Bool {
        var needsRetile = false
        var changed = false
        for i in 0..<Config.shared.workspaceCount {
            let before = workspaces[i].count
            workspaces[i].removeAll(where: predicate)
            if workspaces[i].count != before {
                changed = true
                needsRetile = needsRetile || (i == active)
            }
        }
        if changed && needsRetile { scheduleRetile() }
        return changed
    }

    func removeStaleWindows(pid: pid_t, current: [TrackedWindow]) -> Bool {
        removeWindows { window in
            window.pid == pid && !current.contains(window)
        }
    }

    func restoreFocusAfterClosedWindow(removedWindowIndex: Int) -> TrackedWindow? {
        let windows = workspaces[active]
        guard
            let targetIndex = ClosedWindowFocusRepair.targetIndex(
                removedWindowIndex: removedWindowIndex,
                remainingCount: windows.count
            )
        else { return nil }
        focusedIndices[active] = targetIndex
        let target = windows[targetIndex]
        focusAfterWindowRemoval(target)
        return target
    }

    func containsWindow(_ window: TrackedWindow) -> Bool {
        workspaces.contains { $0.contains(window) }
    }

    func focusNext() { focusOffset(1) }
    func focusPrev() { focusOffset(-1) }

    private func focusOffset(_ offset: Int) {
        let windows = workspaces[active]
        guard windows.count > 1,
            let focused = WindowManager.focusedWindow(),
            let i = windows.firstIndex(of: focused)
        else { return }
        let targetIndex = (i + offset + windows.count) % windows.count
        let target = windows[targetIndex]
        target.focus()
        focusedIndices[active] = targetIndex
    }

    func swapMaster() {
        guard !WorkspaceManager.shared.isTilingPaused else { return }
        guard workspaces[active].count > 1 else { return }
        guard let focused = WindowManager.focusedWindow(),
            let i = workspaces[active].firstIndex(of: focused),
            i != 0
        else { return }
        workspaces[active].swapAt(0, i)
        retile(validate: false)
        workspaces[active][0].focus()
    }

    func toggleLayout() {
        guard !WorkspaceManager.shared.isTilingPaused else { return }
        layouts[active] = layouts[active] == .tile ? .monocle : .tile
        retile(validate: false)
        if layouts[active] == .monocle, let focused = WindowManager.focusedWindow(),
            workspaces[active].contains(focused)
        {
            focused.raise()
        }
    }

    private func scheduleRetile() {
        guard !WorkspaceManager.shared.isTilingPaused else { return }
        guard !retileScheduled else { return }
        retileScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scheduledRetileDelay) { [self] in
            retileScheduled = false
            retile(validate: false)
        }
    }

    func scheduleCorrectiveRetile() {
        guard !WorkspaceManager.shared.isTilingPaused else { return }
        guard !shouldSuppressGeometryNotification() else { return }

        geometryRetileWork?.cancel()
        let scheduledActive = active
        let scheduledGeneration = geometryOperationGeneration
        let work = DispatchWorkItem { [self] in
            geometryRetileWork = nil
            guard active == scheduledActive else { return }
            guard geometryOperationGeneration == scheduledGeneration else { return }
            guard ProcessInfo.processInfo.systemUptime >= ignoreGeometryUntil else { return }
            guard !activeWorkspaceMatchesLayout(tolerance: Self.frameTolerance) else { return }
            invalidateActiveWorkspaceAppliedGeometry()
            retile(validate: false)
        }
        geometryRetileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.geometryDebounceDelay, execute: work)
    }

    func shouldSuppressGeometryNotification() -> Bool {
        guard ProcessInfo.processInfo.systemUptime < ignoreGeometryUntil else { return false }
        PerformanceTelemetry.recordSuppressedGeometryNotification()
        return true
    }

    @discardableResult
    func retile(force: Bool = false, validate: Bool = true) -> CGRect {
        guard force || !WorkspaceManager.shared.isTilingPaused else { return tileFrame }
        return PerformanceTelemetry.measure(.retile) {
            if validate {
                cleanActiveWorkspace()
            }
            if force || validate {
                invalidateActiveWorkspaceAppliedGeometry()
            }
            suppressGeometryNotifications()
            let windows = workspaces[active]
            let frames = Tiler.calculateFrames(
                count: windows.count,
                screen: tileFrame,
                layout: layouts[active],
                masterRatio: Config.shared.masterRatio
            )
            for i in windows.indices {
                windows[i].setFrame(frames[i])
            }
            if let window = windows.first, let frame = frames.first, windows.count == 1 {
                scheduleSingleWindowSettle(
                    window: window,
                    target: frame,
                    attempt: 0
                )
            }
            return tileFrame
        }
    }

    func cancelPendingRetile() {
        retileScheduled = false
        geometryRetileWork?.cancel()
        geometryRetileWork = nil
        ignoreGeometryUntil = 0
        geometryOperationGeneration &+= 1
    }

    private func cleanActiveWorkspace() {
        var windows: [TrackedWindow] = []
        for window in workspaces[active] {
            guard window.isTileable(), !windows.contains(window) else { continue }
            windows.append(window)
        }
        workspaces[active] = windows
        clampFocusedIndex()
    }

    private func clampFocusedIndex() {
        focusedIndices[active] = min(focusedIndices[active], max(workspaces[active].count - 1, 0))
    }

    private func scheduleSingleWindowSettle(
        window: TrackedWindow,
        target: CGRect,
        attempt: Int
    ) {
        guard attempt < Self.singleWindowSettleMaxAttempts else { return }
        guard shouldSettleSingleWindow(window, target: target) else { return }

        let delay = Self.singleWindowSettleStepDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            guard shouldSettleSingleWindow(window, target: target) else { return }
            extendGeometrySuppression()
            window.setPosition(target.origin, force: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay * 2) { [self] in
            guard shouldSettleSingleWindow(window, target: target) else { return }
            extendGeometrySuppression()
            window.setSize(target.size, force: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay * 3) { [self] in
            guard shouldSettleSingleWindow(window, target: target) else { return }
            extendGeometrySuppression()
            window.setPosition(target.origin, force: true)
            scheduleSingleWindowSettle(
                window: window,
                target: target,
                attempt: attempt + 1
            )
        }
    }

    private func shouldSettleSingleWindow(
        _ window: TrackedWindow,
        target: CGRect
    ) -> Bool {
        !WorkspaceManager.shared.isTilingPaused
            && WorkspaceManager.shared.monitors.contains { $0 === self }
            && workspaces.indices.contains(active)
            && workspaces[active].count == 1
            && workspaces[active].contains(window)
            && activeWorkspaceTargetMatches(target)
            && !windowMatchesFrame(window, target)
    }

    private func activeWorkspaceTargetMatches(_ target: CGRect) -> Bool {
        let frames = Tiler.calculateFrames(
            count: workspaces[active].count,
            screen: tileFrame,
            layout: layouts[active],
            masterRatio: Config.shared.masterRatio
        )
        guard frames.count == 1, let frame = frames.first else { return false }
        return framesMatch(frame, target, tolerance: Self.frameTolerance)
    }

    private func windowMatchesFrame(_ window: TrackedWindow, _ target: CGRect) -> Bool {
        guard let frame = window.getFrame() else { return false }
        return framesMatch(frame, target, tolerance: Self.frameTolerance)
    }

    private func invalidateActiveWorkspaceAppliedGeometry() {
        for window in workspaces[active] {
            WindowManager.invalidateAppliedGeometry(window)
        }
    }

    private func activeWorkspaceMatchesLayout(tolerance: CGFloat) -> Bool {
        let windows = workspaces[active]
        let frames = Tiler.calculateFrames(count: windows.count, screen: tileFrame, layout: layouts[active])
        guard frames.count == windows.count else { return false }

        for i in windows.indices {
            guard windows[i].isTileable(), let frame = windows[i].getFrame() else { return false }
            guard framesMatch(frame, frames[i], tolerance: tolerance) else { return false }
        }

        return true
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private func suppressGeometryNotifications() {
        geometryOperationGeneration &+= 1
        ignoreGeometryUntil = ProcessInfo.processInfo.systemUptime + Self.geometrySuppressionDelay
    }

    private func extendGeometrySuppression() {
        ignoreGeometryUntil = max(
            ignoreGeometryUntil,
            ProcessInfo.processInfo.systemUptime + Self.geometrySuppressionDelay
        )
    }

    package func resizeWorkspaces(to count: Int) {
        var state = MonitorWorkspaceState(
            workspaces: workspaces,
            layouts: layouts,
            focusedIndices: focusedIndices,
            active: active,
            previousActive: previousActive
        )
        state.resize(to: count)
        workspaces = state.workspaces
        layouts = state.layouts
        focusedIndices = state.focusedIndices
        active = state.active
        previousActive = state.previousActive
    }

    func saveFocusedIndex() {
        guard let focused = WindowManager.focusedWindow(),
            rememberFocusedWindow(focused)
        else { return }
    }

    @discardableResult
    func rememberFocusedWindow(_ focused: TrackedWindow) -> Bool {
        guard let i = workspaces[active].firstIndex(of: focused) else { return false }
        workspaces[active][i] = focused.keepingMembers(from: workspaces[active][i])
        focusedIndices[active] = i
        return true
    }

    func copyState(from source: Monitor) {
        workspaces = source.workspaces
        layouts = source.layouts
        focusedIndices = source.focusedIndices
        active = source.active
        previousActive = source.previousActive
    }

    func resetState() {
        geometryRetileWork?.cancel()
        geometryRetileWork = nil
        ignoreGeometryUntil = 0
        geometryOperationGeneration &+= 1
        let count = Config.shared.workspaceCount
        workspaces = Array(repeating: [], count: count)
        layouts = Array(repeating: .tile, count: count)
        focusedIndices = Array(repeating: 0, count: count)
        active = 0
        previousActive = 0
    }

    func restoreFocusedWindow(afterWorkspaceSwitch: Bool = false) {
        let windows = workspaces[active]
        guard !windows.isEmpty else { return }
        let idx = restoredFocusIndex(in: windows, afterWorkspaceSwitch: afterWorkspaceSwitch)
        let target = windows[idx]
        if afterWorkspaceSwitch {
            WorkspaceManager.shared.suppressExternalFocusFollow()
            if activeWorkspaceHasMultipleProcesses() {
                target.focus()
            } else {
                target.focusAfterWorkspaceSwitch()
            }
        } else {
            target.focus()
        }
    }

    private func restoredFocusIndex(in windows: [TrackedWindow], afterWorkspaceSwitch: Bool) -> Int {
        if afterWorkspaceSwitch,
            activeWorkspaceHasMultipleProcesses(),
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            let index = windows.firstIndex(where: { $0.pid == frontmostPID })
        {
            focusedIndices[active] = index
            return index
        }
        return min(focusedIndices[active], windows.count - 1)
    }

    private func activeWorkspaceHasMultipleProcesses() -> Bool {
        let windows = workspaces[active]
        guard let first = windows.first?.pid else { return false }
        return windows.contains { $0.pid != first }
    }

    private func focusAfterWindowRemoval(_ target: TrackedWindow) {
        moveFocusGeneration &+= 1
        let scheduledGeneration = moveFocusGeneration
        WorkspaceManager.shared.suppressExternalFocusFollow()
        target.focus()
        DispatchQueue.main.async { [self] in
            guard moveFocusGeneration == scheduledGeneration else { return }
            guard workspaces[active].contains(target) else { return }
            WorkspaceManager.shared.suppressExternalFocusFollow()
            target.focus()
        }
    }

    private func scheduleFocusedWindowRestore(activeWorkspace expectedActive: Int) {
        focusRestoreGeneration &+= 1
        let scheduledGeneration = focusRestoreGeneration
        DispatchQueue.main.async { [self] in
            guard active == expectedActive else { return }
            guard focusRestoreGeneration == scheduledGeneration else { return }
            PerformanceTelemetry.measure(.focusRestore) {
                restoreFocusedWindow(afterWorkspaceSwitch: true)
            }
        }
    }

    func restoreAllWindows() {
        let screen = tileFrame
        let center = CGPoint(
            x: screen.origin.x + screen.width / 4,
            y: screen.origin.y + screen.height / 4
        )
        let size = CGSize(width: screen.width / 2, height: screen.height / 2)

        for ws in workspaces {
            for win in ws {
                win.setFrame(CGRect(origin: center, size: size))
            }
        }
    }
}
