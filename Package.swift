// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "tatami",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "TatamiCore",
            path: "Sources",
            exclude: ["Config.def.swift"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "tatami",
            dependencies: ["TatamiCore"],
            path: "Entry"
        ),
        .executableTarget(
            name: "tatami-tests",
            dependencies: ["TatamiCore"],
            path: "Tests"
        ),
    ]
)
