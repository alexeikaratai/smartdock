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
        // The AppKit layer as a library, so the test bundle can build a view or a
        // menu and read it back. The executable keeps only what has to carry the
        // app's own module name: `@main`, the App Intents (their identifiers are
        // module-qualified) and the `@objc` scripting command classes.
        .target(
            name: "SmartDockUI",
            dependencies: ["SmartDockCore"],
            path: "Sources/SmartDockUI",
            swiftSettings: upcomingFeatures,
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "SmartDock",
            dependencies: ["SmartDockCore", "SmartDockUI"],
            path: "Sources/SmartDock",
            swiftSettings: upcomingFeatures,
            linkerSettings: [
                .linkedFramework("Cocoa"),
            ]
        ),
        .testTarget(
            name: "SmartDockTests",
            dependencies: ["SmartDockCore", "SmartDockUI"],
            path: "Tests/SmartDockTests",
            swiftSettings: upcomingFeatures
        ),
    ]
)
