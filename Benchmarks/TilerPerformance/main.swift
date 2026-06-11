import CoreGraphics
import Dispatch
import Foundation
import ParketCore

@main
struct TilerPerformance {
    static let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    static func main() {
        var failed = 0

        if !measureTile() {
            failed += 1
        }

        if !measureMonocle() {
            failed += 1
        }

        if failed > 0 {
            exit(1)
        }
    }

    static func measureTile() -> Bool {
        let iterations = 10_000
        let start = DispatchTime.now()
        for _ in 0..<iterations {
            for count in 1...20 {
                _ = Tiler.calculateFrames(count: count, screen: screen, layout: .tile)
            }
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        let perCall = elapsed / Double(iterations * 20)
        fputs(
            "tile: \(String(format: "%.3f", elapsed))ms total, \(String(format: "%.4f", perCall))ms/call\n",
            stderr
        )
        return perCall < 1.0
    }

    static func measureMonocle() -> Bool {
        let iterations = 10_000
        let start = DispatchTime.now()
        for _ in 0..<iterations {
            for count in 1...50 {
                _ = Tiler.calculateFrames(count: count, screen: screen, layout: .monocle)
            }
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        let perCall = elapsed / Double(iterations * 50)
        fputs(
            "monocle: \(String(format: "%.3f", elapsed))ms total, \(String(format: "%.4f", perCall))ms/call\n",
            stderr
        )
        return perCall < 1.0
    }
}
