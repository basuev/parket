import AppKit

final class StatusBar: NSObject {
    static let shared = StatusBar()

    private let statusItem: NSStatusItem

    private override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu

        update()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func update() {
        let ws = WorkspaceManager.shared
        var views: [NSView] = []
        let font = NSFont.menuBarFont(ofSize: 0)
        let fontSize = font.pointSize

        for i in 0..<Config.workspaceCount {
            let isActive = i == ws.active
            let hasWindows = !ws.workspaces[i].isEmpty

            guard isActive || hasWindows else { continue }

            views.append(BadgeView(number: i + 1, fontSize: fontSize, active: isActive))
        }

        if views.isEmpty {
            views.append(BadgeView(number: 1, fontSize: fontSize, active: true))
        }

        let stack = NSStackView(views: views)
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)

        DispatchQueue.main.async {
            guard let button = self.statusItem.button else { return }
            button.title = ""
            button.subviews.forEach { $0.removeFromSuperview() }
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

private let badgeColor = NSColor(red: 26/255, green: 34/255, blue: 37/255, alpha: 1)

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
        let font = NSFont.systemFont(ofSize: fontSize - 1)
        let str = NSAttributedString(
            string: "\(number)",
            attributes: [.font: font, .foregroundColor: NSColor.black]
        )
        let line = CTLineCreateWithAttributedString(str)
        let lineBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let textX = bounds.midX - lineBounds.width / 2 - lineBounds.origin.x
        let textY = bounds.midY - font.capHeight / 2

        if active {
            ctx.addPath(path)
            ctx.setFillColor(badgeColor.cgColor)
            ctx.fillPath()

            ctx.setBlendMode(.destinationOut)
            ctx.textPosition = CGPoint(x: textX, y: textY)
            CTLineDraw(line, ctx)
        } else {
            ctx.addPath(path)
            ctx.setStrokeColor(badgeColor.cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()

            ctx.setFillColor(badgeColor.cgColor)
            ctx.textPosition = CGPoint(x: textX, y: textY)
            CTLineDraw(line, ctx)
        }
    }
}
