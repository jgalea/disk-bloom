// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BloomCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BloomCore", targets: ["BloomCore"])
    ],
    targets: [
        .target(
            name: "BloomCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(name: "BloomCoreTests", dependencies: ["BloomCore"])
    ]
)
