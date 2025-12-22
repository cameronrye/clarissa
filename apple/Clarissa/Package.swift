// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Clarissa",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "ClarissaKit",
            targets: ["ClarissaKit"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ClarissaKit",
            dependencies: [],
            path: "Sources",
            exclude: ["App"]
        ),
        .testTarget(
            name: "ClarissaKitTests",
            dependencies: ["ClarissaKit"],
            path: "Tests"
        )
    ]
)

