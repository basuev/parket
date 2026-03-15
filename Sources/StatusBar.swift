import AppKit

final class StatusBar {
    static let shared = StatusBar()

    private let statusItem: NSStatusItem

    private init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        update()
    }

    func update() {
        let ws = WorkspaceManager.shared
        var parts: [String] = []

        for i in 0..<9 {
            let tag = i + 1
            if i == ws.active {
                parts.append("[\(tag)]")
            } else if !ws.workspaces[i].isEmpty {
                parts.append("\(tag)")
            }
        }

        let title = parts.isEmpty ? "[1]" : parts.joined(separator: " ")
        DispatchQueue.main.async {
            self.statusItem.button?.title = title
        }
    }
}
