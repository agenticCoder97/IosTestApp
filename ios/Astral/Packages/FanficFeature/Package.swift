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
    ],
    targets: [
        .target(
            name: "FanficFeature",
            dependencies: ["Core", "Networking", "DesignSystem"]
        ),
    ]
)
