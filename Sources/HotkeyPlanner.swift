package enum HotkeyAction: Equatable {
    case switchWorkspace(Int)
    case moveWorkspace(Int)
    case focusMonitor(Int)
    case moveWindowToMonitor(Int)
    case switchToLastWorkspace
    case focusNext
    case focusPrev
    case swapMaster
    case toggleLayout
    case customCommand(index: Int, command: String)

    package var diagnosticLabel: String {
        switch self {
        case .switchWorkspace(let index):
            return "switch_workspace_\(index + 1)"
        case .moveWorkspace(let index):
            return "move_workspace_\(index + 1)"
        case .focusMonitor(let offset):
            return offset < 0 ? "focus_monitor_prev" : "focus_monitor_next"
        case .moveWindowToMonitor(let offset):
            return offset < 0 ? "move_monitor_prev" : "move_monitor_next"
        case .switchToLastWorkspace:
            return "last_workspace"
        case .focusNext:
            return "focus_next"
        case .focusPrev:
            return "focus_prev"
        case .swapMaster:
            return "swap_master"
        case .toggleLayout:
            return "toggle_layout"
        case .customCommand(let index, _):
            return "custom#\(index)"
        }
    }

    package var traceName: String {
        switch self {
        case .switchWorkspace:
            return "workspace_switch"
        case .moveWorkspace:
            return "move_workspace"
        case .focusMonitor:
            return "focus_monitor"
        case .moveWindowToMonitor:
            return "move_monitor"
        case .switchToLastWorkspace:
            return "last_workspace"
        case .focusNext:
            return "focus_next"
        case .focusPrev:
            return "focus_prev"
        case .swapMaster:
            return "swap_master"
        case .toggleLayout:
            return "toggle_layout"
        case .customCommand:
            return "custom_command"
        }
    }

    package var traceMetadata: [String: Int] {
        switch self {
        case .switchWorkspace(let index), .moveWorkspace(let index):
            return ["target_workspace": index + 1]
        case .focusMonitor(let offset), .moveWindowToMonitor(let offset):
            return ["monitor_offset": offset]
        case .customCommand(let index, _):
            return ["custom_index": index]
        default:
            return [:]
        }
    }
}

package struct HotkeyChord: Hashable, Equatable {
    let modifier: HotkeyModifier
    let shift: Bool
    let key: UInt16

    package var diagnosticText: String {
        var parts = [modifier.rawValue]
        if shift {
            parts.append("shift")
        }
        parts.append(Key.name(for: key))
        return parts.joined(separator: "+")
    }
}

package struct PlannedHotkey: Equatable {
    let id: UInt32
    let chord: HotkeyChord
    let action: HotkeyAction

    package var diagnosticLabel: String {
        action.diagnosticLabel
    }
}

package enum HotkeySkipReason: String, Equatable {
    case duplicate
    case reserved
}

package struct SkippedHotkey: Equatable {
    let chord: HotkeyChord
    let skippedLabel: String
    let reason: HotkeySkipReason
    let keptLabel: String?
}

package struct FailedHotkeyRegistration: Equatable {
    let chord: HotkeyChord
    let label: String
    let osStatus: Int32
}

package struct HotkeyPlan: Equatable {
    let registrations: [PlannedHotkey]
    let skipped: [SkippedHotkey]
}

package enum HotkeyPlanner {
    package static func plan(config: Config) -> HotkeyPlan {
        var registrations: [PlannedHotkey] = []
        var skipped: [SkippedHotkey] = []
        var occupied: [HotkeyChord: PlannedHotkey] = [:]
        var nextID: UInt32 = 1

        func add(key: UInt16, shift: Bool, action: HotkeyAction) {
            let chord = HotkeyChord(modifier: config.modifier, shift: shift, key: key)
            if isReserved(chord) {
                skipped.append(
                    SkippedHotkey(
                        chord: chord,
                        skippedLabel: action.diagnosticLabel,
                        reason: .reserved,
                        keptLabel: nil
                    )
                )
                return
            }
            if let existing = occupied[chord] {
                skipped.append(
                    SkippedHotkey(
                        chord: chord,
                        skippedLabel: action.diagnosticLabel,
                        reason: .duplicate,
                        keptLabel: existing.diagnosticLabel
                    )
                )
                return
            }

            let registration = PlannedHotkey(id: nextID, chord: chord, action: action)
            registrations.append(registration)
            occupied[chord] = registration
            nextID += 1
        }

        for index in config.customBindings.indices {
            let binding = config.customBindings[index]
            add(
                key: binding.key,
                shift: binding.shift,
                action: .customCommand(index: index + 1, command: binding.command)
            )
        }

        let workspaceCount = max(0, min(config.workspaceCount, Key.numberKeys.count))
        for index in 0..<workspaceCount {
            let key = Key.numberKeys[index]
            add(key: key, shift: false, action: .switchWorkspace(index))
            add(key: key, shift: true, action: .moveWorkspace(index))
        }

        let bindings = config.bindings
        add(key: bindings.focusNext.key, shift: bindings.focusNext.shift, action: .focusNext)
        add(key: bindings.focusPrev.key, shift: bindings.focusPrev.shift, action: .focusPrev)
        add(key: bindings.swapMaster.key, shift: bindings.swapMaster.shift, action: .swapMaster)
        add(key: bindings.toggleLayout.key, shift: bindings.toggleLayout.shift, action: .toggleLayout)
        add(key: bindings.focusMonitorPrev.key, shift: bindings.focusMonitorPrev.shift, action: .focusMonitor(-1))
        add(key: bindings.focusMonitorNext.key, shift: bindings.focusMonitorNext.shift, action: .focusMonitor(1))
        add(key: bindings.moveMonitorPrev.key, shift: bindings.moveMonitorPrev.shift, action: .moveWindowToMonitor(-1))
        add(key: bindings.moveMonitorNext.key, shift: bindings.moveMonitorNext.shift, action: .moveWindowToMonitor(1))
        add(key: bindings.lastWorkspace.key, shift: bindings.lastWorkspace.shift, action: .switchToLastWorkspace)

        return HotkeyPlan(registrations: registrations, skipped: skipped)
    }

    private static func isReserved(_ chord: HotkeyChord) -> Bool {
        chord.modifier == .command && chord.key == Key.tab
    }
}
