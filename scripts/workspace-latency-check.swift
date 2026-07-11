import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

struct SampleResult {
    let workspace: Int
    let round: Int
    let startedAt: UInt64
    let visibleLatency: Double
    let focusLatency: Double?
    let visiblePolls: Int
    let focusPolls: Int
    let expectedTitles: [String]
    let focusedTitle: String?
    let result: String
}

let keyCodes: [Int: CGKeyCode] = [
    1: 18,
    2: 19,
    3: 20,
    4: 21,
    5: 23,
    6: 22,
    7: 26,
    8: 28,
    9: 25,
]

func fail(_ message: String) -> Never {
    fputs("workspace-latency-check: \(message)\n", stderr)
    exit(1)
}

func value(after flag: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
        return nil
    }
    return args[index + 1]
}

func intValue(after flag: String, default defaultValue: Int) -> Int {
    value(after: flag).flatMap(Int.init) ?? defaultValue
}

func attribute(_ element: AXUIElement, _ name: CFString) -> AnyObject? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

func boolAttribute(_ element: AXUIElement, _ name: CFString) -> Bool {
    attribute(element, name) as? Bool ?? false
}

func title(of element: AXUIElement) -> String {
    attribute(element, kAXTitleAttribute as CFString) as? String ?? ""
}

func pointAttribute(_ element: AXUIElement, _ name: CFString) -> CGPoint? {
    guard let value = attribute(element, name),
        CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }

    var point = CGPoint.zero
    guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
    return point
}

func sizeAttribute(_ element: AXUIElement, _ name: CFString) -> CGSize? {
    guard let value = attribute(element, name),
        CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }

    var size = CGSize.zero
    guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
    return size
}

func frame(of element: AXUIElement) -> CGRect? {
    guard let position = pointAttribute(element, kAXPositionAttribute as CFString),
        let size = sizeAttribute(element, kAXSizeAttribute as CFString)
    else { return nil }
    return CGRect(origin: position, size: size)
}

func isStandardWindow(_ element: AXUIElement) -> Bool {
    let role = attribute(element, kAXRoleAttribute as CFString) as? String ?? ""
    let subrole = attribute(element, kAXSubroleAttribute as CFString) as? String ?? ""
    return role == kAXWindowRole
        && subrole == kAXStandardWindowSubrole
        && !boolAttribute(element, kAXMinimizedAttribute as CFString)
        && !boolAttribute(element, "AXFullScreen" as CFString)
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

func rawWindows(_ app: NSRunningApplication) -> [AXUIElement] {
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    return attribute(appElement, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
}

func standardWindows() -> [AXUIElement] {
    harnessApps().flatMap(rawWindows).filter(isStandardWindow)
}

func focusedWindowTitle(in app: NSRunningApplication) -> String? {
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    for name in [kAXFocusedUIElementAttribute, kAXFocusedWindowAttribute] {
        guard let value = attribute(appElement, name as CFString),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { continue }
        let window = canonicalWindow(value as! AXUIElement)
        guard isStandardWindow(window) else { continue }
        let windowTitle = title(of: window)
        if !windowTitle.isEmpty { return windowTitle }
    }
    return nil
}

func focusedWindowTitle() -> String? {
    guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
    guard harnessApps().contains(where: { $0.processIdentifier == frontmost.processIdentifier }) else {
        return nil
    }
    return focusedWindowTitle(in: frontmost)
}

func screenRectsInAXCoordinates() -> [CGRect] {
    let topEdge = NSScreen.screens.first?.frame.maxY ?? 1080
    return NSScreen.screens.map { screen in
        let frame = screen.frame
        return CGRect(
            x: frame.origin.x,
            y: topEdge - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}

func isOnscreen(_ rect: CGRect, screenRects: [CGRect]) -> Bool {
    guard rect.width > 1, rect.height > 1 else { return false }
    let center = CGPoint(x: rect.midX, y: rect.midY)
    return screenRects.contains { screen in
        screen.insetBy(dx: -8, dy: -8).contains(center)
    }
}

func onscreenTitles() -> [String] {
    let screenRects = screenRectsInAXCoordinates()
    let titles = standardWindows().compactMap { window -> String? in
        guard let frame = frame(of: window), isOnscreen(frame, screenRects: screenRects) else { return nil }
        let windowTitle = title(of: window)
        return windowTitle.isEmpty ? nil : windowTitle
    }
    return Array(Set(titles)).sorted()
}

func windowElementsByTitle() -> [String: AXUIElement] {
    var result: [String: AXUIElement] = [:]
    for window in standardWindows() {
        let windowTitle = title(of: window)
        guard !windowTitle.isEmpty else { continue }
        result[windowTitle] = window
    }
    return result
}

func containsAll(_ actual: [String], _ expected: [String]) -> Bool {
    let actualSet = Set(actual)
    return expected.allSatisfy { actualSet.contains($0) }
}

func post(number: Int, shift: Bool) {
    guard let keyCode = keyCodes[number] else {
        fail("unsupported workspace \(number)")
    }

    var flags: CGEventFlags = [.maskAlternate]
    if shift {
        flags.insert(.maskShift)
    }

    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    else {
        fail("could not create keyboard event")
    }

    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    usleep(2_000)
    up.post(tap: .cghidEventTap)
}

func elapsedMilliseconds(since start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

func expectedTitlesAreVisible(
    _ expected: [String],
    windowsByTitle: [String: AXUIElement],
    screenRects: [CGRect]
) -> Bool {
    expected.allSatisfy { expectedTitle in
        guard let window = windowsByTitle[expectedTitle], let windowFrame = frame(of: window) else { return false }
        return isOnscreen(windowFrame, screenRects: screenRects)
    }
}

func waitForVisibleTitles(
    _ expected: [String],
    windowsByTitle: [String: AXUIElement],
    timeoutMilliseconds: Int,
    pollMilliseconds: Int
) -> (Bool, Double, Int) {
    let start = DispatchTime.now().uptimeNanoseconds
    let pollDelay = useconds_t(max(1, pollMilliseconds) * 1000)
    let screenRects = screenRectsInAXCoordinates()
    var polls = 0

    repeat {
        polls += 1
        if expectedTitlesAreVisible(expected, windowsByTitle: windowsByTitle, screenRects: screenRects) {
            return (true, elapsedMilliseconds(since: start), polls)
        }
        usleep(pollDelay)
    } while elapsedMilliseconds(since: start) < Double(timeoutMilliseconds)

    return (false, elapsedMilliseconds(since: start), polls)
}

func waitForFocus(in expected: [String], timeoutMilliseconds: Int, pollMilliseconds: Int) -> (
    Bool, Double, Int, String?
) {
    let start = DispatchTime.now().uptimeNanoseconds
    let expectedSet = Set(expected)
    let pollDelay = useconds_t(max(1, pollMilliseconds) * 1000)
    var polls = 0
    var focused = focusedWindowTitle()

    repeat {
        polls += 1
        focused = focusedWindowTitle()
        if let focused, expectedSet.contains(focused) {
            return (true, elapsedMilliseconds(since: start), polls, focused)
        }
        usleep(pollDelay)
    } while elapsedMilliseconds(since: start) < Double(timeoutMilliseconds)

    return (false, elapsedMilliseconds(since: start), polls, focused)
}

func waitForFixtureWindowCount(_ expected: Int, timeoutMilliseconds: Int) {
    let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1000)
    var count = standardWindows().count
    while Date() < deadline {
        if count >= expected { return }
        usleep(100_000)
        count = standardWindows().count
    }
    fail("expected at least \(expected) standard fixture windows, got \(count)")
}

func write(_ text: String, to path: String?) {
    guard let path else {
        print(text)
        return
    }
    if path == "/dev/null" { return }
    let data = "\(text)\n".data(using: .utf8) ?? Data()
    let url = URL(fileURLWithPath: path)
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: url) else {
        fail("could not open output: \(path)")
    }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: data)
}

func encodeTSV(_ values: [String]) -> String {
    values.map {
        $0.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
    }.joined(separator: "\t")
}

func decodeTSV(_ value: String) -> String {
    var result = ""
    var escaped = false
    for char in value {
        if escaped {
            switch char {
            case "t": result.append("\t")
            case "n": result.append("\n")
            case "\\": result.append("\\")
            default:
                result.append("\\")
                result.append(char)
            }
            escaped = false
        } else if char == "\\" {
            escaped = true
        } else {
            result.append(char)
        }
    }
    if escaped { result.append("\\") }
    return result
}

func loadMap(path: String) -> [Int: [String]] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        fail("could not read map: \(path)")
    }

    var result: [Int: [String]] = [:]
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, let workspace = Int(first) else {
            fail("invalid map line: \(line)")
        }
        result[workspace] = parts.dropFirst().map(decodeTSV)
    }
    return result
}

func jsonString(_ value: String) -> String {
    var result = "\""
    for scalar in value.unicodeScalars {
        switch scalar {
        case "\"":
            result += "\\\""
        case "\\":
            result += "\\\\"
        case "\n":
            result += "\\n"
        case "\r":
            result += "\\r"
        case "\t":
            result += "\\t"
        case _ where scalar.value < 0x20:
            result += String(format: "\\u%04X", scalar.value)
        default:
            result.unicodeScalars.append(scalar)
        }
    }
    result += "\""
    return result
}

func jsonArray(_ values: [String]) -> String {
    "[\(values.map(jsonString).joined(separator: ","))]"
}

func jsonNumber(_ value: Double?) -> String {
    guard let value else { return "null" }
    return String(format: "%.3f", value)
}

func writeSample(_ sample: SampleResult, wm: String, scenario: String, output: String?) {
    let fields: [(String, String)] = [
        ("kind", jsonString("workspace_latency")),
        ("wm", jsonString(wm)),
        ("scenario", jsonString(scenario)),
        ("workspace", String(sample.workspace)),
        ("round", String(sample.round)),
        ("started_at_ns", String(sample.startedAt)),
        ("visible_latency_ms", jsonNumber(sample.visibleLatency)),
        ("focus_latency_ms", jsonNumber(sample.focusLatency)),
        ("visible_polls", String(sample.visiblePolls)),
        ("focus_polls", String(sample.focusPolls)),
        ("expected_titles", jsonArray(sample.expectedTitles)),
        ("focused_title", sample.focusedTitle.map(jsonString) ?? "null"),
        ("result", jsonString(sample.result)),
    ]
    write("{\(fields.map { "\(jsonString($0.0)):\($0.1)" }.joined(separator: ","))}", to: output)
}

func nativeTabToken(_ title: String) -> (base: String, suffix: Character)? {
    guard let suffix = title.last, suffix == "A" || suffix == "B" else { return nil }
    return (String(title.dropLast()), suffix)
}

func validateNativeTabGroups(_ captured: [(workspace: Int, titles: [String])]) {
    var groups: [String: (workspace: Int, suffixes: Set<Character>)] = [:]

    for entry in captured {
        for title in entry.titles {
            guard let token = nativeTabToken(title) else { continue }
            if let existing = groups[token.base] {
                guard existing.workspace == entry.workspace else {
                    fail("native tab group split across workspaces: \(token.base)")
                }
                var suffixes = existing.suffixes
                suffixes.insert(token.suffix)
                groups[token.base] = (existing.workspace, suffixes)
            } else {
                groups[token.base] = (entry.workspace, [token.suffix])
            }
        }
    }

    for (base, group) in groups {
        guard group.suffixes == ["A", "B"] else {
            fail("native tab group incomplete: \(base)")
        }
    }
}

func captureMap(
    workspaceCount: Int,
    expectedWindowCount: Int,
    expectedTitlesPerWorkspace: Int,
    settleMilliseconds: Int,
    requireNativeTabGroups: Bool,
    ignoreStableVisibleTitles: Bool,
    output: String?
) {
    waitForFixtureWindowCount(expectedWindowCount, timeoutMilliseconds: 5_000)

    var captured: [(workspace: Int, titles: [String])] = []
    for workspace in 1...workspaceCount {
        post(number: workspace, shift: false)
        usleep(useconds_t(max(0, settleMilliseconds) * 1000))
        let titles = onscreenTitles()
        guard !titles.isEmpty else {
            fail("workspace \(workspace) has no onscreen fixture windows")
        }
        captured.append((workspace, titles))
    }

    if ignoreStableVisibleTitles {
        var workspaceCounts: [String: Int] = [:]
        for entry in captured {
            for title in Set(entry.titles) {
                workspaceCounts[title, default: 0] += 1
            }
        }
        let stableTitles = Set(workspaceCounts.filter { $0.value == workspaceCount }.map(\.key))
        captured = captured.map { entry in
            (entry.workspace, entry.titles.filter { !stableTitles.contains($0) })
        }
    }

    var seen: Set<String> = []
    for entry in captured {
        guard !entry.titles.isEmpty else {
            fail("workspace \(entry.workspace) has no switching fixture windows")
        }
        if expectedTitlesPerWorkspace > 0, entry.titles.count != expectedTitlesPerWorkspace {
            fail(
                "workspace \(entry.workspace) has \(entry.titles.count) switching fixture windows, expected \(expectedTitlesPerWorkspace)"
            )
        }
        for windowTitle in entry.titles {
            guard !seen.contains(windowTitle) else {
                fail("window title appears on more than one workspace: \(windowTitle)")
            }
            seen.insert(windowTitle)
        }
    }

    if requireNativeTabGroups {
        validateNativeTabGroups(captured)
    }

    for entry in captured {
        write("\(entry.workspace)\t\(encodeTSV(entry.titles))", to: output)
    }
}

func runCycle(
    workspaceCount: Int,
    rounds: Int,
    delayMilliseconds: Int,
    timeoutMilliseconds: Int,
    pollMilliseconds: Int,
    startWorkspace: Int?,
    map: [Int: [String]],
    wm: String,
    scenario: String,
    output: String?
) {
    let sequence = workspaceCount > 1 ? Array(2...workspaceCount) + [1] : [1]
    let delay = useconds_t(max(0, delayMilliseconds) * 1000)
    let windowsByTitle = windowElementsByTitle()

    if let startWorkspace, let expectedTitles = map[startWorkspace] {
        post(number: startWorkspace, shift: false)
        _ = waitForVisibleTitles(
            expectedTitles,
            windowsByTitle: windowsByTitle,
            timeoutMilliseconds: timeoutMilliseconds,
            pollMilliseconds: pollMilliseconds
        )
        _ = waitForFocus(
            in: expectedTitles,
            timeoutMilliseconds: timeoutMilliseconds,
            pollMilliseconds: pollMilliseconds
        )
        usleep(delay)
    }

    for round in 1...rounds {
        for workspace in sequence {
            guard let expectedTitles = map[workspace], !expectedTitles.isEmpty else {
                fail("missing map entry for workspace \(workspace)")
            }

            let startedAt = DispatchTime.now().uptimeNanoseconds
            post(number: workspace, shift: false)
            let visible = waitForVisibleTitles(
                expectedTitles,
                windowsByTitle: windowsByTitle,
                timeoutMilliseconds: timeoutMilliseconds,
                pollMilliseconds: pollMilliseconds
            )
            let visibleLatency = elapsedMilliseconds(since: startedAt)
            let remaining = max(0, timeoutMilliseconds - Int(visibleLatency.rounded(.up)))
            let focus = waitForFocus(
                in: expectedTitles,
                timeoutMilliseconds: remaining,
                pollMilliseconds: pollMilliseconds
            )
            let result = visible.0 ? (focus.0 ? "ok" : "visible_only") : "timeout"
            let focusLatency = focus.0 ? elapsedMilliseconds(since: startedAt) : nil
            writeSample(
                SampleResult(
                    workspace: workspace,
                    round: round,
                    startedAt: startedAt,
                    visibleLatency: visibleLatency,
                    focusLatency: focusLatency,
                    visiblePolls: visible.2,
                    focusPolls: focus.2,
                    expectedTitles: expectedTitles,
                    focusedTitle: focus.3,
                    result: result
                ),
                wm: wm,
                scenario: scenario,
                output: output
            )
            usleep(delay)
        }
    }
}

guard AXIsProcessTrusted() else {
    fail("Accessibility is required")
}

guard !harnessApps().isEmpty else {
    fail("ParketHarnessApp is not running")
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fail("usage: workspace-latency-check.swift map|cycle [options]")
}

let command = args[1]
let workspaceCount = min(max(intValue(after: "--workspaces", default: 9), 1), 9)
let output = value(after: "--output")

switch command {
case "map":
    captureMap(
        workspaceCount: workspaceCount,
        expectedWindowCount: intValue(after: "--expected-window-count", default: 27),
        expectedTitlesPerWorkspace: intValue(after: "--expected-titles-per-workspace", default: 0),
        settleMilliseconds: intValue(after: "--settle-ms", default: 180),
        requireNativeTabGroups: CommandLine.arguments.contains("--require-native-tab-groups"),
        ignoreStableVisibleTitles: CommandLine.arguments.contains("--ignore-stable-visible-titles"),
        output: output
    )
case "cycle":
    guard let mapPath = value(after: "--map") else {
        fail("cycle requires --map")
    }
    runCycle(
        workspaceCount: workspaceCount,
        rounds: max(intValue(after: "--rounds", default: 20), 1),
        delayMilliseconds: intValue(after: "--delay-ms", default: 10),
        timeoutMilliseconds: intValue(after: "--timeout-ms", default: 1_500),
        pollMilliseconds: intValue(after: "--poll-ms", default: 2),
        startWorkspace: value(after: "--start-workspace").flatMap(Int.init),
        map: loadMap(path: mapPath),
        wm: value(after: "--wm") ?? "unknown",
        scenario: value(after: "--scenario") ?? "workspace-switch",
        output: output
    )
default:
    fail("usage: workspace-latency-check.swift map|cycle [options]")
}
