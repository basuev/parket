import AppKit

@main
@MainActor
final class HarnessApp: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    static func main() {
        NSWindow.allowsAutomaticWindowTabbing = false
        let app = NSApplication.shared
        let delegate = HarnessApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
