// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MorningOperator",
    defaultLocalization: "en",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "MorningCore", targets: ["MorningCore"]),
        .library(name: "MorningApple", targets: ["MorningApple"]),
        // HealthKit stays isolated from the widget and the shared briefing logic.
        .library(name: "MorningHealth", targets: ["MorningHealth"]),
        // Pure demo policy/wire values; XCTest phone control remains in the UI-test target.
        .library(name: "MorningLiveDemo", targets: ["MorningLiveDemo"])
    ],
    targets: [
        .target(name: "MorningCore", resources: [.process("Resources")]),
        .target(name: "MorningApple", dependencies: ["MorningCore"], resources: [.process("Resources")]),
        .target(name: "MorningHealth", dependencies: ["MorningApple"]),
        .target(name: "MorningLiveDemo"),
        .testTarget(name: "MorningCoreTests", dependencies: ["MorningCore"]),
        .testTarget(name: "MorningLiveDemoTests", dependencies: ["MorningLiveDemo"]),
        .testTarget(name: "MorningHealthTests", dependencies: ["MorningHealth", "MorningApple"]),
        .testTarget(name: "MorningAppleTests", dependencies: ["MorningApple", "MorningCore"])
    ]
)
