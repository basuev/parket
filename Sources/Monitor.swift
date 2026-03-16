import AppKit

package final class Monitor {
    let displayID: CGDirectDisplayID
    var screen: NSScreen
    var workspaces: [[TrackedWindow]] = Array(repeating: [], count: Config.shared.workspaceCount)
    var layouts: [Layout] = Array(repeating: .tile, count: Config.shared.workspaceCount)
    var active: Int = 0
    var previousActive: Int = 0
    private var retileScheduled = false

    init(displayID: CGDirectDisplayID, screen: NSScreen) {
        self.displayID = displayID
        self.screen = screen
    }

    func switchTo(_ index: Int) {
        guard index >= 0, index < Config.shared.workspaceCount, index != active else { return }

        let previous = active
        previousActive = previous
        active = index

        let screen = WindowManager.screenRect(for: self.screen)
        for win in workspaces[previous] {
            win.hideOffscreen(screen)
        }

        retile()

        if let master = workspaces[active].first {
            master.focus()
        }
    }

    func moveActiveWindowTo(_ index: Int) {
        guard index >= 0, index < Config.shared.workspaceCount, index != active else { return }
        guard let focused = WindowManager.focusedWindow() else { return }

        guard let i = workspaces[active].firstIndex(of: focused) else { return }
        workspaces[active].remove(at: i)
        workspaces[index].insert(focused, at: 0)

        retile()
        focused.hideOffscreen(WindowManager.screenRect(for: self.screen))

        if let next = workspaces[active].first {
            next.focus()
        }
    }

    func insertWindow(_ window: TrackedWindow) {
        for ws in workspaces where ws.contains(window) { return }
        workspaces[active].insert(window, at: 0)
    }

    func addWindow(_ window: TrackedWindow) {
        insertWindow(window)
        scheduleRetile()
    }

    @discardableResult
    func removeFromActive(_ window: TrackedWindow) -> Bool {
        guard let i = workspaces[active].firstIndex(of: window) else { return false }
        workspaces[active].remove(at: i)
        return true
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
        let target = windows[(i + offset + windows.count) % windows.count]
        target.focus()
        if layouts[active] == .monocle {
            target.raise()
        }
    }

    func swapMaster() {
        guard workspaces[active].count > 1 else { return }
        guard let focused = WindowManager.focusedWindow(),
              let i = workspaces[active].firstIndex(of: focused),
              i != 0
        else { return }
        workspaces[active].swapAt(0, i)
        retile()
        workspaces[active][0].focus()
    }

    func toggleLayout() {
        layouts[active] = layouts[active] == .tile ? .monocle : .tile
        retile()
        if layouts[active] == .monocle, let focused = WindowManager.focusedWindow(),
           workspaces[active].contains(focused) {
            focused.raise()
        }
    }

    private func scheduleRetile() {
        guard !retileScheduled else { return }
        retileScheduled = true
        DispatchQueue.main.async { [self] in
            retileScheduled = false
            retile()
        }
    }

    @discardableResult
    func retile() -> CGRect {
        workspaces[active].removeAll { !$0.isTileable() }
        let screen = WindowManager.screenFrame(for: self.screen)
        Tiler.tile(windows: workspaces[active], screen: screen, layout: layouts[active])
        return screen
    }

    package func resizeWorkspaces(to count: Int) {
        let old = workspaces.count
        guard count != old else { return }

        if count > old {
            workspaces.append(contentsOf: Array(repeating: [], count: count - old))
            layouts.append(contentsOf: Array(repeating: .tile, count: count - old))
        } else {
            let overflow = workspaces[count..<old].joined()
            workspaces.removeSubrange(count...)
            layouts.removeSubrange(count...)
            if active >= count {
                active = count - 1
            }
            if previousActive >= count {
                previousActive = active
            }
            workspaces[active].append(contentsOf: overflow)
        }
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
                win.setPosition(center)
                win.setSize(size)
            }
        }
    }
}
