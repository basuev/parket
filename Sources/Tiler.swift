import Foundation

package enum Layout {
    case tile
    case monocle
}

package enum Tiler {
    package static func calculateFrames(count: Int, screen: CGRect, layout: Layout) -> [CGRect] {
        guard count > 0 else { return [] }
        switch layout {
        case .tile: return tileFrames(count: count, screen: screen)
        case .monocle: return monocleFrames(count: count, screen: screen)
        }
    }

    static func tile(windows: [TrackedWindow], screen: CGRect, layout: Layout) {
        let frames = calculateFrames(count: windows.count, screen: screen, layout: layout)
        for (i, frame) in frames.enumerated() {
            windows[i].setFrame(frame)
        }
    }

    private static func tileFrames(count: Int, screen: CGRect) -> [CGRect] {
        if count == 1 {
            return [screen]
        }

        var result: [CGRect] = []
        result.reserveCapacity(count)
        let masterWidth = floor(screen.width * Config.masterRatio)
        result.append(CGRect(
            x: screen.origin.x, y: screen.origin.y,
            width: masterWidth, height: screen.height
        ))

        let stackCount = count - 1
        let stackWidth = screen.width - masterWidth
        let stackHeight = floor(screen.height / CGFloat(stackCount))

        for i in 1..<count {
            let y = screen.origin.y + CGFloat(i - 1) * stackHeight
            let h = (i == count - 1)
                ? screen.height - CGFloat(i - 1) * stackHeight
                : stackHeight
            result.append(CGRect(
                x: screen.origin.x + masterWidth, y: y,
                width: stackWidth, height: h
            ))
        }
        return result
    }

    private static func monocleFrames(count: Int, screen: CGRect) -> [CGRect] {
        Array(repeating: screen, count: count)
    }
}
