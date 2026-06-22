import Foundation

package struct RuntimeVersion: Equatable {
    package let version: String
    package let build: String

    package init(info: [String: Any]) {
        version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        build = info["CFBundleVersion"] as? String ?? "unknown"
    }

    package static func current(bundle: Bundle = .main) -> RuntimeVersion {
        RuntimeVersion(info: bundle.infoDictionary ?? [:])
    }

    package var diagnosticLines: [String] {
        [
            "parket_version: \(version)",
            "parket_build: \(build)",
        ]
    }
}
