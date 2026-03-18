import Foundation
import AppKit

package final class WorkspaceManager {
    package static let shared = WorkspaceManager()

    private(set) var monitors: [Monitor] = []
    private(set) var focusedMonitorIndex: Int = 0

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

    func addWindow(_ window: TrackedWindow) {
        for monitor in monitors where monitor.containsWindow(window) { return }
        focusedMonitor.addWindow(window)
        StatusBar.shared.update()
    }

    func removeWindow(pid: pid_t) {
        removeWindows { $0.pid == pid }
    }

    func removeWindow(_ window: TrackedWindow) {
        removeWindows { $0 == window }
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
        guard source.removeFromActive(focused) else { return }
        source.retile()

        let targetIndex = (focusedMonitorIndex + offset + monitors.count) % monitors.count
        let target = monitors[targetIndex]
        target.insertWindow(focused)
        target.retile()

        focusedMonitorIndex = targetIndex
        focused.focus()
        StatusBar.shared.update()
    }

    package func handleScreenChange() {
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
