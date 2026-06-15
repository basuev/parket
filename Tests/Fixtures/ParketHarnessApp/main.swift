import AppKit

@main
@MainActor
final class HarnessApp: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var churnWindows: [NSWindow] = []
    private var churnTimer: Timer?
    private var focusTimer: Timer?
    private var focusIndex = 0

    static func main() {
        NSWindow.allowsAutomaticWindowTabbing = false
        let app = NSApplication.shared
        let delegate = HarnessApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mode = ProcessInfo.processInfo.environment["PARKET_HARNESS_MODE"]
        if mode == "workspace-switch" {
            makeWorkspaceSwitchWindows()
            print("parket-harness-app ready pid=\(ProcessInfo.processInfo.processIdentifier)")
            fflush(stdout)
            return
        }

        if mode == "focus-check" {
            makeFocusCheckWindows()
            print("parket-harness-app ready pid=\(ProcessInfo.processInfo.processIdentifier)")
            fflush(stdout)
            return
        }

        if mode == "multi-monitor-close" {
            makeMultiMonitorCloseWindows()
            print("parket-harness-app ready pid=\(ProcessInfo.processInfo.processIdentifier)")
            fflush(stdout)
            return
        }

        let first = makeWindow(
            title: "Harness One", frame: NSRect(x: 120, y: 420, width: 640, height: 420), tabGroup: "tabs")
        let second = makeWindow(
            title: "Harness Two", frame: NSRect(x: 780, y: 420, width: 640, height: 420), tabGroup: "second")
        let tab = makeWindow(
            title: "Harness Tab", frame: NSRect(x: 120, y: 420, width: 640, height: 420), tabGroup: "tabs")
        first.addTabbedWindow(tab, ordered: .above)

        let minimized = makeWindow(
            title: "Harness Minimized", frame: NSRect(x: 260, y: 220, width: 480, height: 320), tabGroup: "minimized")
        minimized.miniaturize(nil)

        let panel = NSPanel(
            contentRect: NSRect(x: 520, y: 240, width: 360, height: 220),
            styleMask: [.titled, .utilityWindow, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Harness Panel"
        panel.setAccessibilitySubrole(.floatingWindow)
        panel.isReleasedWhenClosed = false
        panel.orderFront(nil)

        windows.append(contentsOf: [first, second, tab, minimized, panel])
        print("parket-harness-app ready pid=\(ProcessInfo.processInfo.processIdentifier)")
        fflush(stdout)
    }

    private func makeWorkspaceSwitchWindows() {
        let environment = ProcessInfo.processInfo.environment
        let count =
            environment["PARKET_HARNESS_WINDOW_COUNT"].flatMap(Int.init) ?? 27
        let titlePrefix = environment["PARKET_HARNESS_TITLE_PREFIX"] ?? "Harness Perf"
        let nativeTabs = environmentFlag("PARKET_HARNESS_NATIVE_TABS")
        let distributeScreens = environmentFlag("PARKET_HARNESS_DISTRIBUTE_SCREENS")
        let movingCount = environment["PARKET_HARNESS_MOVING_WINDOW_COUNT"].flatMap(Int.init) ?? 0

        for index in 0..<count {
            let frame = workspaceFrame(index: index, distributeScreens: distributeScreens, movingCount: movingCount)
            if nativeTabs {
                windows.append(
                    makeWindow(
                        title: "\(titlePrefix) \(index + 1)A",
                        frame: frame,
                        tabGroup: "perf-\(index + 1)"
                    )
                )
                windows.append(
                    makeWindow(
                        title: "\(titlePrefix) \(index + 1)B",
                        frame: frame,
                        tabGroup: "perf-\(index + 1)"
                    )
                )
            } else {
                windows.append(
                    makeWindow(
                        title: "\(titlePrefix) \(index + 1)",
                        frame: frame,
                        tabGroup: "perf-\(index + 1)"
                    )
                )
            }
        }

        if distributeScreens, movingCount > 0, windows.indices.contains(movingCount - 1) {
            windows[movingCount - 1].makeKeyAndOrderFront(nil)
        }

        if environmentFlag("PARKET_HARNESS_CHURN") {
            startChurn(titlePrefix: titlePrefix)
        }

        if environmentFlag("PARKET_HARNESS_FOCUS_THRASH") {
            startFocusThrash()
        }
    }

    private func makeFocusCheckWindows() {
        windows.append(
            makeWindow(
                title: "Focus Normal 1",
                frame: NSRect(x: 90, y: 460, width: 520, height: 320),
                tabGroup: "focus-normal-1"
            )
        )
        windows.append(
            makeWindow(
                title: "Focus Normal 2",
                frame: NSRect(x: 650, y: 460, width: 520, height: 320),
                tabGroup: "focus-normal-2"
            )
        )
        windows.append(
            makeWindow(
                title: "Focus Normal 3",
                frame: NSRect(x: 370, y: 120, width: 520, height: 320),
                tabGroup: "focus-normal-3"
            )
        )

        let nativeFrame = NSRect(x: 930, y: 120, width: 520, height: 320)
        windows.append(makeWindow(title: "Focus Native A", frame: nativeFrame, tabGroup: "focus-native"))
        windows.append(makeWindow(title: "Focus Native B", frame: nativeFrame, tabGroup: "focus-native"))
    }

    private func makeMultiMonitorCloseWindows() {
        let screens = NSScreen.screens
        let primary = NSScreen.main ?? screens[0]
        let secondary = screens.count > 1 ? screens.first { $0 !== primary } ?? screens[1] : primary

        windows.append(
            makeWindow(
                title: "Close Main",
                frame: closeFocusFrame(screen: primary, slot: 0),
                tabGroup: "close-main"
            )
        )
        windows.append(
            makeWindow(
                title: "Close Secondary Previous",
                frame: closeFocusFrame(screen: secondary, slot: 0),
                tabGroup: "close-secondary-previous"
            )
        )
        windows.append(
            makeWindow(
                title: "Close Secondary Active",
                frame: closeFocusFrame(screen: secondary, slot: 1),
                tabGroup: "close-secondary-active"
            )
        )
    }

    private func closeFocusFrame(screen: NSScreen, slot: Int) -> NSRect {
        let frame = screen.visibleFrame
        return NSRect(
            x: frame.minX + 70 + CGFloat(slot) * 96,
            y: frame.minY + 110 + CGFloat(slot) * 72,
            width: min(480, frame.width - 140),
            height: min(300, frame.height - 180)
        )
    }

    private func workspaceFrame(index: Int, distributeScreens: Bool, movingCount: Int = 0) -> NSRect {
        if distributeScreens, !NSScreen.screens.isEmpty {
            let screenCount = NSScreen.screens.count
            let backgroundScreenCount = max(screenCount - 1, 1)
            let screenIndex: Int
            let localIndex: Int
            if movingCount > 0 {
                if index >= movingCount && screenCount > 1 {
                    screenIndex = 1 + ((index - movingCount) % backgroundScreenCount)
                    localIndex = (index - movingCount) / backgroundScreenCount
                } else {
                    screenIndex = 0
                    localIndex = index
                }
            } else {
                screenIndex = index % screenCount
                localIndex = index / screenCount
            }
            let screen = NSScreen.screens[screenIndex]
            let frame = screen.visibleFrame
            let xRange = max(1, Int(frame.width - 540))
            let yRange = max(1, Int(frame.height - 420))
            return NSRect(
                x: frame.minX + 60 + CGFloat((localIndex * 67) % xRange),
                y: frame.minY + 80 + CGFloat((localIndex * 59) % yRange),
                width: min(420, frame.width - 120),
                height: min(260, frame.height - 160)
            )
        }

        let column = index % 9
        let row = index / 9
        return NSRect(
            x: 80 + CGFloat(column) * 90,
            y: 120 + CGFloat(row) * 80,
            width: 420,
            height: 260
        )
    }

    private func startChurn(titlePrefix: String) {
        churnTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.toggleChurnWindow(titlePrefix: titlePrefix)
            }
        }
    }

    private func toggleChurnWindow(titlePrefix: String) {
        if let window = churnWindows.popLast() {
            window.close()
            return
        }

        let index = windows.count + churnWindows.count + 1
        let window = makeWindow(
            title: "\(titlePrefix) Churn \(index)",
            frame: NSRect(x: 160, y: 180, width: 380, height: 240),
            tabGroup: "churn-\(index)"
        )
        churnWindows.append(window)
    }

    private func startFocusThrash() {
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.focusNextWindow()
            }
        }
    }

    private func focusNextWindow() {
        let candidates = windows.filter { $0.isVisible && !$0.title.contains("Churn") }
        guard !candidates.isEmpty else { return }
        focusIndex = (focusIndex + 1) % candidates.count
        candidates[focusIndex].makeKeyAndOrderFront(nil)
    }

    private func environmentFlag(_ name: String) -> Bool {
        guard let value = ProcessInfo.processInfo.environment[name]?.lowercased() else { return false }
        return value == "1" || value == "true" || value == "yes"
    }

    private func makeWindow(title: String, frame: NSRect, tabGroup: String) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.setAccessibilitySubrole(.standardWindow)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = tabGroup
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        return window
    }
}
