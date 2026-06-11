import AppKit
import ApplicationServices

struct TrackedWindow: Equatable {
    let element: AXUIElement
    let focusElement: AXUIElement
    let members: [AXUIElement]
    let pid: pid_t
    let group: WindowGroupKey

    @MainActor
    init(element: AXUIElement, pid: pid_t, members: [AXUIElement] = [], group: WindowGroupKey? = nil) {
        let window = WindowManager.canonicalWindowElement(element) ?? element
        self.element = window
        self.focusElement = element
        self.members = TrackedWindow.unique([window] + members)
        self.pid = pid
        self.group = group ?? WindowGroupKey(pid: pid, frame: WindowManager.frame(of: window) ?? .null)
    }

    static func == (lhs: TrackedWindow, rhs: TrackedWindow) -> Bool {
        if lhs.hasElement(rhs) {
            return true
        }
        return lhs.group == rhs.group
    }

    func hasElement(_ other: TrackedWindow) -> Bool {
        references.contains { left in
            other.references.contains { CFEqual(left, $0) }
        }
    }

    func hasSameMembers(_ other: TrackedWindow) -> Bool {
        members.count == other.members.count
            && members.allSatisfy { member in other.members.contains { CFEqual(member, $0) } }
    }

    func containsElement(_ element: AXUIElement) -> Bool {
        references.contains { CFEqual($0, element) }
    }

    @MainActor
    func getFrame() -> CGRect? {
        WindowManager.frame(of: element)
    }

    @MainActor
    func keepingMembers(from current: TrackedWindow) -> TrackedWindow {
        TrackedWindow(element: focusElement, pid: pid, members: current.members, group: group)
    }

    @MainActor
    func setPosition(_ point: CGPoint) {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return }
        for member in members {
            AXUIElementSetAttributeValue(member, kAXPositionAttribute as CFString, value)
        }
    }

    @MainActor
    func setSize(_ size: CGSize) {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return }
        for member in members {
            AXUIElementSetAttributeValue(member, kAXSizeAttribute as CFString, value)
        }
    }

    @MainActor
    func hideOffscreen(_ screen: CGRect) {
        setPosition(CGPoint(x: screen.origin.x + 1 - screen.width, y: screen.maxY - 1))
    }

    @MainActor
    func setFrame(_ rect: CGRect) {
        setPosition(rect.origin)
        setSize(rect.size)
    }

    @MainActor
    func focus() {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(focusElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(focusElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    @MainActor
    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    @MainActor
    func isTileable() -> Bool {
        WindowManager.isTileable(element)
    }

    @MainActor
    func title() -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func unique(_ elements: [AXUIElement]) -> [AXUIElement] {
        var result: [AXUIElement] = []
        for element in elements where !result.contains(where: { CFEqual($0, element) }) {
            result.append(element)
        }
        return result
    }

    private var references: [AXUIElement] {
        TrackedWindow.unique([element, focusElement] + members)
    }
}

@MainActor
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

            result.append(contentsOf: trackedWindows(pid: pid, windows: windows))
        }
        return result
    }

    static func windows(pid: pid_t) -> [TrackedWindow]? {
        let appRef = AXUIElementCreateApplication(pid)

        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
            let windows = windowsValue as? [AXUIElement]
        else { return nil }

        return trackedWindows(pid: pid, windows: windows)
    }

    static func trackedWindows(pid: pid_t, windows: [AXUIElement]) -> [TrackedWindow] {
        let candidates = windows.compactMap { WindowCandidate(element: $0, pid: pid) }
        var result: [TrackedWindow] = []

        for candidate in candidates {
            let related =
                candidates
                .filter { candidate.matches($0) }
                .map(\.window)
            let window = TrackedWindow(element: candidate.element, pid: pid, members: related, group: candidate.group)
            guard !result.contains(window) else { continue }
            result.append(window)
        }

        return result
    }

    static func focusedWindow() -> TrackedWindow? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier
        return focusedWindow(pid: pid)
    }

    static func focusedWindow(pid: pid_t) -> TrackedWindow? {
        let appRef = AXUIElementCreateApplication(pid)

        if let focused = trackedWindow(appRef, kAXFocusedUIElementAttribute as CFString, pid: pid) {
            return focused
        }
        return trackedWindow(appRef, kAXFocusedWindowAttribute as CFString, pid: pid)
    }

    private static func trackedWindow(_ appRef: AXUIElement, _ attribute: CFString, pid: pid_t) -> TrackedWindow? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, attribute, &value) == .success,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        let element = value as! AXUIElement
        let window = TrackedWindow(element: element, pid: pid)
        guard window.isTileable() else { return nil }
        return window
    }

    static func isTileable(_ element: AXUIElement) -> Bool {
        let attrs =
            [
                kAXRoleAttribute,
                kAXSubroleAttribute,
                kAXMinimizedAttribute,
                "AXFullScreen",
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

    static func canonicalWindowElement(_ element: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value) == .success,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }

        let window = value as! AXUIElement
        guard isStandardWindow(window) else { return nil }
        return window
    }

    static func frame(of element: AXUIElement) -> CGRect? {
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

@MainActor
private struct WindowCandidate {
    let element: AXUIElement
    let window: AXUIElement
    let frame: CGRect
    let group: WindowGroupKey

    init?(element: AXUIElement, pid: pid_t) {
        let window = WindowManager.canonicalWindowElement(element) ?? element
        guard WindowManager.isTileable(window), let frame = WindowManager.frame(of: window) else { return nil }
        self.element = element
        self.window = window
        self.frame = frame
        self.group = WindowGroupKey(pid: pid, frame: frame)
    }

    func matches(_ other: WindowCandidate) -> Bool {
        WindowGrouping.matches(lhsGroup: group, lhsFrame: frame, rhsGroup: other.group, rhsFrame: other.frame)
    }
}
