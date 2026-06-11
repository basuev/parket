import AppKit

@MainActor
package final class StatusBar: NSObject {
    package static let shared = StatusBar()

    private let statusItem: NSStatusItem
    private var lastState: StatusState?
    private let stateSummaryItem = NSMenuItem(title: "parket", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause Tiling", action: #selector(togglePause), keyEquivalent: "p")
    private let retileItem = NSMenuItem(title: "Retile Now", action: #selector(retileNow), keyEquivalent: "t")
    private let restoreItem = NSMenuItem(
        title: "Pause and Restore Windows", action: #selector(restoreAllWindows), keyEquivalent: "")
    private let openAccessibilityItem = NSMenuItem(
        title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let recheckAccessibilityItem = NSMenuItem(
        title: "Recheck Accessibility", action: #selector(recheckPermissions), keyEquivalent: "")
    private let openConfigItem = NSMenuItem(title: "Open Config", action: #selector(openConfig), keyEquivalent: "")
    private let reloadItem = NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r")
    private let copyDiagnosticsItem = NSMenuItem(
        title: "Copy Diagnostic Report", action: #selector(copyDiagnosticReport), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit parket", action: #selector(quit), keyEquivalent: "q")
    private let stateSeparator = NSMenuItem.separator()
    private let problemSeparator = NSMenuItem.separator()
    private let configSeparator = NSMenuItem.separator()
    private let diagnosticsSeparator = NSMenuItem.separator()
    private let quitSeparator = NSMenuItem.separator()

    private override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        update()
    }

    private func buildMenu() {
        let menu = NSMenu()
        for item in [
            pauseItem,
            retileItem,
            restoreItem,
            openAccessibilityItem,
            recheckAccessibilityItem,
            openConfigItem,
            reloadItem,
            copyDiagnosticsItem,
            quitItem,
        ] {
            item.target = self
        }

        stateSummaryItem.isEnabled = false
        menu.addItem(stateSummaryItem)
        menu.addItem(stateSeparator)
        menu.addItem(pauseItem)
        menu.addItem(retileItem)
        menu.addItem(restoreItem)
        menu.addItem(problemSeparator)
        menu.addItem(openAccessibilityItem)
        menu.addItem(recheckAccessibilityItem)
        menu.addItem(configSeparator)
        menu.addItem(openConfigItem)
        menu.addItem(reloadItem)
        menu.addItem(diagnosticsSeparator)
        menu.addItem(copyDiagnosticsItem)
        menu.addItem(quitSeparator)
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func openAccessibilitySettings() {
        Permissions.requestAccessibility()
        Permissions.openAccessibilitySettings()
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
        ParketRuntime.shared.reloadConfig()
    }

    @objc private func openConfig() {
        Config.openConfig()
    }

    @objc private func copyDiagnosticReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(ParketRuntime.shared.diagnosticReport(), forType: .string)
        copyDiagnosticsItem.title = "Diagnostic Report Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.copyDiagnosticsItem.title = "Copy Diagnostic Report"
        }
    }

    @objc private func quit() {
        if ParketRuntime.shared.permissions.isReady {
            WorkspaceManager.shared.restoreAllWindows()
        }
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

        if !runtime.permissions.isReady {
            views.append(
                SymbolBadgeView(
                    symbolName: "accessibility", accessibilityLabel: "Accessibility Missing", fontSize: fontSize))
            applyViews(views)
            return
        }

        if runtime.startupIssue != nil {
            views.append(
                SymbolBadgeView(
                    symbolName: "exclamationmark.triangle", accessibilityLabel: "Startup Issue", fontSize: fontSize))
            applyViews(views)
            return
        }

        if Hotkeys.shared.status == .degraded {
            views.append(
                SymbolBadgeView(symbolName: "keyboard", accessibilityLabel: "Hotkeys Degraded", fontSize: fontSize))
        }

        if ws.isTilingPaused {
            views.append(
                SymbolBadgeView(symbolName: "pause.fill", accessibilityLabel: "Tiling Paused", fontSize: fontSize))
        }

        guard !ws.monitors.isEmpty else {
            views.append(BadgeView(number: 1, fontSize: fontSize, active: true))
            applyViews(views)
            return
        }

        let monitor = ws.focusedMonitor

        if ws.monitors.count > 1 {
            let monitorNumber = ws.focusedMonitorIndex + 1
            views.append(MonitorBadgeView(number: monitorNumber, fontSize: fontSize))
        }

        let layout = monitor.layouts[monitor.active]
        if layout == .monocle {
            let windowCount = monitor.workspaces[monitor.active].count
            views.append(MonocleBadgeView(windowCount: windowCount, fontSize: fontSize))
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

        stateSummaryItem.title = stateSummaryTitle()
        stateSummaryItem.isEnabled = false

        let showAccessibilityActions = !permissions.accessibility
        problemSeparator.isHidden = !showAccessibilityActions
        openAccessibilityItem.isHidden = !showAccessibilityActions
        recheckAccessibilityItem.isHidden = !showAccessibilityActions

        pauseItem.state = ws.isTilingPaused ? .on : .off
        pauseItem.isEnabled = runtime.isRunning
        retileItem.isEnabled = runtime.isRunning
        restoreItem.isEnabled = runtime.isRunning
        reloadItem.isEnabled = true
        openConfigItem.isEnabled = true
        copyDiagnosticsItem.isEnabled = true
    }

    private func stateSummaryTitle() -> String {
        let runtime = ParketRuntime.shared
        let ws = WorkspaceManager.shared

        if !runtime.permissions.isReady {
            return "parket: Accessibility Missing"
        }

        if runtime.startupIssue != nil {
            return "parket: Startup Issue"
        }

        var problemParts: [String] = []
        if Hotkeys.shared.status == .degraded {
            problemParts.append("Hotkeys Degraded")
        }
        if ws.isTilingPaused {
            problemParts.append("Paused")
        }
        if !problemParts.isEmpty {
            return "parket: \(problemParts.joined(separator: ", "))"
        }

        guard !ws.monitors.isEmpty else {
            return "parket: Workspace 1"
        }

        let monitor = ws.focusedMonitor
        let display = ws.monitors.count > 1 ? "Display \(ws.focusedMonitorIndex + 1), " : ""
        if monitor.layouts[monitor.active] == .monocle {
            let count = monitor.workspaces[monitor.active].count
            return "parket: \(display)Monocle, \(count) \(Self.windowWord(count))"
        }

        return "parket: \(display)Workspace \(monitor.active + 1)"
    }

    private static func windowWord(_ count: Int) -> String {
        count == 1 ? "window" : "windows"
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

private final class SymbolBadgeView: NSView {
    private let imageView = NSImageView()

    init(symbolName: String, accessibilityLabel: String, fontSize: CGFloat) {
        super.init(frame: .zero)
        let size = fontSize + 6
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        setAccessibilityElement(true)
        setAccessibilityLabel(accessibilityLabel)

        let configuration = NSImage.SymbolConfiguration(pointSize: fontSize - 3, weight: .semibold)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)?
            .withSymbolConfiguration(configuration)
        imageView.contentTintColor = badgeColor
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: size - 6),
            imageView.heightAnchor.constraint(equalToConstant: size - 6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        imageView.contentTintColor = badgeColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
        ctx.addPath(path)
        ctx.setStrokeColor(badgeColor.cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
    }
}

private final class MonitorBadgeView: NSView {
    private let number: Int
    private let fontSize: CGFloat

    init(number: Int, fontSize: CGFloat) {
        self.number = number
        self.fontSize = fontSize
        super.init(frame: .zero)
        widthAnchor.constraint(equalToConstant: fontSize + 12).isActive = true
        heightAnchor.constraint(equalToConstant: fontSize + 6).isActive = true
        setAccessibilityElement(true)
        setAccessibilityLabel("Display \(number)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let screenRect = bounds.insetBy(dx: 2.5, dy: 3.0)
        let path = CGPath(roundedRect: screenRect, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
        ctx.addPath(path)
        ctx.setStrokeColor(badgeColor.cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
        drawCenteredText("\(number)", in: screenRect, fontSize: fontSize, color: badgeColor, ctx: ctx)
    }
}

private final class MonocleBadgeView: NSView {
    private let windowCount: Int
    private let fontSize: CGFloat

    init(windowCount: Int, fontSize: CGFloat) {
        self.windowCount = windowCount
        self.fontSize = fontSize
        super.init(frame: .zero)
        widthAnchor.constraint(equalToConstant: windowCount > 1 ? fontSize + 15 : fontSize + 6).isActive = true
        heightAnchor.constraint(equalToConstant: fontSize + 6).isActive = true
        setAccessibilityElement(true)
        setAccessibilityLabel(
            windowCount == 1 ? "Monocle Layout, 1 Window" : "Monocle Layout, \(windowCount) Windows")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
        ctx.addPath(path)
        ctx.setStrokeColor(badgeColor.cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()

        let iconSize = fontSize - 5
        let iconX = windowCount > 1 ? rect.minX + 4 : rect.midX - iconSize / 2
        let iconRect = CGRect(x: iconX, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize)
        ctx.addPath(CGPath(roundedRect: iconRect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
        ctx.setFillColor(badgeColor.cgColor)
        ctx.fillPath()

        if windowCount > 1 {
            let textRect = CGRect(
                x: iconRect.maxX + 2, y: rect.minY, width: rect.maxX - iconRect.maxX - 3, height: rect.height)
            drawCenteredText("\(windowCount)", in: textRect, fontSize: fontSize, color: badgeColor, ctx: ctx)
        }
    }
}

private struct StatusState: Equatable {
    let permissions: PermissionSnapshot
    let startupIssue: String?
    let runtimeRunning: Bool
    let hotkeyStatus: HotkeyStatus
    let hotkeyIssueCount: Int
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
                hotkeyStatus: Hotkeys.shared.status,
                hotkeyIssueCount: Hotkeys.shared.issueCount,
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
            hotkeyStatus: Hotkeys.shared.status,
            hotkeyIssueCount: Hotkeys.shared.issueCount,
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
