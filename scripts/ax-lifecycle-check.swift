import AppKit
import ApplicationServices
import CoreGraphics
import Darwin

func fail(_ message: String) -> Never {
    fputs("ax-lifecycle-check: \(message)\n", stderr)
    exit(1)
}

func attribute(_ element: AXUIElement, _ name: CFString) -> AnyObject? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

func frame(of element: AXUIElement) -> CGRect? {
    guard let positionValue = attribute(element, kAXPositionAttribute as CFString),
        let sizeValue = attribute(element, kAXSizeAttribute as CFString),
        CFGetTypeID(positionValue) == AXValueGetTypeID(),
        CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else { return nil }

    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    else { return nil }
    return CGRect(origin: position, size: size)
}

func windows(pid: pid_t) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    return attribute(app, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
}

func title(of element: AXUIElement) -> String {
    attribute(element, kAXTitleAttribute as CFString) as? String ?? ""
}

func window(pid: pid_t, matchingTitle: String) -> AXUIElement? {
    windows(pid: pid).first { title(of: $0) == matchingTitle }
}

func waitUntil(_ body: () -> Bool) -> Bool {
    for _ in 0..<40 {
        if body() { return true }
        usleep(100_000)
    }
    return false
}

func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) <= 2
        && abs(lhs.origin.y - rhs.origin.y) <= 2
        && abs(lhs.width - rhs.width) <= 2
        && abs(lhs.height - rhs.height) <= 2
}

guard AXIsProcessTrusted() else {
    fail("Accessibility is required")
}

guard
    let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == "com.parket.harness"
    })
else {
    fail("ParketHarnessApp is not running")
}

let pid = app.processIdentifier
guard waitUntil({ window(pid: pid, matchingTitle: "Harness Delayed") != nil }),
    let delayed = window(pid: pid, matchingTitle: "Harness Delayed"),
    let delayedFrame = frame(of: delayed)
else {
    fail("delayed window did not appear")
}

guard abs(delayedFrame.width - 420) > 5 || abs(delayedFrame.height - 292) > 5 else {
    fail("delayed window was not adopted")
}

guard let minimized = window(pid: pid, matchingTitle: "Harness Minimized"),
    let minimizedFrame = frame(of: minimized)
else {
    fail("minimized fixture window is missing")
}

guard
    AXUIElementSetAttributeValue(
        minimized,
        kAXMinimizedAttribute as CFString,
        kCFBooleanFalse
    ) == .success
else {
    fail("could not restore minimized fixture window")
}

guard
    waitUntil({
        guard let restored = window(pid: pid, matchingTitle: "Harness Minimized"),
            let restoredFrame = frame(of: restored)
        else { return false }
        return !framesMatch(restoredFrame, minimizedFrame)
    })
else {
    fail("restored fixture window was not adopted")
}

guard let second = window(pid: pid, matchingTitle: "Harness Two") else {
    fail("tracked fixture window is missing")
}

let beforeMinimize = Dictionary(
    uniqueKeysWithValues: windows(pid: pid).compactMap { element -> (String, CGRect)? in
        let value = title(of: element)
        guard value != "Harness Two", let valueFrame = frame(of: element) else { return nil }
        return (value, valueFrame)
    }
)

guard
    AXUIElementSetAttributeValue(
        second,
        kAXMinimizedAttribute as CFString,
        kCFBooleanTrue
    ) == .success
else {
    fail("could not minimize tracked fixture window")
}

guard
    waitUntil({
        for element in windows(pid: pid) {
            let value = title(of: element)
            guard let previous = beforeMinimize[value], let current = frame(of: element) else { continue }
            if !framesMatch(previous, current) { return true }
        }
        return false
    })
else {
    fail("layout did not remove the minimized fixture window")
}

guard
    AXUIElementSetAttributeValue(
        second,
        kAXMinimizedAttribute as CFString,
        kCFBooleanFalse
    ) == .success
else {
    fail("could not restore tracked fixture window")
}

guard
    waitUntil({
        guard let restored = window(pid: pid, matchingTitle: "Harness Two") else { return false }
        return attribute(restored, kAXMinimizedAttribute as CFString) as? Bool == false
    })
else {
    fail("tracked fixture window did not leave the Dock")
}

print("ax-lifecycle-check: delayed, minimize, and deminimize passed")
