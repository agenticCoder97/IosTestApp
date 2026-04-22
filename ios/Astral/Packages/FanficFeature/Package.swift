// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FanficFeature",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FanficFeature", targets: ["FanficFeature"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Networking"),
        .package(path: "../DesignSystem"),
        .package(path: "../StatsUI"),
    ],
    targets: [
        .target(
            name: "FanficFeature",
            dependencies: ["Core", "Networking", "DesignSystem", "StatsUI"]
        ),
        .testTarget(
            name: "FanficFeatureTests",
            dependencies: ["FanficFeature", "Core"],
            path: "Tests/FanficFeatureTests"
        ),
    ]
)
