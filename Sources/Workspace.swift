import Foundation

final class WorkspaceManager {
    static let shared = WorkspaceManager()

    private(set) var workspaces: [[TrackedWindow]] = Array(repeating: [], count: Config.workspaceCount)
    private(set) var active: Int = 0

    private init() {}

    func bootstrap() {
        let windows = WindowManager.allWindows()
        workspaces[0] = windows
        retile()
        StatusBar.shared.update()
    }

    func switchTo(_ index: Int) {
        guard index >= 0, index < Config.workspaceCount, index != active else { return }

        for win in workspaces[active] {
            win.hideOffscreen()
        }

        active = index
        retile()

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
        focused.hideOffscreen()

        retile()

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
        var needsRetile = false
        for i in 0..<Config.workspaceCount {
            let before = workspaces[i].count
            workspaces[i].removeAll { $0.pid == pid }
            if workspaces[i].count != before {
                needsRetile = needsRetile || (i == active)
            }
        }
        if needsRetile {
            retile()
        }
        StatusBar.shared.update()
    }

    func removeWindow(_ window: TrackedWindow) {
        var needsRetile = false
        for i in 0..<Config.workspaceCount {
            if let idx = workspaces[i].firstIndex(of: window) {
                workspaces[i].remove(at: idx)
                needsRetile = needsRetile || (i == active)
            }
        }
        if needsRetile {
            retile()
        }
        StatusBar.shared.update()
    }

    func focusNext() {
        let windows = workspaces[active]
        guard windows.count > 1 else { return }
        guard let focused = WindowManager.focusedWindow(),
              let i = windows.firstIndex(of: focused)
        else { return }
        let next = (i + 1) % windows.count
        windows[next].focus()
    }

    func focusPrev() {
        let windows = workspaces[active]
        guard windows.count > 1 else { return }
        guard let focused = WindowManager.focusedWindow(),
              let i = windows.firstIndex(of: focused)
        else { return }
        let prev = (i - 1 + windows.count) % windows.count
        windows[prev].focus()
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

    func retile() {
        workspaces[active].removeAll { !$0.isAlive() || !$0.isStandard() || $0.isMinimized() || $0.isFullscreen() }
        let screen = WindowManager.screenFrame()
        Tiler.tile(windows: workspaces[active], screen: screen)
    }

    func restoreAllWindows() {
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
