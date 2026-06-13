import ApplicationServices

struct WindowLocation {
    let monitorIndex: Int
    let workspaceIndex: Int
    let windowIndex: Int
}

@MainActor
final class ShadowWindowRegistry {
    private struct Entry {
        let window: TrackedWindow
        let location: WindowLocation
    }

    private var entriesByPID: [pid_t: [Entry]] = [:]

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
}
