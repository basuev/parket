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
    private struct SpanTrace {
        let name: String
        let duration: TimeInterval
        let axReads: Int
        let axWrites: Int
    }

    private static var samples: [Operation: [Double]] = [:]
    private static var axReads = 0
    private static var axWrites = 0
    private static var suppressedGeometryNotifications = 0
    private static var tracePathLoaded = false
    private static var tracePath: String?
    private static var traceHandle: FileHandle?
    private static var spanTraceStack: [[SpanTrace]] = []

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

    @discardableResult
    package static func traceAction<T>(
        _ name: String,
        startedAt: TimeInterval,
        metadata: [String: Int],
        _ body: () -> T
    ) -> T {
        guard isActionTracingEnabled else { return body() }

        let runStartedAt = ProcessInfo.processInfo.systemUptime
        let startReads = axReads
        let startWrites = axWrites
        spanTraceStack.append([])
        let result = body()
        let finishedAt = ProcessInfo.processInfo.systemUptime
        let spans = spanTraceStack.removeLast()
        writeActionTrace(
            name: name,
            startedAt: startedAt,
            duration: finishedAt - startedAt,
            runDuration: finishedAt - runStartedAt,
            queueDelay: runStartedAt - startedAt,
            axReads: axReads - startReads,
            axWrites: axWrites - startWrites,
            metadata: metadata,
            spans: spans
        )
        return result
    }

    @discardableResult
    package static func traceSubspan<T>(_ name: String, _ body: () -> T) -> T {
        guard isActionTracingEnabled, !spanTraceStack.isEmpty else { return body() }

        let startedAt = ProcessInfo.processInfo.systemUptime
        let startReads = axReads
        let startWrites = axWrites
        let result = body()
        let finishedAt = ProcessInfo.processInfo.systemUptime
        let span = SpanTrace(
            name: traceFieldPrefix(name),
            duration: finishedAt - startedAt,
            axReads: axReads - startReads,
            axWrites: axWrites - startWrites
        )
        spanTraceStack[spanTraceStack.index(before: spanTraceStack.endIndex)].append(span)
        return result
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

    private static var isActionTracingEnabled: Bool {
        actionTracePath() != nil
    }

    private static func actionTracePath() -> String? {
        if !tracePathLoaded {
            tracePathLoaded = true
            tracePath = ProcessInfo.processInfo.environment["PARKET_TRACE_PATH"].flatMap {
                $0.isEmpty ? nil : $0
            }
        }
        return tracePath
    }

    private static func writeActionTrace(
        name: String,
        startedAt: TimeInterval,
        duration: TimeInterval,
        runDuration: TimeInterval,
        queueDelay: TimeInterval,
        axReads: Int,
        axWrites: Int,
        metadata: [String: Int],
        spans: [SpanTrace]
    ) {
        var fields: [(String, String)] = [
            ("kind", jsonString("action")),
            ("name", jsonString(name)),
            ("started_at", formatJSON(startedAt)),
            ("duration_ms", formatJSON(duration * 1000)),
            ("queue_delay_ms", formatJSON(queueDelay * 1000)),
            ("run_ms", formatJSON(runDuration * 1000)),
            ("ax_reads", String(axReads)),
            ("ax_writes", String(axWrites)),
            ("result", jsonString("ok")),
        ]

        for span in spans {
            fields.append(("\(span.name)_ms", formatJSON(span.duration * 1000)))
            fields.append(("\(span.name)_ax_reads", String(span.axReads)))
            fields.append(("\(span.name)_ax_writes", String(span.axWrites)))
        }

        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            fields.append((key, String(value)))
        }

        for (key, value) in actionStateFields().sorted(by: { $0.key < $1.key }) {
            fields.append((key, String(value)))
        }

        appendTraceLine("{\(fields.map { "\(jsonString($0.0)):\($0.1)" }.joined(separator: ","))}")
    }

    private static func actionStateFields() -> [String: Int] {
        let workspace = WorkspaceManager.shared
        guard !workspace.monitors.isEmpty else {
            return ["monitor_count": 0]
        }

        let monitor = workspace.focusedMonitor
        return [
            "active_window_count": monitor.workspaces[monitor.active].count,
            "active_workspace": monitor.active + 1,
            "focused_monitor": workspace.focusedMonitorIndex + 1,
            "monitor_count": workspace.monitors.count,
        ]
    }

    private static func appendTraceLine(_ line: String) {
        guard let path = actionTracePath() else { return }
        let url = URL(fileURLWithPath: path)

        if traceHandle == nil {
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            traceHandle = try? FileHandle(forWritingTo: url)
            _ = try? traceHandle?.seekToEnd()
        }

        guard let data = "\(line)\n".data(using: .utf8) else { return }
        _ = try? traceHandle?.seekToEnd()
        try? traceHandle?.write(contentsOf: data)
    }

    private static func jsonString(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                result += "\\\""
            case "\\":
                result += "\\\\"
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            case _ where scalar.value < 0x20:
                result += String(format: "\\u%04X", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }

    private static func formatJSON(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func traceFieldPrefix(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            let allowed =
                (scalar.value >= 48 && scalar.value <= 57)
                || (scalar.value >= 65 && scalar.value <= 90)
                || (scalar.value >= 97 && scalar.value <= 122)
                || scalar.value == 95
            if allowed {
                result.unicodeScalars.append(scalar)
            } else {
                result += "_"
            }
        }
        return result.isEmpty ? "span" : result
    }
}
