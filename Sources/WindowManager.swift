import AppKit
import ApplicationServices

struct TrackedWindow: Equatable {
    let element: AXUIElement
    let focusElement: AXUIElement
    let members: [AXUIElement]
    let pid: pid_t
    let group: WindowGroupKey

    private enum FocusIntent {
        case full
        case workspaceSwitch
    }

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
            guard WindowManager.shouldApplyPosition(point, to: member) else { continue }
            if WindowManager.setAttributeValue(member, kAXPositionAttribute as CFString, value) == .success {
                WindowManager.recordAppliedPosition(point, for: member)
            }
        }
    }

    @MainActor
    func setSize(_ size: CGSize) {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return }
        for member in members {
            guard WindowManager.shouldApplySize(size, to: member) else { continue }
            if WindowManager.setAttributeValue(member, kAXSizeAttribute as CFString, value) == .success {
                WindowManager.recordAppliedSize(size, for: member)
            }
        }
    }

    @MainActor
    func hideOffscreen(_ screen: CGRect) {
        let y = WindowManager.appliedPosition(for: element)?.y ?? screen.maxY - 1
        setPosition(CGPoint(x: screen.origin.x + 1 - screen.width, y: y))
    }

    @MainActor
    func setFrame(_ rect: CGRect) {
        setSize(rect.size)
        setPosition(rect.origin)
    }

    @MainActor
    func focus() {
        focus(intent: .full)
    }

    @MainActor
    func focusAfterWorkspaceSwitch() {
        focus(intent: .workspaceSwitch)
    }

    @MainActor
    private func focus(intent: FocusIntent) {
        let frontmost = PerformanceTelemetry.traceSubspan("frontmost_check") {
            WindowManager.isFrontmostApplication(pid: pid)
        }
        PerformanceTelemetry.traceSubspan("activate") {
            activateApplicationIfNeeded(frontmost: frontmost)
        }
        let focused = PerformanceTelemetry.traceSubspan("focused_window_read") {
            frontmost && WindowManager.isExpectedFocused(self) && WindowManager.isActuallyFocused(self)
        }
        PerformanceTelemetry.traceSubspan("raise") {
            if shouldRaise(frontmost: frontmost, focused: focused) {
                raise()
            }
        }
        PerformanceTelemetry.traceSubspan("explicit_focus_attrs") {
            if shouldApplyFocusAttributes(intent: intent, frontmost: frontmost) {
                applyFocusAttributes()
            }
        }
        WindowManager.recordExpectedFocus(self)
    }

    @MainActor
    private func activateApplicationIfNeeded(frontmost: Bool) {
        guard !frontmost else { return }
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
    }

    private func shouldRaise(frontmost: Bool, focused: Bool) -> Bool {
        guard frontmost else { return true }
        guard focused else { return true }
        return false
    }

    @MainActor
    private func applyFocusAttributes() {
        for target in TrackedWindow.unique([element, focusElement]) {
            WindowManager.setAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
            WindowManager.setAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
    }

    @MainActor
    func raise() {
        if WindowManager.performAction(element, kAXRaiseAction as CFString) == .success {
            WindowManager.recordExpectedFocus(self)
        }
    }

    @MainActor
    func isTileable() -> Bool {
        WindowManager.isTileable(element)
    }

    @MainActor
    func title() -> String? {
        var value: AnyObject?
        guard WindowManager.copyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else {
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

    private var requiresExplicitFocusAttributes: Bool {
        members.count > 1 || !CFEqual(element, focusElement)
    }

    private func shouldApplyFocusAttributes(intent: FocusIntent, frontmost: Bool) -> Bool {
        switch intent {
        case .full:
            return true
        case .workspaceSwitch:
            return requiresExplicitFocusAttributes || !frontmost
        }
    }
}

@MainActor
enum WindowManager {
    private struct AppliedGeometry {
        var position: CGPoint?
        var size: CGSize?
    }

    private static let appliedGeometryTolerance: CGFloat = 0.5
    private static var appliedGeometry: [CFHashCode: AppliedGeometry] = [:]
    private static var expectedFocusedWindow: TrackedWindow?

    static func isManagedApplication(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular else { return false }
        guard let bundleID = ProcessInfo.processInfo.environment["PARKET_MANAGED_BUNDLE_ID"],
            !bundleID.isEmpty
        else { return true }
        return app.bundleIdentifier == bundleID
    }

    static func allWindows() -> [TrackedWindow] {
        var result: [TrackedWindow] = []
        for app in NSWorkspace.shared.runningApplications {
            guard isManagedApplication(app) else { continue }
            let pid = app.processIdentifier
            let appRef = AXUIElementCreateApplication(pid)

            var windowsValue: AnyObject?
            guard copyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                let windows = windowsValue as? [AXUIElement]
            else { continue }

            result.append(contentsOf: trackedWindows(pid: pid, windows: windows))
        }
        return result
    }

    static func windows(pid: pid_t) -> [TrackedWindow]? {
        let appRef = AXUIElementCreateApplication(pid)

        var windowsValue: AnyObject?
        guard copyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
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
        guard isManagedApplication(frontApp) else { return nil }
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

    static func isFrontmostApplication(pid: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    static func recordExpectedFocus(_ window: TrackedWindow) {
        expectedFocusedWindow = window
    }

    static func clearExpectedFocus(pid: pid_t) {
        guard expectedFocusedWindow?.pid == pid else { return }
        expectedFocusedWindow = nil
    }

    static func clearExpectedFocus(_ window: TrackedWindow) {
        guard expectedFocusedWindow == window else { return }
        expectedFocusedWindow = nil
    }

    static func isExpectedFocused(_ window: TrackedWindow) -> Bool {
        guard let expected = expectedFocusedWindow else { return false }
        return expected.pid == window.pid && CFEqual(expected.focusElement, window.focusElement)
    }

    static func isActuallyFocused(_ window: TrackedWindow) -> Bool {
        guard let focused = focusedWindow(pid: window.pid) else { return false }
        return focused.pid == window.pid && CFEqual(focused.focusElement, window.focusElement)
    }

    private static func trackedWindow(_ appRef: AXUIElement, _ attribute: CFString, pid: pid_t) -> TrackedWindow? {
        var value: AnyObject?
        guard copyAttributeValue(appRef, attribute, &value) == .success,
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
        guard copyMultipleAttributeValues(element, attrs, .stopOnError, &values) == .success,
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

        guard copyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
            copyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success
        else { return false }

        let role = roleValue as? String
        let subrole = subroleValue as? String
        return role == kAXWindowRole && subrole == kAXStandardWindowSubrole
    }

    static func canonicalWindowElement(_ element: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        guard copyAttributeValue(element, kAXWindowAttribute as CFString, &value) == .success,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }

        let window = value as! AXUIElement
        guard isStandardWindow(window) else { return nil }
        return window
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?
        guard copyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
            copyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
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
        ScreenGeometry.convertRect(screen.visibleFrame, screens: screenDescriptors())
    }

    static func screenRect(for screen: NSScreen) -> CGRect {
        ScreenGeometry.convertRect(screen.frame, screens: screenDescriptors())
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    static func screenDescriptors() -> [ScreenDescriptor] {
        NSScreen.screens.map { screen in
            ScreenDescriptor(
                displayID: displayID(for: screen),
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                scale: screen.backingScaleFactor
            )
        }
    }

    static func screenTopologySignature() -> String {
        ScreenGeometry.topologySignature(screenDescriptors())
    }

    static func invalidateAppliedGeometry(_ window: TrackedWindow) {
        for member in window.members {
            invalidateAppliedGeometry(member)
        }
    }

    static func invalidateAppliedGeometry(_ element: AXUIElement) {
        appliedGeometry.removeValue(forKey: elementKey(element))
    }

    static func copyAttributeValue(
        _ element: AXUIElement,
        _ attribute: CFString,
        _ value: UnsafeMutablePointer<AnyObject?>
    ) -> AXError {
        PerformanceTelemetry.recordAXRead()
        return AXUIElementCopyAttributeValue(element, attribute, value)
    }

    static func copyMultipleAttributeValues(
        _ element: AXUIElement,
        _ attributes: CFArray,
        _ options: AXCopyMultipleAttributeOptions,
        _ values: UnsafeMutablePointer<CFArray?>
    ) -> AXError {
        PerformanceTelemetry.recordAXRead()
        return AXUIElementCopyMultipleAttributeValues(element, attributes, options, values)
    }

    @discardableResult
    static func setAttributeValue(_ element: AXUIElement, _ attribute: CFString, _ value: CFTypeRef) -> AXError {
        PerformanceTelemetry.recordAXWrite()
        return AXUIElementSetAttributeValue(element, attribute, value)
    }

    @discardableResult
    static func performAction(_ element: AXUIElement, _ action: CFString) -> AXError {
        PerformanceTelemetry.recordAXWrite()
        return AXUIElementPerformAction(element, action)
    }

    static func shouldApplyPosition(_ position: CGPoint, to element: AXUIElement) -> Bool {
        guard let current = appliedGeometry[elementKey(element)]?.position else { return true }
        return !pointsMatch(current, position)
    }

    static func shouldApplySize(_ size: CGSize, to element: AXUIElement) -> Bool {
        guard let current = appliedGeometry[elementKey(element)]?.size else { return true }
        return !sizesMatch(current, size)
    }

    static func recordAppliedPosition(_ position: CGPoint, for element: AXUIElement) {
        let key = elementKey(element)
        var geometry = appliedGeometry[key] ?? AppliedGeometry()
        geometry.position = position
        appliedGeometry[key] = geometry
    }

    static func appliedPosition(for element: AXUIElement) -> CGPoint? {
        appliedGeometry[elementKey(element)]?.position
    }

    static func recordAppliedSize(_ size: CGSize, for element: AXUIElement) {
        let key = elementKey(element)
        var geometry = appliedGeometry[key] ?? AppliedGeometry()
        geometry.size = size
        appliedGeometry[key] = geometry
    }

    private static func elementKey(_ element: AXUIElement) -> CFHashCode {
        CFHash(element)
    }

    private static func pointsMatch(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) <= appliedGeometryTolerance
            && abs(lhs.y - rhs.y) <= appliedGeometryTolerance
    }

    private static func sizesMatch(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) <= appliedGeometryTolerance
            && abs(lhs.height - rhs.height) <= appliedGeometryTolerance
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
