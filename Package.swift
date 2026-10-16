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
        .library(name: "MorningHealth", targets: ["MorningHealth"])
    ],
    targets: [
        .target(name: "MorningCore", resources: [.process("Resources")]),
        .target(name: "MorningApple", dependencies: ["MorningCore"], resources: [.process("Resources")]),
        .target(name: "MorningHealth", dependencies: ["MorningApple"]),
        .testTarget(name: "MorningCoreTests", dependencies: ["MorningCore"]),
        .testTarget(name: "MorningHealthTests", dependencies: ["MorningHealth", "MorningApple"]),
        .testTarget(name: "MorningAppleTests", dependencies: ["MorningApple", "MorningCore"])
    ]
)
