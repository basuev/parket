import Foundation

final class WorkspaceManager {
    static let shared = WorkspaceManager()

    private(set) var workspaces: [[TrackedWindow]] = Array(repeating: [], count: 9)
    private(set) var active: Int = 0

    private let offscreen = CGPoint(x: 10000, y: 10000)

    private init() {}

    func bootstrap() {
        let windows = WindowManager.allWindows()
        workspaces[0] = windows
        retile()
        StatusBar.shared.update()
    }

    func switchTo(_ index: Int) {
        guard index >= 0, index < 9, index != active else { return }

        for win in workspaces[active] {
            win.setPosition(offscreen)
        }

        active = index
        retile()

        if let master = workspaces[active].first {
            master.focus()
        }

        StatusBar.shared.update()
    }

    func moveActiveWindowTo(_ index: Int) {
        guard index >= 0, index < 9, index != active else { return }
        guard let focused = WindowManager.focusedWindow() else { return }

        guard let i = workspaces[active].firstIndex(of: focused) else { return }
        workspaces[active].remove(at: i)

        workspaces[index].insert(focused, at: 0)
        focused.setPosition(offscreen)

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
        for i in 0..<9 {
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
        for i in 0..<9 {
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
