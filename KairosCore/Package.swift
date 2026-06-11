// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KairosCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "KairosCore",
            targets: ["KairosCore"]
        ),
    ],
    targets: [
        .target(
            name: "KairosCore"
        ),
        .testTarget(
            name: "KairosCoreTests",
            dependencies: ["KairosCore"]
        ),
    ]
)
