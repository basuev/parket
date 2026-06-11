import AppKit

@MainActor
package final class StatusBar: NSObject {
    package static let shared = StatusBar()

    private let statusItem: NSStatusItem
    private var lastState: StatusState?
    private let permissionsItem = NSMenuItem(
        title: "Permissions", action: #selector(showPermissions), keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(
        title: "Accessibility", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let inputMonitoringItem = NSMenuItem(
        title: "Input Monitoring", action: #selector(openInputMonitoringSettings), keyEquivalent: "")
    private let recheckPermissionsItem = NSMenuItem(
        title: "Recheck Permissions", action: #selector(recheckPermissions), keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause Tiling", action: #selector(togglePause), keyEquivalent: "p")
    private let retileItem = NSMenuItem(title: "Retile Now", action: #selector(retileNow), keyEquivalent: "t")
    private let restoreItem = NSMenuItem(
        title: "Restore All Windows", action: #selector(restoreAllWindows), keyEquivalent: "")
    private let reloadItem = NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r")
    private let openConfigItem = NSMenuItem(title: "Open Config", action: #selector(openConfig), keyEquivalent: "")
    private let copyDiagnosticsItem = NSMenuItem(
        title: "Copy Diagnostic Report", action: #selector(copyDiagnosticReport), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")

    private override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        update()
    }

    private func buildMenu() {
        let menu = NSMenu()
        for item in [
            permissionsItem,
            accessibilityItem,
            inputMonitoringItem,
            recheckPermissionsItem,
            pauseItem,
            retileItem,
            restoreItem,
            reloadItem,
            openConfigItem,
            copyDiagnosticsItem,
            quitItem,
        ] {
            item.target = self
        }

        menu.addItem(permissionsItem)
        menu.addItem(accessibilityItem)
        menu.addItem(inputMonitoringItem)
        menu.addItem(recheckPermissionsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(pauseItem)
        menu.addItem(retileItem)
        menu.addItem(restoreItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(reloadItem)
        menu.addItem(openConfigItem)
        menu.addItem(copyDiagnosticsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func showPermissions() {
        ParketRuntime.shared.showPermissions()
    }

    @objc private func openAccessibilitySettings() {
        Permissions.request(.accessibility)
        Permissions.openSettings(.accessibility)
        ParketRuntime.shared.refreshPermissions(prompt: false)
    }

    @objc private func openInputMonitoringSettings() {
        Permissions.request(.inputMonitoring)
        Permissions.openSettings(.inputMonitoring)
        ParketRuntime.shared.refreshPermissions(prompt: false)
    }

    @objc private func recheckPermissions() {
        ParketRuntime.shared.refreshPermissions(prompt: false)
    }

    @objc private func togglePause() {
        WorkspaceManager.shared.toggleTilingPaused()
    }

    @objc private func retileNow() {
        WorkspaceManager.shared.retileNow()
    }

    @objc private func restoreAllWindows() {
        WorkspaceManager.shared.pauseTilingAndRestoreAllWindows()
    }

    @objc private func reloadConfig() {
        WorkspaceManager.shared.reloadConfig()
    }

    @objc private func openConfig() {
        Config.openConfig()
    }

    @objc private func copyDiagnosticReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(ParketRuntime.shared.diagnosticReport(), forType: .string)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func update() {
        updateMenu()
        let ws = WorkspaceManager.shared
        let state = StatusState.capture(ws)
        guard state != lastState else { return }
        lastState = state

        var views: [NSView] = []
        let font = NSFont.menuBarFont(ofSize: 0)
        let fontSize = font.pointSize
        let runtime = ParketRuntime.shared

        if !runtime.permissions.isReady || runtime.startupIssue != nil {
            let codes = runtime.permissions.missingCodes
            if codes.isEmpty {
                views.append(LayoutIndicatorView(text: "ERR", fontSize: fontSize))
            } else {
                for code in codes {
                    views.append(LayoutIndicatorView(text: "\(code)!", fontSize: fontSize))
                }
            }
            applyViews(views)
            return
        }

        if ws.isTilingPaused {
            views.append(LayoutIndicatorView(text: "PAUSED", fontSize: fontSize))
        }

        guard !ws.monitors.isEmpty else {
            views.append(BadgeView(number: 1, fontSize: fontSize, active: true))
            applyViews(views)
            return
        }

        let monitor = ws.focusedMonitor

        if ws.monitors.count > 1 {
            let monitorNumber = ws.focusedMonitorIndex + 1
            views.append(LayoutIndicatorView(text: "\(monitorNumber):", fontSize: fontSize))
        }

        let layout = monitor.layouts[monitor.active]
        if layout == .monocle {
            let windowCount = monitor.workspaces[monitor.active].count
            views.append(LayoutIndicatorView(text: "M\(windowCount)", fontSize: fontSize))
        }

        for i in 0..<Config.shared.workspaceCount {
            let isActive = i == monitor.active
            let hasWindows = !monitor.workspaces[i].isEmpty

            guard isActive || hasWindows else { continue }

            views.append(BadgeView(number: i + 1, fontSize: fontSize, active: isActive))
        }

        if views.isEmpty {
            views.append(BadgeView(number: 1, fontSize: fontSize, active: true))
        }

        applyViews(views)
    }

    private func updateMenu() {
        let runtime = ParketRuntime.shared
        let permissions = runtime.permissions
        let ws = WorkspaceManager.shared
        let missing = permissions.missingCodes.joined(separator: ", ")

        permissionsItem.title =
            permissions.isReady
            ? "Permissions: Granted"
            : "Permissions: Missing \(missing)"
        accessibilityItem.title = "Accessibility: \(permissions.accessibility ? "Granted" : "Missing")"
        inputMonitoringItem.title = "Input Monitoring: \(permissions.inputMonitoring ? "Granted" : "Missing")"

        pauseItem.state = ws.isTilingPaused ? .on : .off
        retileItem.isEnabled = runtime.isRunning
        restoreItem.isEnabled = runtime.isRunning
        reloadItem.isEnabled = runtime.isRunning
    }

    private func applyViews(_ views: [NSView]) {
        let stack = NSStackView(views: views)
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)

        DispatchQueue.main.async {
            guard let button = self.statusItem.button else { return }
            button.title = ""
            for view in button.subviews {
                view.removeFromSuperview()
            }
            stack.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                stack.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            ])
        }
    }
}

private let badgeColor = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 230 / 255, green: 230 / 255, blue: 235 / 255, alpha: 1)
        : NSColor(red: 26 / 255, green: 34 / 255, blue: 37 / 255, alpha: 1)
}

private func drawCenteredText(_ text: String, in bounds: NSRect, fontSize: CGFloat, color: NSColor, ctx: CGContext) {
    let font = NSFont.systemFont(ofSize: fontSize - 1)
    let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let line = CTLineCreateWithAttributedString(str)
    let lineBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    let textX = bounds.midX - lineBounds.width / 2 - lineBounds.origin.x
    let textY = bounds.midY - font.capHeight / 2
    ctx.textPosition = CGPoint(x: textX, y: textY)
    CTLineDraw(line, ctx)
}

private final class BadgeView: NSView {
    private let number: Int
    private let fontSize: CGFloat
    private let active: Bool

    init(number: Int, fontSize: CGFloat, active: Bool) {
        self.number = number
        self.fontSize = fontSize
        self.active = active
        super.init(frame: .zero)
        let size = fontSize + 6
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)

        ctx.addPath(path)
        let textColor: NSColor
        if active {
            ctx.setFillColor(badgeColor.cgColor)
            ctx.fillPath()
            ctx.setBlendMode(.destinationOut)
            textColor = .black
        } else {
            ctx.setStrokeColor(badgeColor.cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
            textColor = badgeColor
        }
        drawCenteredText("\(number)", in: bounds, fontSize: fontSize, color: textColor, ctx: ctx)
    }
}

private struct StatusState: Equatable {
    let permissions: PermissionSnapshot
    let startupIssue: String?
    let runtimeRunning: Bool
    let tilingPaused: Bool
    let monitorCount: Int
    let focusedMonitorIndex: Int
    let activeWorkspace: Int
    let activeLayout: Layout
    let occupiedWorkspaces: [Bool]
    let activeWindowCount: Int

    @MainActor
    static func capture(_ ws: WorkspaceManager) -> StatusState {
        let runtime = ParketRuntime.shared
        guard !ws.monitors.isEmpty else {
            return StatusState(
                permissions: runtime.permissions,
                startupIssue: runtime.startupIssue,
                runtimeRunning: runtime.isRunning,
                tilingPaused: ws.isTilingPaused,
                monitorCount: 0, focusedMonitorIndex: 0, activeWorkspace: 0,
                activeLayout: .tile, occupiedWorkspaces: [], activeWindowCount: 0
            )
        }
        let monitor = ws.focusedMonitor
        let occupied = (0..<Config.shared.workspaceCount).map { !monitor.workspaces[$0].isEmpty }
        return StatusState(
            permissions: runtime.permissions,
            startupIssue: runtime.startupIssue,
            runtimeRunning: runtime.isRunning,
            tilingPaused: ws.isTilingPaused,
            monitorCount: ws.monitors.count,
            focusedMonitorIndex: ws.focusedMonitorIndex,
            activeWorkspace: monitor.active,
            activeLayout: monitor.layouts[monitor.active],
            occupiedWorkspaces: occupied,
            activeWindowCount: monitor.workspaces[monitor.active].count
        )
    }
}

private final class LayoutIndicatorView: NSView {
    private let text: String
    private let fontSize: CGFloat

    init(text: String, fontSize: CGFloat) {
        self.text = text
        self.fontSize = fontSize
        super.init(frame: .zero)
        let font = NSFont.systemFont(ofSize: fontSize - 1)
        let str = NSAttributedString(string: text, attributes: [.font: font])
        let textWidth = str.size().width
        widthAnchor.constraint(equalToConstant: textWidth + 6).isActive = true
        heightAnchor.constraint(equalToConstant: fontSize + 6).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawCenteredText(text, in: bounds, fontSize: fontSize, color: badgeColor, ctx: ctx)
    }
}
