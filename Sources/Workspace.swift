import Foundation

package final class WorkspaceManager {
    package static let shared = WorkspaceManager()

    private(set) var workspaces: [[TrackedWindow]] = Array(repeating: [], count: Config.workspaceCount)
    private(set) var layouts: [Layout] = Array(repeating: .tile, count: Config.workspaceCount)
    private(set) var active: Int = 0

    private init() {}

    package func bootstrap() {
        let windows = WindowManager.allWindows()
        workspaces[0] = windows
        retile()
        StatusBar.shared.update()
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

        StatusBar.shared.update()
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

        StatusBar.shared.update()
    }

    func addWindow(_ window: TrackedWindow) {
        for ws in workspaces where ws.contains(window) { return }

        workspaces[active].insert(window, at: 0)
        retile()
        StatusBar.shared.update()
    }

    func removeWindow(pid: pid_t) {
        removeWindows { $0.pid == pid }
    }

    func removeWindow(_ window: TrackedWindow) {
        removeWindows { $0 == window }
    }

    private func removeWindows(where predicate: (TrackedWindow) -> Bool) {
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
        guard changed else { return }
        if needsRetile { retile() }
        StatusBar.shared.update()
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
        StatusBar.shared.update()
    }

    @discardableResult
    func retile() -> CGRect {
        workspaces[active].removeAll { !$0.isTileable() }
        let screen = WindowManager.screenFrame()
        Tiler.tile(windows: workspaces[active], screen: screen, layout: layouts[active])
        return screen
    }

    package func restoreAllWindows() {
        let screen = WindowManager.screenFrame()
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
