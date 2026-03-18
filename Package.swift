// swift-tools-version: 5.9
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
        .executableTarget(
            name: "parket-tests",
            dependencies: ["ParketCore"],
            path: "Tests"
        ),
    ]
)
