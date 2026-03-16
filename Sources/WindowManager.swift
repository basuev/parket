import AppKit
import ApplicationServices

struct TrackedWindow: Equatable {
    let element: AXUIElement
    let pid: pid_t

    static func == (lhs: TrackedWindow, rhs: TrackedWindow) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func getFrame() -> CGRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    func setPosition(_ point: CGPoint) {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    func setSize(_ size: CGSize) {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }

    func hideInCorner(_ screen: CGRect) {
        let x = screen.origin.x - 5000
        let y = screen.origin.y + screen.height + 5000
        setPosition(CGPoint(x: x, y: y))
    }

    func setFrame(_ rect: CGRect) {
        setPosition(rect.origin)
        setSize(rect.size)
    }

    func focus() {
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
    }

    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    func isTileable() -> Bool {
        let attrs = [
            kAXRoleAttribute,
            kAXSubroleAttribute,
            kAXMinimizedAttribute,
            "AXFullScreen"
        ] as CFArray

        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attrs, .stopOnError, &values) == .success,
              let results = values as? [AnyObject], results.count == 4
        else { return false }

        let role = results[0] as? String
        let subrole = results[1] as? String
        let minimized = results[2] as? Bool ?? false
        let fullscreen = results[3] as? Bool ?? false

        return role == kAXWindowRole
            && subrole == kAXStandardWindowSubrole
            && !minimized
            && !fullscreen
    }

    func title() -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}

enum WindowManager {
    static func allWindows() -> [TrackedWindow] {
        var result: [TrackedWindow] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            let pid = app.processIdentifier
            let appRef = AXUIElementCreateApplication(pid)

            var windowsValue: AnyObject?
            guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let windows = windowsValue as? [AXUIElement]
            else { continue }

            for win in windows {
                let tw = TrackedWindow(element: win, pid: pid)
                guard tw.isTileable() else { continue }
                result.append(tw)
            }
        }
        return result
    }

    static func focusedWindow() -> TrackedWindow? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)

        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &value) == .success else {
            return nil
        }
        let win = value as! AXUIElement
        guard isStandardWindow(win) else { return nil }
        return TrackedWindow(element: win, pid: pid)
    }

    static func isStandardWindow(_ element: AXUIElement) -> Bool {
        var roleValue: AnyObject?
        var subroleValue: AnyObject?

        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success
        else { return false }

        let role = roleValue as? String
        let subrole = subroleValue as? String
        return role == kAXWindowRole && subrole == kAXStandardWindowSubrole
    }

    static func screenFrame() -> CGRect {
        guard let screen = NSScreen.main else {
            return CGRect(x: 0, y: 0, width: 1920, height: 1080)
        }
        return screenFrame(for: screen)
    }

    static func screenFrame(for screen: NSScreen) -> CGRect {
        convertRect(screen.visibleFrame)
    }

    static func screenRect(for screen: NSScreen) -> CGRect {
        convertRect(screen.frame)
    }

    private static func convertRect(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 1080
        return CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}
