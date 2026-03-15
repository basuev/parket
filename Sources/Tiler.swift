import Foundation

enum Tiler {
    static func tile(windows: [TrackedWindow], screen: CGRect) {
        guard !windows.isEmpty else { return }

        if windows.count == 1 {
            windows[0].setFrame(screen)
            return
        }

        let masterWidth = floor(screen.width * Config.masterRatio)
        let masterRect = CGRect(
            x: screen.origin.x,
            y: screen.origin.y,
            width: masterWidth,
            height: screen.height
        )
        windows[0].setFrame(masterRect)

        let stackCount = windows.count - 1
        let stackWidth = screen.width - masterWidth
        let stackHeight = floor(screen.height / CGFloat(stackCount))

        for i in 1..<windows.count {
            let y = screen.origin.y + CGFloat(i - 1) * stackHeight
            let h = (i == windows.count - 1)
                ? screen.height - CGFloat(i - 1) * stackHeight
                : stackHeight
            let rect = CGRect(
                x: screen.origin.x + masterWidth,
                y: y,
                width: stackWidth,
                height: h
            )
            windows[i].setFrame(rect)
        }
    }
}
