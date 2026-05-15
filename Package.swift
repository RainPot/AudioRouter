// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AudioRouter",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "AudioRouterApp", targets: ["AudioRouterApp"]),
    ],
    targets: [
        .executableTarget(
            name: "AudioRouterApp",
            path: "Sources/AudioRouterApp"
        ),
        .testTarget(
            name: "AudioRouterAppTests",
            dependencies: ["AudioRouterApp"],
            path: "Tests/AudioRouterAppTests"
        ),
    ]
)
