import ApplicationServices

struct WindowLocation: Equatable, Sendable {
    let monitorIndex: Int
    let workspaceIndex: Int
    let windowIndex: Int
}

struct RemovedWindowRecord {
    let window: TrackedWindow
    let location: WindowLocation
    let wasFocused: Bool
}

@MainActor
final class ShadowWindowRegistry {
    private struct Entry {
        let window: TrackedWindow
        let location: WindowLocation
    }

    private var entriesByPID: [pid_t: [Entry]] = [:]
    private var focusedEntry: Entry?

    init() {}

    func rebuild(from monitors: [Monitor]) {
        var next: [pid_t: [Entry]] = [:]
        for monitorIndex in monitors.indices {
            let monitor = monitors[monitorIndex]
            for workspaceIndex in monitor.workspaces.indices {
                for windowIndex in monitor.workspaces[workspaceIndex].indices {
                    let window = monitor.workspaces[workspaceIndex][windowIndex]
                    let location = WindowLocation(
                        monitorIndex: monitorIndex,
                        workspaceIndex: workspaceIndex,
                        windowIndex: windowIndex
                    )
                    next[window.pid, default: []].append(Entry(window: window, location: location))
                }
            }
        }
        entriesByPID = next
        guard let focusedEntry else { return }
        self.focusedEntry = locate(focusedEntry.window).map {
            Entry(window: focusedEntry.window, location: $0)
        }
    }

    func reconcile(pid: pid_t, from monitors: [Monitor]) {
        entriesByPID[pid] = entries(in: monitors).filter { $0.window.pid == pid }
        guard let focused = focusedEntry, focused.window.pid == pid else { return }
        focusedEntry = entriesByPID[pid]?.first { $0.window == focused.window }
    }

    func upsert(_ window: TrackedWindow, at location: WindowLocation) {
        entriesByPID[window.pid, default: []].removeAll { $0.window == window }
        entriesByPID[window.pid, default: []].append(Entry(window: window, location: location))
        guard focusedEntry?.window == window else { return }
        focusedEntry = Entry(window: window, location: location)
    }

    func remove(_ window: TrackedWindow) {
        entriesByPID[window.pid]?.removeAll { $0.window == window }
        if focusedEntry?.window == window {
            focusedEntry = nil
        }
    }

    func remove(pid: pid_t, element: AXUIElement) -> RemovedWindowRecord? {
        guard let entry = entriesByPID[pid]?.first(where: { $0.window.containsElement(element) }) else {
            return nil
        }
        let wasFocused = focusedEntry?.window == entry.window
        remove(entry.window)
        return RemovedWindowRecord(window: entry.window, location: entry.location, wasFocused: wasFocused)
    }

    func remove(pid: pid_t) {
        entriesByPID.removeValue(forKey: pid)
        if focusedEntry?.window.pid == pid {
            focusedEntry = nil
        }
    }

    func recordFocus(_ window: TrackedWindow, at location: WindowLocation) {
        focusedEntry = Entry(window: window, location: location)
        upsert(window, at: location)
    }

    func locate(_ window: TrackedWindow) -> WindowLocation? {
        entriesByPID[window.pid]?.first { $0.window == window }?.location
    }

    func locate(pid: pid_t, element: AXUIElement) -> WindowLocation? {
        entriesByPID[pid]?.first { $0.window.containsElement(element) }?.location
    }

    func singleTrackedWindow(pid: pid_t) -> (window: TrackedWindow, location: WindowLocation)? {
        guard let entries = entriesByPID[pid] else { return nil }
        var result: Entry?
        for entry in entries {
            guard entry.window.isTileable() else { continue }
            guard result == nil else { return nil }
            result = entry
        }
        guard let result else { return nil }
        return (result.window, result.location)
    }

    private func entries(in monitors: [Monitor]) -> [Entry] {
        var result: [Entry] = []
        for monitorIndex in monitors.indices {
            let monitor = monitors[monitorIndex]
            for workspaceIndex in monitor.workspaces.indices {
                for windowIndex in monitor.workspaces[workspaceIndex].indices {
                    let window = monitor.workspaces[workspaceIndex][windowIndex]
                    let location = WindowLocation(
                        monitorIndex: monitorIndex,
                        workspaceIndex: workspaceIndex,
                        windowIndex: windowIndex
                    )
                    result.append(Entry(window: window, location: location))
                }
            }
        }
        return result
    }
}
