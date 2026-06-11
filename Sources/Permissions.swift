import AppKit
import ApplicationServices
import CoreGraphics

package enum PermissionKind {
    case accessibility
    case inputMonitoring
}

package struct PermissionSnapshot: Equatable {
    let accessibility: Bool
    let inputMonitoring: Bool

    var isReady: Bool {
        accessibility && inputMonitoring
    }

    var missingCodes: [String] {
        var result: [String] = []
        if !accessibility { result.append("AX") }
        if !inputMonitoring { result.append("IM") }
        return result
    }
}

@MainActor
package enum Permissions {
    package static func snapshot(
        promptAccessibility: Bool = false,
        promptInputMonitoring: Bool = false
    ) -> PermissionSnapshot {
        PermissionSnapshot(
            accessibility: accessibilityTrusted(prompt: promptAccessibility),
            inputMonitoring: inputMonitoringTrusted(prompt: promptInputMonitoring)
        )
    }

    package static func request(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            _ = accessibilityTrusted(prompt: true)
        case .inputMonitoring:
            _ = inputMonitoringTrusted(prompt: true)
        }
    }

    package static func openSettings(_ kind: PermissionKind) {
        let value: String
        switch kind {
        case .accessibility:
            value = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            value = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }

        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func accessibilityTrusted(prompt: Bool) -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func inputMonitoringTrusted(prompt: Bool) -> Bool {
        prompt ? CGRequestListenEventAccess() : CGPreflightListenEventAccess()
    }
}
