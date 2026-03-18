import CoreGraphics
@testable import ParketCore

enum TilerPerformanceTests {
    static let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    static func runAll() -> (passed: Int, failed: Int) {
        var passed = 0
        var failed = 0

        func check(_ condition: Bool, _ message: String) {
            if condition {
                passed += 1
            } else {
                fputs("FAIL: \(message)\n", stderr)
                failed += 1
            }
        }

        do {
            let iterations = 10_000
            let start = DispatchTime.now()
            for _ in 0..<iterations {
                for count in 1...20 {
                    _ = Tiler.calculateFrames(count: count, screen: screen, layout: .tile)
                }
            }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            let perCall = elapsed / Double(iterations * 20)
            fputs("  tile: \(String(format: "%.3f", elapsed))ms total, \(String(format: "%.4f", perCall))ms/call\n", stderr)
            check(perCall < 1.0, "tile layout under 1ms per call")
        }

        do {
            let iterations = 10_000
            let start = DispatchTime.now()
            for _ in 0..<iterations {
                for count in 1...50 {
                    _ = Tiler.calculateFrames(count: count, screen: screen, layout: .monocle)
                }
            }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            let perCall = elapsed / Double(iterations * 50)
            fputs("  monocle: \(String(format: "%.3f", elapsed))ms total, \(String(format: "%.4f", perCall))ms/call\n", stderr)
            check(perCall < 1.0, "monocle layout under 1ms per call")
        }

        return (passed, failed)
    }
}
