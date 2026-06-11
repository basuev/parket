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
        refreshPermissions(prompt: true)
    }

    package func refreshPermissions(prompt: Bool) {
        startupIssue = nil
        permissions = Permissions.snapshot(
            promptAccessibility: prompt,
            promptInputMonitoring: prompt
        )

        if permissions.isReady {
            if startServices() {
                PermissionWindowController.shared.closeWindow()
            } else {
                PermissionWindowController.shared.show(snapshot: permissions, startupIssue: startupIssue)
            }
        } else {
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
            "input_monitoring: \(permissions.inputMonitoring ? "granted" : "missing")",
            "runtime: \(isRunning ? "running" : "waiting")",
            "hotkeys: \(Hotkeys.shared.isRunning ? "running" : "stopped")",
            "tiling: \(ws.isTilingPaused ? "paused" : "enabled")",
            "config_path: \(Config.path)",
            "workspace_count: \(Config.shared.workspaceCount)",
            "monitor_count: \(ws.monitors.count)",
        ]

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

    private func startServices() -> Bool {
        guard !isRunning else { return true }

        guard Hotkeys.shared.start() else {
            startupIssue = "Hotkeys could not start. Recheck Input Monitoring or restart parket."
            return false
        }

        WorkspaceManager.shared.bootstrap()
        WindowObserver.shared.start()
        registerScreenObserver()
        isRunning = true
        fputs("parket: running\n", stderr)
        return true
    }

    private func registerScreenObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                WorkspaceManager.shared.handleScreenChange()
            }
        }
    }
}
