import AppKit
import ApplicationServices
import CoreGraphics
import Darwin

struct SmokeWindow {
    let title: String
    let role: String
    let subrole: String
    let minimized: Bool
    let fullscreen: Bool
    let frame: CGRect
}

func fail(_ message: String) -> Never {
    fputs("ax-smoke-check: \(message)\n", stderr)
    exit(1)
}

func attribute(_ element: AXUIElement, _ name: CFString) -> AnyObject? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

func frame(of element: AXUIElement) -> CGRect? {
    guard let posValue = attribute(element, kAXPositionAttribute as CFString),
        let sizeValue = attribute(element, kAXSizeAttribute as CFString)
    else { return nil }

    var position = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    return CGRect(origin: position, size: size)
}

func smokeWindow(_ element: AXUIElement) -> SmokeWindow? {
    guard let frame = frame(of: element) else { return nil }
    let title = attribute(element, kAXTitleAttribute as CFString) as? String ?? ""
    let role = attribute(element, kAXRoleAttribute as CFString) as? String ?? ""
    let subrole = attribute(element, kAXSubroleAttribute as CFString) as? String ?? ""
    let minimized = attribute(element, kAXMinimizedAttribute as CFString) as? Bool ?? false
    let fullscreen = attribute(element, "AXFullScreen" as CFString) as? Bool ?? false
    return SmokeWindow(
        title: title, role: role, subrole: subrole, minimized: minimized, fullscreen: fullscreen, frame: frame)
}

func convertedVisibleFrames() -> [CGRect] {
    let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 1080
    return NSScreen.screens.map { screen in
        let rect = screen.visibleFrame
        return CGRect(x: rect.origin.x, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

func intersectsVisibleScreen(_ frame: CGRect, visibleFrames: [CGRect]) -> Bool {
    visibleFrames.contains { !$0.intersection(frame).isNull }
}

guard AXIsProcessTrusted(), CGPreflightListenEventAccess() else {
    fail("Accessibility and Input Monitoring are required")
}

guard
    let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == "com.parket.harness"
    })
else {
    fail("ParketHarnessApp is not running")
}

let appRef = AXUIElementCreateApplication(app.processIdentifier)
guard let rawWindows = attribute(appRef, kAXWindowsAttribute as CFString) as? [AXUIElement] else {
    fail("could not read fixture windows")
}

let windows = rawWindows.compactMap(smokeWindow)
let standard = windows.filter {
    $0.role == kAXWindowRole && $0.subrole == kAXStandardWindowSubrole && !$0.minimized && !$0.fullscreen
}
let nonstandard = windows.filter {
    $0.role == kAXWindowRole && $0.subrole != kAXStandardWindowSubrole
}
let visibleFrames = convertedVisibleFrames()

guard standard.count >= 2 else {
    fail("expected at least two standard visible fixture windows, got \(standard.count)")
}

guard !nonstandard.isEmpty else {
    fail("expected at least one nonstandard fixture window")
}

for window in standard {
    guard intersectsVisibleScreen(window.frame, visibleFrames: visibleFrames) else {
        fail("standard window is offscreen: \(window.title)")
    }
}

print("ax-smoke-check: standard=\(standard.count) nonstandard=\(nonstandard.count)")
