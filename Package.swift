// swift-tools-version: 6.2

import PackageDescription

/// Applied to every target so the whole package moves together.
///
/// Both are slated to become the default in a later language mode; enabling them
/// now means the migration is already done, and it cannot regress — a bare
/// existential or a member reached through a transitive import breaks the build
/// instead of quietly accumulating.
let upcomingFeatures: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "SmartDock",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "SmartDockCore",
            path: "Sources/SmartDockCore",
            swiftSettings: upcomingFeatures,
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .executableTarget(
            name: "SmartDock",
            dependencies: ["SmartDockCore"],
            path: "Sources/SmartDock",
            swiftSettings: upcomingFeatures,
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "SmartDockTests",
            dependencies: ["SmartDockCore"],
            path: "Tests/SmartDockTests",
            swiftSettings: upcomingFeatures
        ),
    ]
)
