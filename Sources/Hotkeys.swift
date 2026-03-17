import Cocoa
import ApplicationServices

package final class Hotkeys {
    package static let shared = Hotkeys()

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

        let config = Config.shared
        let hasModifier = flags.contains(config.modifier)
        let hasShift = flags.contains(.maskShift)
        let hasExtraModifiers =
            (config.modifier != .maskCommand && flags.contains(.maskCommand)) ||
            (config.modifier != .maskControl && flags.contains(.maskControl)) ||
            (config.modifier != .maskAlternate && flags.contains(.maskAlternate))

        guard hasModifier, !hasExtraModifiers else {
            return Unmanaged.passRetained(event)
        }

        for binding in config.customBindings {
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

        if let number = config.numberKeys[keyCode] {
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

        let b = config.bindings

        if keyCode == b.focusMonitorPrev.key && hasShift == b.focusMonitorPrev.shift {
            DispatchQueue.main.async { WorkspaceManager.shared.focusMonitor(offset: -1) }
            return nil
        }
        if keyCode == b.focusMonitorNext.key && hasShift == b.focusMonitorNext.shift {
            DispatchQueue.main.async { WorkspaceManager.shared.focusMonitor(offset: 1) }
            return nil
        }
        if keyCode == b.moveMonitorPrev.key && hasShift == b.moveMonitorPrev.shift {
            DispatchQueue.main.async { WorkspaceManager.shared.moveWindowToMonitor(offset: -1) }
            return nil
        }
        if keyCode == b.moveMonitorNext.key && hasShift == b.moveMonitorNext.shift {
            DispatchQueue.main.async { WorkspaceManager.shared.moveWindowToMonitor(offset: 1) }
            return nil
        }
        if keyCode == b.lastWorkspace.key && hasShift == b.lastWorkspace.shift {
            DispatchQueue.main.async { WorkspaceManager.shared.switchToLast() }
            return nil
        }
        if keyCode == b.focusNext.key && hasShift == b.focusNext.shift {
            DispatchQueue.main.async { WorkspaceManager.shared.focusNext() }
            return nil
        }
        if keyCode == b.focusPrev.key && hasShift == b.focusPrev.shift {
            DispatchQueue.main.async { WorkspaceManager.shared.focusPrev() }
            return nil
        }
        if keyCode == b.swapMaster.key && hasShift == b.swapMaster.shift {
            DispatchQueue.main.async { WorkspaceManager.shared.swapMaster() }
            return nil
        }
        if keyCode == b.toggleLayout.key && hasShift == b.toggleLayout.shift {
            DispatchQueue.main.async { WorkspaceManager.shared.toggleLayout() }
            return nil
        }

        return Unmanaged.passRetained(event)
    }
}
