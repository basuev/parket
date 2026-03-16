import AppKit

package final class Monitor {
    let displayID: CGDirectDisplayID
    var screen: NSScreen
    var workspaces: [[TrackedWindow]] = Array(repeating: [], count: Config.workspaceCount)
    var layouts: [Layout] = Array(repeating: .tile, count: Config.workspaceCount)
    var active: Int = 0

    init(displayID: CGDirectDisplayID, screen: NSScreen) {
        self.displayID = displayID
        self.screen = screen
    }

    func switchTo(_ index: Int) {
        guard index >= 0, index < Config.workspaceCount, index != active else { return }

        let previous = active
        active = index
        let screen = retile()

        for win in workspaces[previous] {
            win.hideInCorner(screen)
        }

        if let master = workspaces[active].first {
            master.focus()
        }
    }

    func moveActiveWindowTo(_ index: Int) {
        guard index >= 0, index < Config.workspaceCount, index != active else { return }
        guard let focused = WindowManager.focusedWindow() else { return }

        guard let i = workspaces[active].firstIndex(of: focused) else { return }
        workspaces[active].remove(at: i)
        workspaces[index].insert(focused, at: 0)

        let screen = retile()
        focused.hideInCorner(screen)

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
        retile()
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
        for i in 0..<Config.workspaceCount {
            let before = workspaces[i].count
            workspaces[i].removeAll(where: predicate)
            if workspaces[i].count != before {
                changed = true
                needsRetile = needsRetile || (i == active)
            }
        }
        if changed && needsRetile { retile() }
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

    @discardableResult
    func retile() -> CGRect {
        workspaces[active].removeAll { !$0.isTileable() }
        let screen = WindowManager.screenFrame(for: self.screen)
        Tiler.tile(windows: workspaces[active], screen: screen, layout: layouts[active])
        return screen
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
