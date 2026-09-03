// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FissionCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FissionCore",
            targets: ["FissionCore"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            from: "7.9.0"
        ),
    ],
    targets: [
        .target(
            name: "FissionCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "FissionCoreTests",
            dependencies: ["FissionCore"],
            path: "Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
