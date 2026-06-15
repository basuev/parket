package enum WorkspaceBounds {
    package static let minimumCount = 1
    package static let maximumCount = 9

    package static func isValidCount(_ count: Int) -> Bool {
        count >= minimumCount && count <= maximumCount
    }

    package static func clampedCount(_ count: Int) -> Int {
        min(max(count, minimumCount), maximumCount)
    }

    package static func isValidIndex(_ index: Int, count: Int) -> Bool {
        index >= 0 && index < count
    }
}

package struct WorkspaceState: Equatable, Sendable {
    package private(set) var count: Int
    package private(set) var active: Int
    package private(set) var previousActive: Int

    package init(count: Int = WorkspaceBounds.maximumCount, active: Int = 0, previousActive: Int = 0) {
        self.count = WorkspaceBounds.clampedCount(count)
        self.active = min(max(active, 0), self.count - 1)
        self.previousActive = min(max(previousActive, 0), self.count - 1)
    }

    @discardableResult
    package mutating func switchTo(_ index: Int) -> Bool {
        guard WorkspaceBounds.isValidIndex(index, count: count), index != active else { return false }
        previousActive = active
        active = index
        return true
    }

    package mutating func resize(to count: Int) {
        self.count = WorkspaceBounds.clampedCount(count)
        if active >= self.count {
            active = self.count - 1
        }
        if previousActive >= self.count {
            previousActive = active
        }
    }
}

struct ClosedWindowFocusRepair: Equatable, Sendable {
    let location: WindowLocation

    init?(
        removedLocation: WindowLocation,
        focusedMonitorIndex: Int,
        activeWorkspaceIndex: Int,
        focusedWindowIndex: Int,
        wasFocused: Bool
    ) {
        guard activeWorkspaceIndex == removedLocation.workspaceIndex else { return nil }
        guard
            wasFocused
                || (focusedMonitorIndex == removedLocation.monitorIndex
                    && focusedWindowIndex == removedLocation.windowIndex)
        else { return nil }
        location = removedLocation
    }

    static func targetIndex(removedWindowIndex: Int, remainingCount: Int) -> Int? {
        guard remainingCount > 0 else { return nil }
        return min(max(removedWindowIndex, 0), remainingCount - 1)
    }
}

struct WorkspacePlacementTarget: Equatable, Hashable, Sendable {
    let monitorIndex: Int
    let workspaceIndex: Int
}

enum NewWindowPlacement {
    static func target(
        existingAppWindows: [WorkspacePlacementTarget],
        current: WorkspacePlacementTarget
    ) -> WorkspacePlacementTarget {
        guard let first = existingAppWindows.first else { return current }
        guard existingAppWindows.allSatisfy({ $0 == first }) else { return current }
        return first
    }
}

enum RemovedMonitorWindowMigration {
    static func targetWorkspace(
        sourceWorkspaceIndex: Int,
        sourceActive: Int,
        targetActive: Int,
        workspaceCount: Int
    ) -> Int {
        guard WorkspaceBounds.isValidIndex(sourceWorkspaceIndex, count: workspaceCount) else {
            return targetActive
        }
        guard sourceWorkspaceIndex != sourceActive else {
            return targetActive
        }
        return sourceWorkspaceIndex
    }
}

enum ScreenChangeEmptySnapshotPolicy {
    static func shouldDefer(
        windowsAreEmpty: Bool,
        hasTrackedWindows: Bool,
        isScreenChangeSettling: Bool
    ) -> Bool {
        windowsAreEmpty && hasTrackedWindows && isScreenChangeSettling
    }
}

enum PostSyncExternalFocusPolicy {
    static func shouldFollow(changed: Bool, closedWindow: Bool, repairedFocus: Bool) -> Bool {
        changed && !closedWindow && !repairedFocus
    }
}

package struct MonitorWorkspaceState<Element: Equatable>: Equatable {
    package private(set) var workspaces: [[Element]]
    package private(set) var layouts: [Layout]
    package private(set) var focusedIndices: [Int]
    package private(set) var active: Int
    package private(set) var previousActive: Int

    package init(
        workspaces: [[Element]],
        layouts: [Layout],
        focusedIndices: [Int],
        active: Int,
        previousActive: Int
    ) {
        self.workspaces = workspaces
        self.layouts = layouts
        self.focusedIndices = focusedIndices
        self.active = active
        self.previousActive = previousActive
    }

    package mutating func resize(to rawCount: Int) {
        let count = WorkspaceBounds.clampedCount(rawCount)
        let old = workspaces.count
        guard count != old else { return }

        if count > old {
            workspaces.append(contentsOf: Array(repeating: [], count: count - old))
            layouts.append(contentsOf: Array(repeating: .tile, count: count - old))
            focusedIndices.append(contentsOf: Array(repeating: 0, count: count - old))
        } else {
            let overflow = workspaces[count..<old].joined()
            workspaces.removeSubrange(count...)
            layouts.removeSubrange(count...)
            focusedIndices.removeSubrange(count...)
            if active >= count {
                active = count - 1
            }
            if previousActive >= count {
                previousActive = active
            }
            workspaces[active].append(contentsOf: overflow)
        }
    }
}
