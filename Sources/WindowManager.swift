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

    func isFullscreen() -> Bool {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &value) == .success else {
            return false
        }
        return (value as? Bool) == true
    }

    func isMinimized() -> Bool {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &value) == .success else {
            return false
        }
        return (value as? Bool) == true
    }

    func isStandard() -> Bool {
        WindowManager.isStandardWindow(element)
    }

    func isAlive() -> Bool {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success
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
                guard isStandardWindow(win) else { continue }
                let tw = TrackedWindow(element: win, pid: pid)
                if tw.isMinimized() || tw.isFullscreen() { continue }
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
        let full = screen.frame
        let visible = screen.visibleFrame

        let x = visible.origin.x
        let y = full.height - visible.origin.y - visible.height
        return CGRect(x: x, y: y, width: visible.width, height: visible.height)
    }
}
