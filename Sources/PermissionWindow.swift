import AppKit

@MainActor
package final class PermissionWindowController: NSWindowController {
    package static let shared = PermissionWindowController()

    private let titleLabel = PermissionWindowController.label("parket needs permissions", size: 17, weight: .semibold)
    private let detailsLabel = PermissionWindowController.wrappingLabel(
        "Grant Accessibility, then use Recheck Permissions. parket starts tiling only after Accessibility is granted."
    )
    private let accessibilityState = PermissionWindowController.label("", size: 13, weight: .regular)
    private let startupIssueLabel = PermissionWindowController.wrappingLabel("")

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "parket Permissions"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    package func show(snapshot: PermissionSnapshot, startupIssue: String?) {
        update(snapshot: snapshot, startupIssue: startupIssue)
        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    package func update(snapshot: PermissionSnapshot, startupIssue: String?) {
        accessibilityState.stringValue = Self.stateText(snapshot.accessibility)
        accessibilityState.textColor = Self.stateColor(snapshot.accessibility)
        startupIssueLabel.stringValue = startupIssue ?? ""
        startupIssueLabel.isHidden = startupIssue == nil
    }

    package func closeWindow() {
        close()
    }

    private func buildContent() {
        let openAccessibility = NSButton(
            title: "Open Accessibility",
            target: self,
            action: #selector(openAccessibilitySettings)
        )
        let recheck = NSButton(
            title: "Recheck Permissions",
            target: self,
            action: #selector(recheckPermissions)
        )
        recheck.keyEquivalent = "\r"

        let rows = NSStackView(views: [
            permissionRow(title: "Accessibility", state: accessibilityState, button: openAccessibility)
        ])
        rows.orientation = .vertical
        rows.spacing = 10

        let content = NSStackView(views: [
            titleLabel,
            detailsLabel,
            rows,
            startupIssueLabel,
            recheck,
        ])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        content.translatesAutoresizingMaskIntoConstraints = false

        window?.contentView = NSView()
        guard let contentView = window?.contentView else { return }
        contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: contentView.topAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }

    private func permissionRow(title: String, state: NSTextField, button: NSButton) -> NSStackView {
        let name = Self.label(title, size: 13, weight: .medium)
        name.widthAnchor.constraint(equalToConstant: 130).isActive = true
        state.widthAnchor.constraint(equalToConstant: 76).isActive = true

        let row = NSStackView(views: [name, state, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    @objc private func openAccessibilitySettings() {
        Permissions.requestAccessibility()
        Permissions.openAccessibilitySettings()
        ParketRuntime.shared.refreshPermissions(prompt: false)
    }

    @objc private func recheckPermissions() {
        ParketRuntime.shared.refreshPermissions(prompt: false)
    }

    private static func label(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        return field
    }

    private static func wrappingLabel(_ text: String) -> NSTextField {
        let field = label(text, size: 13, weight: .regular)
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.preferredMaxLayoutWidth = 420
        return field
    }

    private static func stateText(_ granted: Bool) -> String {
        granted ? "Granted" : "Missing"
    }

    private static func stateColor(_ granted: Bool) -> NSColor {
        granted ? .systemGreen : .systemRed
    }
}
