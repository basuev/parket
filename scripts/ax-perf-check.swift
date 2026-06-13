import AppKit
import ApplicationServices
import Darwin

func fail(_ message: String) -> Never {
    fputs("ax-perf-check: \(message)\n", stderr)
    exit(1)
}

func attribute(_ element: AXUIElement, _ name: CFString) -> AnyObject? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

func isStandardWindow(_ element: AXUIElement) -> Bool {
    let role = attribute(element, kAXRoleAttribute as CFString) as? String ?? ""
    let subrole = attribute(element, kAXSubroleAttribute as CFString) as? String ?? ""
    let minimized = attribute(element, kAXMinimizedAttribute as CFString) as? Bool ?? false
    let fullscreen = attribute(element, "AXFullScreen" as CFString) as? Bool ?? false
    return role == kAXWindowRole && subrole == kAXStandardWindowSubrole && !minimized && !fullscreen
}

guard AXIsProcessTrusted() else {
    fail("Accessibility is required")
}

guard
    !NSWorkspace.shared.runningApplications.filter({ $0.bundleIdentifier == "com.parket.harness" }).isEmpty
else {
    fail("ParketHarnessApp is not running")
}

let rawWindows = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.parket.harness" }
    .flatMap { app -> [AXUIElement] in
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        return attribute(appRef, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
    }

guard !rawWindows.isEmpty else {
    fail("could not read fixture windows")
}

let standardCount = rawWindows.filter(isStandardWindow).count
let expectedCount =
    ProcessInfo.processInfo.environment["PARKET_HARNESS_EXPECTED_STANDARD_COUNT"].flatMap(Int.init)
    ?? ProcessInfo.processInfo.environment["PARKET_HARNESS_WINDOW_COUNT"].flatMap(Int.init)
    ?? 27
guard standardCount >= expectedCount else {
    fail("expected at least \(expectedCount) standard fixture windows, got \(standardCount)")
}

print("ax-perf-check: standard=\(standardCount)")
