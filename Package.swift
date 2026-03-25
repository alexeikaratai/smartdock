// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SmartDock",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "SmartDockCore",
            path: "Sources/SmartDockCore",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .executableTarget(
            name: "SmartDock",
            dependencies: ["SmartDockCore"],
            path: "Sources/SmartDock",
            linkerSettings: [
                .linkedFramework("Cocoa"),
            ]
        ),
        .testTarget(
            name: "SmartDockTests",
            dependencies: ["SmartDockCore"],
            path: "Tests/SmartDockTests"
        ),
    ]
)
