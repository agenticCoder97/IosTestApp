// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StatsUI",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "StatsUI", targets: ["StatsUI"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "StatsUI",
            dependencies: ["Core", "DesignSystem"]
        ),
    ]
)
