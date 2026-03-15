// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "tatami",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "tatami",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
