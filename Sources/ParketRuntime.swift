import AppKit

@MainActor
package final class ParketRuntime {
    package static let shared = ParketRuntime()

    package private(set) var permissions = Permissions.snapshot()
    package private(set) var isRunning = false
    package private(set) var startupIssue: String?

    private var screenObserver: NSObjectProtocol?

    private init() {}

    package func start() {
        Config.load()
        _ = StatusBar.shared
        refreshPermissions(prompt: false)
    }

    package func refreshPermissions(prompt: Bool) {
        startupIssue = nil
        permissions = Permissions.snapshot(promptAccessibility: prompt)

        if permissions.isReady {
            startServices()
            PermissionWindowController.shared.closeWindow()
        } else {
            enterWaitingState()
            PermissionWindowController.shared.show(snapshot: permissions, startupIssue: nil)
        }

        StatusBar.shared.update()
    }

    package func showPermissions() {
        permissions = Permissions.snapshot()
        PermissionWindowController.shared.show(snapshot: permissions, startupIssue: startupIssue)
        StatusBar.shared.update()
    }

    package func diagnosticReport() -> String {
        permissions = Permissions.snapshot()
        let ws = WorkspaceManager.shared
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        var lines: [String] = [
            "parket diagnostic report",
            "bundle_id: \(bundleID)",
            "macos: \(version)",
            "accessibility: \(permissions.accessibility ? "granted" : "missing")",
            "runtime: \(isRunning ? "running" : "waiting")",
            "tiling: \(ws.isTilingPaused ? "paused" : "enabled")",
            "config_path: \(Config.path)",
            "workspace_count: \(Config.shared.workspaceCount)",
            "monitor_count: \(ws.monitors.count)",
        ]
        lines.append(contentsOf: Hotkeys.shared.diagnosticLines())

        if let startupIssue {
            lines.append("startup_issue: \(startupIssue)")
        }

        for monitorIndex in ws.monitors.indices {
            let monitor = ws.monitors[monitorIndex]
            let counts = monitor.workspaces.map(\.count).map(String.init).joined(separator: ",")
            lines.append(
                "monitor_\(monitorIndex + 1): active=\(monitor.active + 1) layout=\(monitor.layouts[monitor.active]) windows=[\(counts)]"
            )
        }

        return lines.joined(separator: "\n")
    }

    package func reloadConfig() {
        Config.load()
        if isRunning {
            WorkspaceManager.shared.applyCurrentConfig()
            Hotkeys.shared.reload()
        }
        StatusBar.shared.update()
        fputs("parket: config reloaded\n", stderr)
    }

    private func startServices() {
        guard !isRunning else { return }

        WorkspaceManager.shared.bootstrap()
        WindowObserver.shared.start()
        registerScreenObserver()
        Hotkeys.shared.start()
        isRunning = true
        fputs("parket: running\n", stderr)
    }

    private func enterWaitingState() {
        Hotkeys.shared.stop()
        isRunning = false
    }

    private func registerScreenObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if ParketRuntime.shared.isRunning {
                    WorkspaceManager.shared.handleScreenChange()
                }
            }
        }
    }
}
