import AppKit
import ParketCore

func setupCrashSafety() {
    let restore: @convention(c) (Int32) -> Void = { _ in
        MainActor.assumeIsolated {
            WorkspaceManager.shared.restoreAllWindows()
        }
        exit(0)
    }
    signal(SIGTERM, restore)
    signal(SIGINT, restore)
    atexit {
        MainActor.assumeIsolated {
            WorkspaceManager.shared.restoreAllWindows()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
setupCrashSafety()
ParketRuntime.shared.start()
app.run()
