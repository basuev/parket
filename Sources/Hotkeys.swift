import Carbon
import Cocoa

package enum HotkeyStatus: String, Equatable {
    case stopped
    case running
    case degraded
}

@MainActor
package final class Hotkeys {
    package static let shared = Hotkeys()

    private static let signature = OSType(0x7072_6b74)

    private var handler: EventHandlerRef?
    private var registered: [EventHotKeyRef] = []
    private var actions: [UInt32: HotkeyAction] = [:]

    package private(set) var status: HotkeyStatus = .stopped
    package private(set) var skippedBindings: [SkippedHotkey] = []
    package private(set) var failedRegistrations: [FailedHotkeyRegistration] = []
    package private(set) var handlerInstallStatus: Int32?

    package var isRunning: Bool { status != .stopped }
    package var issueCount: Int {
        skippedBindings.count + failedRegistrations.count + (handlerInstallStatus == nil ? 0 : 1)
    }

    private init() {}

    package func start() {
        guard status == .stopped else { return }
        registerCurrentConfig()
    }

    package func reload() {
        stop()
        registerCurrentConfig()
    }

    package func stop() {
        for ref in registered {
            UnregisterEventHotKey(ref)
        }
        registered.removeAll()
        actions.removeAll()
        if let handler {
            RemoveEventHandler(handler)
        }
        handler = nil
        status = .stopped
        skippedBindings = []
        failedRegistrations = []
        handlerInstallStatus = nil
    }

    package func diagnosticLines() -> [String] {
        var lines: [String] = [
            "hotkeys: \(status.rawValue)",
            "hotkey_issue_count: \(issueCount)",
        ]

        if let handlerInstallStatus {
            lines.append("hotkey_backend_status: \(handlerInstallStatus)")
        }

        for skipped in skippedBindings {
            let kept = skipped.keptLabel.map { " kept=\($0)" } ?? ""
            lines.append(
                "hotkey_skipped: \(skipped.skippedLabel) \(skipped.chord.diagnosticText) reason=\(skipped.reason.rawValue)\(kept)"
            )
        }

        for failure in failedRegistrations {
            lines.append(
                "hotkey_failed: \(failure.label) \(failure.chord.diagnosticText) osstatus=\(failure.osStatus)"
            )
        }

        return lines
    }

    private func registerCurrentConfig() {
        let plan = HotkeyPlanner.plan(config: Config.shared)
        skippedBindings = plan.skipped
        failedRegistrations = []
        handlerInstallStatus = nil

        let installStatus = installHandler()
        guard installStatus == noErr else {
            handlerInstallStatus = installStatus
            status = .degraded
            return
        }

        for registration in plan.registrations {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: registration.id)
            let osStatus = RegisterEventHotKey(
                UInt32(registration.chord.key),
                registration.chord.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                UInt32(kEventHotKeyExclusive),
                &ref
            )

            if osStatus == noErr, let ref {
                registered.append(ref)
                actions[registration.id] = registration.action
            } else {
                failedRegistrations.append(
                    FailedHotkeyRegistration(
                        chord: registration.chord,
                        label: registration.diagnosticLabel,
                        osStatus: osStatus
                    )
                )
            }
        }

        if issueCount > 0 || registered.isEmpty {
            status = .degraded
        } else {
            status = .running
        }
    }

    private func installHandler() -> Int32 {
        guard handler == nil else { return noErr }
        var eventSpec = EventTypeSpec(
            eventClass: UInt32(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        return InstallEventHandler(
            GetApplicationEventTarget(),
            Self.carbonCallback,
            1,
            &eventSpec,
            nil,
            &handler
        )
    }

    private static let carbonCallback: EventHandlerUPP = { _, event, _ in
        guard let event else { return noErr }

        var hotKeyID = EventHotKeyID()
        let status = withUnsafeMutablePointer(to: &hotKeyID) { pointer in
            GetEventParameter(
                event,
                UInt32(kEventParamDirectObject),
                UInt32(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                pointer
            )
        }
        guard status == noErr else { return status }

        let id = hotKeyID.id
        let startedAt = ProcessInfo.processInfo.systemUptime

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                Hotkeys.shared.perform(id: id, startedAt: startedAt)
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    Hotkeys.shared.perform(id: id, startedAt: startedAt)
                }
            }
        }
        return noErr
    }

    private func perform(id: UInt32, startedAt: TimeInterval) {
        guard let action = actions[id] else { return }
        PerformanceTelemetry.traceAction(
            action.traceName,
            startedAt: startedAt,
            metadata: action.traceMetadata
        ) {
            perform(action)
        }
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .switchWorkspace(let index):
            WorkspaceManager.shared.switchTo(index)
        case .moveWorkspace(let index):
            WorkspaceManager.shared.moveActiveWindowTo(index)
        case .focusMonitor(let offset):
            WorkspaceManager.shared.focusMonitor(offset: offset)
        case .moveWindowToMonitor(let offset):
            WorkspaceManager.shared.moveWindowToMonitor(offset: offset)
        case .switchToLastWorkspace:
            WorkspaceManager.shared.switchToLast()
        case .focusNext:
            WorkspaceManager.shared.focusNext()
        case .focusPrev:
            WorkspaceManager.shared.focusPrev()
        case .swapMaster:
            WorkspaceManager.shared.swapMaster()
        case .toggleLayout:
            WorkspaceManager.shared.toggleLayout()
        case .customCommand(_, let command):
            run(command)
        }
    }

    private func run(_ command: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            try? process.run()
        }
    }
}

extension HotkeyChord {
    fileprivate var carbonModifiers: UInt32 {
        var flags: UInt32
        switch modifier {
        case .command:
            flags = UInt32(cmdKey)
        case .option:
            flags = UInt32(optionKey)
        case .control:
            flags = UInt32(controlKey)
        }
        if shift {
            flags |= UInt32(shiftKey)
        }
        return flags
    }
}
