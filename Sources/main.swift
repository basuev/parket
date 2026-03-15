import AppKit
import ApplicationServices

func checkAccessibility() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

func setupCrashSafety() {
    let restore: @convention(c) (Int32) -> Void = { _ in
        WorkspaceManager.shared.restoreAllWindows()
        exit(0)
    }
    signal(SIGTERM, restore)
    signal(SIGINT, restore)
    atexit {
        WorkspaceManager.shared.restoreAllWindows()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard checkAccessibility() else {
    let alert = NSAlert()
    alert.messageText = "tatami requires Accessibility permission"
    alert.informativeText = "grant access in System Settings -> Privacy & Security -> Accessibility, then relaunch tatami."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "open System Settings")
    alert.addButton(withTitle: "quit")
    if alert.runModal() == .alertFirstButtonReturn {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    exit(1)
}

setupCrashSafety()

let statusBar = StatusBar.shared
let workspace = WorkspaceManager.shared
workspace.bootstrap()

let hotkeys = Hotkeys.shared
hotkeys.start()

let observer = WindowObserver.shared
observer.start()

fputs("tatami: running\n", stderr)
app.run()
