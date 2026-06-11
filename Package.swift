// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "parket",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ParketCore",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "parket",
            dependencies: ["ParketCore"],
            path: "Entry"
        ),
        .testTarget(
            name: "ParketCoreTests",
            dependencies: ["ParketCore"],
            path: "Tests",
            exclude: ["Fixtures", "Smoke"]
        ),
        .executableTarget(
            name: "parket-perf",
            dependencies: ["ParketCore"],
            path: "Benchmarks/TilerPerformance"
        ),
    ],
    swiftLanguageModes: [.v6]
)
