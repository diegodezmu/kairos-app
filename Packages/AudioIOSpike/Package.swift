// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AudioIOSpike",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "AudioIOSpikeSupport",
            targets: ["AudioIOSpikeSupport"]
        ),
        .executable(
            name: "AudioIOSpikeCLI",
            targets: ["AudioIOSpikeCLI"]
        ),
    ],
    targets: [
        .target(
            name: "CAudioIOSpikeAtomics",
            publicHeadersPath: "include"
        ),
        .target(
            name: "AudioIOSpikeSupport",
            dependencies: ["CAudioIOSpikeAtomics"]
        ),
        .executableTarget(
            name: "AudioIOSpikeCLI",
            dependencies: ["AudioIOSpikeSupport"]
        ),
        .testTarget(
            name: "AudioIOSpikeSupportTests",
            dependencies: ["AudioIOSpikeSupport"]
        ),
    ]
)
