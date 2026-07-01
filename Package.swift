// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let packageName = "FoundationModelsMultitool"

let package = Package(
    name: packageName,
    // Commit to macOS 27 / FoundationModels v2; no pre-27 fallback.
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(
            name: packageName,
            targets: [packageName]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/swissarmyhammer/FoundationModelsRouter",
            branch: "main"
        )
    ],
    targets: [
        .target(
            name: packageName,
            dependencies: [
                .product(name: "FoundationModelsRouter", package: "FoundationModelsRouter")
            ],
            path: "Sources/\(packageName)"
        ),
        .testTarget(
            name: "\(packageName)Tests",
            dependencies: [
                .target(name: packageName),
                .product(name: "FoundationModelsRouter", package: "FoundationModelsRouter"),
            ],
            path: "Tests/\(packageName)Tests"
        ),
    ]
)
