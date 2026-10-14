// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MorningOperator",
    defaultLocalization: "en",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "MorningCore", targets: ["MorningCore"]),
        .library(name: "MorningApple", targets: ["MorningApple"]),
        // The only code that imports HealthKit. The app links it for the morning extras
        // (sleep and steps); the briefing's own sleep section still has no reader.
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
