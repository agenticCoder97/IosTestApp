// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ComicFeature",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ComicFeature", targets: ["ComicFeature"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Networking"),
        .package(path: "../DesignSystem"),
        .package(path: "../StatsUI"),
    ],
    targets: [
        .target(
            name: "ComicFeature",
            dependencies: ["Core", "Networking", "DesignSystem", "StatsUI"]
        ),
        .testTarget(
            name: "ComicFeatureTests",
            dependencies: ["ComicFeature", "Core"],
            path: "Tests/ComicFeatureTests"
        ),
    ]
)
