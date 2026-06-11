import Foundation
import OSLog

@MainActor
package enum PerformanceTelemetry {
    package enum Operation: String, CaseIterable {
        case workspaceSwitch = "workspace_switch"
        case hideWorkspace = "hide_workspace"
        case retile = "retile"
        case focusRestore = "focus_restore"
        case screenChange = "screen_change"
        case axSnapshot = "ax_snapshot"
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "parket",
        category: "performance"
    )
    private static let sampleLimit = 120
    private static var samples: [Operation: [Double]] = [:]
    private static var axReads = 0
    private static var axWrites = 0
    private static var suppressedGeometryNotifications = 0

    @discardableResult
    package static func measure<T>(_ operation: Operation, _ body: () -> T) -> T {
        let start = ProcessInfo.processInfo.systemUptime
        let result = body()
        record(operation, duration: ProcessInfo.processInfo.systemUptime - start)
        return result
    }

    package static func recordAXRead() {
        axReads += 1
    }

    package static func recordAXWrite() {
        axWrites += 1
    }

    package static func recordSuppressedGeometryNotification() {
        suppressedGeometryNotifications += 1
    }

    package static func diagnosticLines() -> [String] {
        var lines = [
            "performance_ax_reads: \(axReads)",
            "performance_ax_writes: \(axWrites)",
            "performance_geometry_suppressed: \(suppressedGeometryNotifications)",
        ]

        for operation in Operation.allCases {
            guard let stats = stats(for: operation) else { continue }
            lines.append(
                "performance_\(operation.rawValue): count=\(stats.count) p50_ms=\(format(stats.p50)) p95_ms=\(format(stats.p95)) max_ms=\(format(stats.max))"
            )
        }

        return lines
    }

    private static func record(_ operation: Operation, duration: TimeInterval) {
        let milliseconds = duration * 1000
        var operationSamples = samples[operation, default: []]
        operationSamples.append(milliseconds)
        if operationSamples.count > sampleLimit {
            operationSamples.removeFirst(operationSamples.count - sampleLimit)
        }
        samples[operation] = operationSamples

        if milliseconds >= 50 {
            logger.notice(
                "\(operation.rawValue, privacy: .public) took \(milliseconds, format: .fixed(precision: 1)) ms")
        } else {
            logger.debug(
                "\(operation.rawValue, privacy: .public) took \(milliseconds, format: .fixed(precision: 1)) ms")
        }
    }

    private static func stats(for operation: Operation) -> (count: Int, p50: Double, p95: Double, max: Double)? {
        guard let operationSamples = samples[operation], !operationSamples.isEmpty else { return nil }
        let sorted = operationSamples.sorted()
        return (
            count: operationSamples.count,
            p50: percentile(sorted, 0.50),
            p95: percentile(sorted, 0.95),
            max: sorted[sorted.count - 1]
        )
    }

    private static func percentile(_ sorted: [Double], _ value: Double) -> Double {
        guard sorted.count > 1 else { return sorted[0] }
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * value).rounded(.up))))
        return sorted[index]
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
