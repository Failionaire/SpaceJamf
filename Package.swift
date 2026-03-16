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
            path: "Sources/SpaceJamf"
        ),
        .testTarget(
            name: "SpaceJamfTests",
            dependencies: ["SpaceJamf"],
            path: "Tests/SpaceJamfTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
