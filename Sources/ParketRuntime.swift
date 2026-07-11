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
        ]
        lines.append(contentsOf: RuntimeVersion.current().diagnosticLines)
        lines.append(contentsOf: [
            "macos: \(version)",
            "accessibility: \(permissions.accessibility ? "granted" : "missing")",
            "runtime: \(isRunning ? "running" : "waiting")",
            "tiling: \(ws.isTilingPaused ? "paused" : "enabled")",
            "config_path: \(Config.path)",
            "workspace_count: \(Config.shared.workspaceCount)",
            "monitor_count: \(ws.monitors.count)",
            "ax_messaging_timeout_seconds: \(WindowManager.messagingTimeoutSeconds)",
        ])
        lines.append(contentsOf: Hotkeys.shared.diagnosticLines())
        lines.append("screen_topology: \(WindowManager.screenTopologySignature())")
        for (index, screen) in WindowManager.screenDescriptors().enumerated() {
            lines.append(
                "screen_\(index): id=\(screen.displayID) frame=\(format(screen.frame)) visible=\(format(screen.visibleFrame)) scale=\(String(format: "%.2f", Double(screen.scale)))"
            )
        }
        lines.append(contentsOf: PerformanceTelemetry.diagnosticLines())

        if let startupIssue {
            lines.append("startup_issue: \(startupIssue)")
        }

        for monitorIndex in ws.monitors.indices {
            let monitor = ws.monitors[monitorIndex]
            let counts = monitor.workspaces.map(\.count).map(String.init).joined(separator: ",")
            lines.append(
                "monitor_\(monitorIndex + 1): active=\(monitor.active + 1) layout=\(monitor.layouts[monitor.active]) windows=[\(counts)]"
            )
            for workspaceIndex in monitor.workspaces.indices {
                for windowIndex in monitor.workspaces[workspaceIndex].indices {
                    let window = monitor.workspaces[workspaceIndex][windowIndex]
                    let frame = window.getFrame().map(format) ?? "unknown"
                    let title = sanitize(window.title() ?? "")
                    lines.append(
                        "window: monitor=\(monitorIndex + 1) workspace=\(workspaceIndex + 1) index=\(windowIndex) pid=\(window.pid) members=\(window.members.count) frame=\(frame) title=\(title)"
                    )
                }
            }
        }
        lines.append(contentsOf: WindowManager.appDiscoveryDiagnosticLines())

        return lines.joined(separator: "\n")
    }

    private func format(_ rect: CGRect) -> String {
        "(\(format(rect.origin.x)),\(format(rect.origin.y)),\(format(rect.width)),\(format(rect.height)))"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
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

        let timeoutStatus = WindowManager.configureMessagingTimeout()
        if timeoutStatus != .success {
            startupIssue = "failed to configure AX messaging timeout: \(timeoutStatus.rawValue)"
        }
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
