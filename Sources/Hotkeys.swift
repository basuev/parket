import Cocoa
import ApplicationServices

package final class Hotkeys {
    package static let shared = Hotkeys()

    private static let numberKeys: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5,
        22: 6, 26: 7, 28: 8, 25: 9
    ]

    private var tap: CFMachPort?

    private init() {}

    package func start() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Hotkeys.callback,
            userInfo: nil
        ) else {
            fputs("tatami: failed to create event tap (check Input Monitoring permission)\n", stderr)
            exit(1)
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private static let callback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = Hotkeys.shared.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        let hasModifier = flags.contains(Config.modifier)
        let hasShift = flags.contains(.maskShift)
        let hasCmd = flags.contains(.maskCommand)
        let hasCtrl = flags.contains(.maskControl)

        guard hasModifier, !hasCmd, !hasCtrl else {
            return Unmanaged.passRetained(event)
        }

        for binding in Config.customBindings {
            guard binding.key == keyCode, binding.shift == hasShift else { continue }
            let cmd = binding.command
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", cmd]
                try? process.run()
            }
            return nil
        }

        if let number = numberKeys[keyCode] {
            let index = number - 1
            DispatchQueue.main.async {
                if hasShift {
                    WorkspaceManager.shared.moveActiveWindowTo(index)
                } else {
                    WorkspaceManager.shared.switchTo(index)
                }
            }
            return nil
        }

        if keyCode == Key.comma || keyCode == Key.period {
            let offset = keyCode == Key.comma ? -1 : 1
            DispatchQueue.main.async {
                if hasShift {
                    WorkspaceManager.shared.moveWindowToMonitor(offset: offset)
                } else {
                    WorkspaceManager.shared.focusMonitor(offset: offset)
                }
            }
            return nil
        }

        guard !hasShift else { return Unmanaged.passRetained(event) }

        switch keyCode {
        case 38:
            DispatchQueue.main.async { WorkspaceManager.shared.focusNext() }
            return nil
        case 40:
            DispatchQueue.main.async { WorkspaceManager.shared.focusPrev() }
            return nil
        case 36:
            DispatchQueue.main.async { WorkspaceManager.shared.swapMaster() }
            return nil
        case 46:
            DispatchQueue.main.async { WorkspaceManager.shared.toggleLayout() }
            return nil
        default:
            return Unmanaged.passRetained(event)
        }
    }
}
