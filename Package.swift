// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "metr",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "metr", targets: ["Metr"]),
        .executable(name: "metr-statusline", targets: ["MetrStatusline"]),
        .library(name: "MetrKit", targets: ["MetrKit"])
    ],
    targets: [
        // Data model + logic. No AppKit/SwiftUI, so it is testable headlessly.
        .target(name: "MetrKit"),
        // Presentation layer only.
        .executableTarget(name: "Metr", dependencies: ["MetrKit"]),
        // Tiny stdin-to-local-snapshot bridge for Claude Code's official
        // statusLine hook. It has no UI and never handles credentials.
        .executableTarget(name: "MetrStatusline"),
        .testTarget(name: "MetrKitTests", dependencies: ["MetrKit"])
    ]
)
