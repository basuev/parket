import AppKit
import ApplicationServices
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    fputs("ax-focus-check: \(message)\n", stderr)
    exit(1)
}

func attribute(_ element: AXUIElement, _ name: CFString) -> AnyObject? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

func title(of element: AXUIElement) -> String {
    attribute(element, kAXTitleAttribute as CFString) as? String ?? ""
}

func isStandardWindow(_ element: AXUIElement) -> Bool {
    let role = attribute(element, kAXRoleAttribute as CFString) as? String ?? ""
    let subrole = attribute(element, kAXSubroleAttribute as CFString) as? String ?? ""
    let minimized = attribute(element, kAXMinimizedAttribute as CFString) as? Bool ?? false
    let fullscreen = attribute(element, "AXFullScreen" as CFString) as? Bool ?? false
    return role == kAXWindowRole && subrole == kAXStandardWindowSubrole && !minimized && !fullscreen
}

func canonicalWindow(_ element: AXUIElement) -> AXUIElement {
    guard let value = attribute(element, kAXWindowAttribute as CFString),
        CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return element }
    return value as! AXUIElement
}

func harnessApps() -> [NSRunningApplication] {
    let bundleID = ProcessInfo.processInfo.environment["PARKET_HARNESS_BUNDLE_ID"] ?? "com.parket.harness"
    return NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
}

func appRef(_ app: NSRunningApplication) -> AXUIElement {
    AXUIElementCreateApplication(app.processIdentifier)
}

func rawWindows(_ app: NSRunningApplication) -> [AXUIElement] {
    guard let windows = attribute(appRef(app), kAXWindowsAttribute as CFString) as? [AXUIElement] else {
        return []
    }
    return windows
}

func standardWindows() -> [AXUIElement] {
    harnessApps().flatMap(rawWindows).filter(isStandardWindow)
}

func focusedWindowTitle() -> String? {
    for app in harnessApps() {
        let appElement = appRef(app)
        for attributeName in [kAXFocusedUIElementAttribute, kAXFocusedWindowAttribute] {
            guard let value = attribute(appElement, attributeName as CFString),
                CFGetTypeID(value) == AXUIElementGetTypeID()
            else { continue }

            let window = canonicalWindow(value as! AXUIElement)
            guard isStandardWindow(window) else { continue }
            return title(of: window)
        }
    }
    return nil
}

func focusWindow(title targetTitle: String) {
    for app in harnessApps() {
        for window in rawWindows(app) where isStandardWindow(window) && title(of: window) == targetTitle {
            app.activate()
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            return
        }
    }
    fail("window not found: \(targetTitle)")
}

func closeWindow(title targetTitle: String) {
    for app in harnessApps() {
        for window in rawWindows(app) where isStandardWindow(window) && title(of: window) == targetTitle {
            guard let value = attribute(window, kAXCloseButtonAttribute as CFString),
                CFGetTypeID(value) == AXUIElementGetTypeID()
            else {
                fail("close button not found: \(targetTitle)")
            }
            let result = AXUIElementPerformAction(value as! AXUIElement, kAXPressAction as CFString)
            guard result == .success else {
                fail("close failed for \(targetTitle): \(result.rawValue)")
            }
            print("ax-focus-check: closed=\(targetTitle)")
            return
        }
    }
    fail("window not found: \(targetTitle)")
}

func expectFocusedTitle(_ expected: String, timeoutMilliseconds: Int) {
    let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1000)
    var lastTitle = focusedWindowTitle()

    while Date() < deadline {
        if lastTitle == expected {
            print("ax-focus-check: focused=\(expected)")
            return
        }
        usleep(50_000)
        lastTitle = focusedWindowTitle()
    }

    fail("expected focused \(expected), got \(lastTitle ?? "nil")")
}

func expectWindowCount(_ expected: Int, timeoutMilliseconds: Int) {
    let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1000)
    var count = standardWindows().count

    while Date() < deadline {
        if count >= expected {
            print("ax-focus-check: standard=\(count)")
            return
        }
        usleep(100_000)
        count = standardWindows().count
    }

    fail("expected at least \(expected) standard windows, got \(count)")
}

func intArgument(after flag: String, default defaultValue: Int) -> Int {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
        return defaultValue
    }
    return Int(args[index + 1]) ?? defaultValue
}

guard AXIsProcessTrusted() else {
    fail("Accessibility is required")
}

guard !harnessApps().isEmpty else {
    fail("ParketHarnessApp is not running")
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fail("usage: ax-focus-check.swift list|focus|close|expect|expect-count")
}

switch args[1] {
case "list":
    let titles = standardWindows().map(title).sorted()
    print("ax-focus-check: windows=\(titles.joined(separator: ",")) focused=\(focusedWindowTitle() ?? "nil")")
case "focus":
    guard args.count >= 3 else { fail("focus requires a title") }
    focusWindow(title: args[2])
    expectFocusedTitle(args[2], timeoutMilliseconds: intArgument(after: "--timeout-ms", default: 1500))
case "close":
    guard args.count >= 3 else { fail("close requires a title") }
    closeWindow(title: args[2])
case "expect":
    guard args.count >= 3 else { fail("expect requires a title") }
    expectFocusedTitle(args[2], timeoutMilliseconds: intArgument(after: "--timeout-ms", default: 1500))
case "expect-count":
    guard args.count >= 3, let expected = Int(args[2]) else {
        fail("expect-count requires a count")
    }
    expectWindowCount(expected, timeoutMilliseconds: intArgument(after: "--timeout-ms", default: 5000))
default:
    fail("usage: ax-focus-check.swift list|focus|close|expect|expect-count")
}
