// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tidemark",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Tidemark", targets: ["Tidemark"]),
        .library(name: "TidemarkKit", targets: ["TidemarkKit"])
    ],
    targets: [
        // Data model + logic. No AppKit/SwiftUI, so it is testable headlessly.
        .target(name: "TidemarkKit"),
        // Presentation layer only.
        .executableTarget(name: "Tidemark", dependencies: ["TidemarkKit"]),
        .testTarget(name: "TidemarkKitTests", dependencies: ["TidemarkKit"])
    ]
)
