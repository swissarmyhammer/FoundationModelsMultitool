// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The name of this Swift package.
let packageName = "FoundationModelsMultitool"

/// The name of the FoundationModelsRouter dependency package.
let routerDependencyName = "FoundationModelsRouter"

/// SwiftPM manifest for FoundationModelsMultitool.
///
/// Integrates the FoundationModelsRouter package alongside the system
/// FoundationModels and JavaScriptCore frameworks.
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
            url: "https://github.com/swissarmyhammer/\(routerDependencyName)",
            branch: "main"
        )
    ],
    targets: [
        .target(
            name: packageName,
            dependencies: [
                .product(name: routerDependencyName, package: routerDependencyName)
            ],
            path: "Sources/\(packageName)"
        ),
        .testTarget(
            name: "\(packageName)Tests",
            dependencies: [
                .target(name: packageName),
                .product(name: routerDependencyName, package: routerDependencyName),
            ],
            path: "Tests/\(packageName)Tests",
            resources: [
                // Golden files pinning `ToolAPIRenderer`'s rendered surface
                // (M2). Tests read these directly off disk via `#filePath`,
                // not `Bundle.module`; declared as a resource purely so
                // SwiftPM doesn't warn about an unhandled source-tree file.
                .copy("Goldens")
            ]
        ),
    ]
)
