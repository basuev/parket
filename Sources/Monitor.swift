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
    private static let frameTolerance: CGFloat = 2.0

    let displayID: CGDirectDisplayID
    var screen: NSScreen
    var workspaces: [[TrackedWindow]] = Array(repeating: [], count: Config.shared.workspaceCount)
    var layouts: [Layout] = Array(repeating: .tile, count: Config.shared.workspaceCount)
    var focusedIndices: [Int] = Array(repeating: 0, count: Config.shared.workspaceCount)
    var active: Int = 0
    var previousActive: Int = 0
    private var retileScheduled = false
    private var geometryRetileWork: DispatchWorkItem?
    private var ignoreGeometryUntil: TimeInterval = 0
    private var geometryOperationGeneration: UInt64 = 0

    init(displayID: CGDirectDisplayID, screen: NSScreen) {
        self.displayID = displayID
        self.screen = screen
    }

    func switchTo(_ index: Int) {
        guard !WorkspaceManager.shared.isTilingPaused else { return }
        guard index >= 0, index < Config.shared.workspaceCount, index != active else { return }

        PerformanceTelemetry.measure(.workspaceSwitch) {
            let previous = active
            previousActive = previous
            active = index

            let screen = WindowManager.screenRect(for: self.screen)
            suppressGeometryNotifications()
            PerformanceTelemetry.measure(.hideWorkspace) {
                for win in workspaces[previous] {
                    win.hideOffscreen(screen)
                }
            }

            retile(validate: false)
            PerformanceTelemetry.measure(.focusRestore) {
                restoreFocusedWindow()
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

            let screen = WindowManager.screenRect(for: self.screen)
            suppressGeometryNotifications()
            PerformanceTelemetry.measure(.hideWorkspace) {
                for win in workspaces[previous] {
                    win.hideOffscreen(screen)
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

    func moveActiveWindowTo(_ index: Int) {
        guard !WorkspaceManager.shared.isTilingPaused else { return }
        guard index >= 0, index < Config.shared.workspaceCount, index != active else { return }
        guard let focused = WindowManager.focusedWindow() else { return }

        guard let i = workspaces[active].firstIndex(of: focused) else { return }
        let moved = focused.keepingMembers(from: workspaces[active][i])
        workspaces[active].remove(at: i)
        workspaces[index].insert(moved, at: 0)

        retile(validate: false)
        moved.hideOffscreen(WindowManager.screenRect(for: self.screen))

        if let next = workspaces[active].first {
            next.focus()
        }
    }

    @discardableResult
    func insertWindow(_ window: TrackedWindow) -> Bool {
        guard updateExistingWindow(window) == .missing else { return false }
        workspaces[active].insert(window, at: 0)
        return true
    }

    @discardableResult
    func addWindow(_ window: TrackedWindow) -> WindowUpdate {
        let existing = updateExistingWindow(window)
        guard existing == .missing else { return existing }
        workspaces[active].insert(window, at: 0)
        scheduleRetile()
        return .inserted
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
        DispatchQueue.main.async { [self] in
            retileScheduled = false
            retile(validate: false)
        }
    }

    func scheduleCorrectiveRetile() {
        guard !WorkspaceManager.shared.isTilingPaused else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= ignoreGeometryUntil else {
            PerformanceTelemetry.recordSuppressedGeometryNotification()
            return
        }

        geometryRetileWork?.cancel()
        let scheduledActive = active
        let scheduledGeneration = geometryOperationGeneration
        let work = DispatchWorkItem { [self] in
            geometryRetileWork = nil
            guard active == scheduledActive else { return }
            guard geometryOperationGeneration == scheduledGeneration else { return }
            guard ProcessInfo.processInfo.systemUptime >= ignoreGeometryUntil else { return }
            guard !activeWorkspaceMatchesLayout(tolerance: Self.frameTolerance) else { return }
            retile(validate: false)
        }
        geometryRetileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.geometryDebounceDelay, execute: work)
    }

    @discardableResult
    func retile(force: Bool = false, validate: Bool = true) -> CGRect {
        let screen = WindowManager.screenFrame(for: self.screen)
        guard force || !WorkspaceManager.shared.isTilingPaused else { return screen }
        return PerformanceTelemetry.measure(.retile) {
            if validate {
                cleanActiveWorkspace()
            }
            suppressGeometryNotifications()
            Tiler.tile(
                windows: workspaces[active], screen: screen, layout: layouts[active],
                masterRatio: Config.shared.masterRatio
            )
            return screen
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
    }

    private func activeWorkspaceMatchesLayout(tolerance: CGFloat) -> Bool {
        let windows = workspaces[active]
        let screen = WindowManager.screenFrame(for: self.screen)
        let frames = Tiler.calculateFrames(count: windows.count, screen: screen, layout: layouts[active])
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

    func restoreFocusedWindow() {
        let windows = workspaces[active]
        guard !windows.isEmpty else { return }
        let idx = min(focusedIndices[active], windows.count - 1)
        let target = windows[idx]
        target.focus()
    }

    func restoreAllWindows() {
        let screen = WindowManager.screenFrame(for: self.screen)
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
