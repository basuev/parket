import AppKit
import ApplicationServices

func checkAccessibility() -> Bool {
    AXIsProcessTrusted()
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
    fputs("mmwm: grant Accessibility permission and restart\n", stderr)
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

fputs("mmwm: running\n", stderr)
app.run()
