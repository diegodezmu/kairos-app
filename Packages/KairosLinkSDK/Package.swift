// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KairosLinkSDK",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "KairosLinkSDK",
            targets: ["KairosLinkSDK"]
        ),
        .executable(
            name: "KairosLinkSmokeCLI",
            targets: ["KairosLinkSmokeCLI"]
        ),
        .executable(
            name: "KairosLinkDeterminismSpikeCLI",
            targets: ["KairosLinkDeterminismSpikeCLI"]
        ),
    ],
    targets: [
        .target(
            name: "CAbletonLink",
            path: "Vendor/link/extensions/abl_link",
            exclude: [
                "CMakeLists.txt",
                "README.md",
                "abl_link.cmake",
                "examples",
            ],
            sources: [
                "src/abl_link.cpp",
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../../include"),
                .headerSearchPath("../../modules/asio-standalone/asio/include"),
                .define("LINK_PLATFORM_UNIX", to: "1"),
                .define("LINK_PLATFORM_MACOSX", to: "1"),
            ]
        ),
        .target(
            name: "KairosLinkSDK",
            dependencies: ["CAbletonLink"]
        ),
        .executableTarget(
            name: "KairosLinkSmokeCLI",
            dependencies: ["KairosLinkSDK"]
        ),
        .executableTarget(
            name: "KairosLinkDeterminismSpikeCLI",
            dependencies: ["CAbletonLink"]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
