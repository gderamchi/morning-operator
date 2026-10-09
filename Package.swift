// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MorningOperator",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "MorningCore", targets: ["MorningCore"]),
        .library(name: "MorningApple", targets: ["MorningApple"]),
        .executable(name: "MorningOperator", targets: ["MorningOperator"])
    ],
    targets: [
        .target(name: "MorningCore"),
        .target(name: "MorningApple", dependencies: ["MorningCore"]),
        .executableTarget(name: "MorningOperator", dependencies: ["MorningCore", "MorningApple"]),
        .testTarget(name: "MorningCoreTests", dependencies: ["MorningCore"]),
        .testTarget(name: "MorningAppleTests", dependencies: ["MorningApple", "MorningCore"])
    ]
)
