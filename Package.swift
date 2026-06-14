// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentMeter",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Reusable, UI-free parsing layer. Kept free of AppKit/SwiftUI so it can
        // later be lifted into a Stats module (or any other host) unchanged.
        .target(
            name: "AgentMeterCore"
        ),
        // The menu bar app itself.
        .executableTarget(
            name: "AgentMeter",
            dependencies: ["AgentMeterCore"]
        ),
        .testTarget(
            name: "AgentMeterCoreTests",
            dependencies: ["AgentMeterCore"]
        ),
    ]
)
