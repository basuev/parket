import AppKit
import ApplicationServices

package struct PermissionSnapshot: Equatable {
    let accessibility: Bool

    var isReady: Bool {
        accessibility
    }

    var missingCodes: [String] {
        var result: [String] = []
        if !accessibility { result.append("AX") }
        return result
    }
}

@MainActor
package enum Permissions {
    package static func snapshot(promptAccessibility: Bool = false) -> PermissionSnapshot {
        PermissionSnapshot(
            accessibility: accessibilityTrusted(prompt: promptAccessibility)
        )
    }

    package static func requestAccessibility() {
        _ = accessibilityTrusted(prompt: true)
    }

    package static func openAccessibilitySettings() {
        let value = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func accessibilityTrusted(prompt: Bool) -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
