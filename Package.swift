// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpaceJamf",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "SpaceJamf",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/SpaceJamf",
            // PK-2: Enable strict concurrency checking so the compiler enforces
            // Sendable conformance and actor isolation at compile time (Swift 5.9).
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SpaceJamfTests",
            dependencies: ["SpaceJamf"],
            path: "Tests/SpaceJamfTests",
            resources: [
                // PK-3: .copy preserves the Fixtures directory structure verbatim
                // inside the test bundle (Bundle.module.url accesses it at runtime).
                .copy("Fixtures")
            ]
        )
    ]
)
