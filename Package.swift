// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "metr",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "metr", targets: ["Metr"]),
        .library(name: "MetrKit", targets: ["MetrKit"])
    ],
    targets: [
        // Data model + logic. No AppKit/SwiftUI, so it is testable headlessly.
        .target(name: "MetrKit"),
        // Presentation layer only.
        .executableTarget(name: "Metr", dependencies: ["MetrKit"]),
        .testTarget(name: "MetrKitTests", dependencies: ["MetrKit"])
    ]
)
