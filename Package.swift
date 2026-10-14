// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MorningOperator",
    defaultLocalization: "en",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "MorningCore", targets: ["MorningCore"]),
        .library(name: "MorningApple", targets: ["MorningApple"]),
        // The only code that imports HealthKit. The app does not link this product:
        // it stays out until the owner adds the HealthKit entitlement and usage text.
        .library(name: "MorningHealth", targets: ["MorningHealth"]),
        // Pure decisions for the tethered live-morning demo UI test. Linked only by
        // MorningOperatorUITests, never by the app.
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
