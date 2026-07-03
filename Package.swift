// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The name of this Swift package.
let packageName = "FoundationModelsMultitool"

/// The name of the FoundationModelsRouter dependency package.
let routerDependencyName = "FoundationModelsRouter"

/// The MLX-backed model package `FoundationModelsRouter` itself depends on
/// (`../FoundationModelsRouter/Package.swift`'s `mlxPackage`). Only two of
/// its products are declared directly here (not Router's own broader
/// `mlxProducts` set): `MLXLMCommon`, whose `Downloader`/`TokenizerLoader`
/// protocols a live `LiveModelLoader` is constructed over, and
/// `MLXHuggingFace`, whose `#hubDownloader()`/`#huggingFaceTokenizerLoader()`
/// macros adapt a real Hugging Face Hub client into those protocols — the
/// same macros Router's own gated `…IntegrationTests` target uses. Already
/// part of this package's resolved dependency graph transitively (Router's
/// own library target needs the *full* mlx-swift-lm product set to build at
/// all), so declaring these two directly for the gated integration test
/// target below adds no new MLX/C++ compilation, only linking.
let mlxPackage = "mlx-swift-lm"

/// Hugging Face Hub client and tokenizer packages. Needed only by the gated
/// integration test target below, which constructs a real, live
/// `LiveModelLoader` through the `MLXHuggingFace` macros — mirrors
/// `../FoundationModelsRouter/Package.swift`'s own `hubProducts` (same
/// package identities and version floors as Router's own gated suite, so a
/// machine that already ran Router's gated suite shares the resolved
/// checkout).
let huggingFacePackage = "swift-huggingface"
let transformersPackage = "swift-transformers"

/// The Hub client + tokenizer products the gated integration test target
/// injects into a live `LiveModelLoader` (via the `MLXHuggingFace` macros).
/// Only that target links these.
let hubProducts: [Target.Dependency] = [
    .product(name: "HuggingFace", package: huggingFacePackage),
    .product(name: "Tokenizers", package: transformersPackage),
]

/// The `mlx-swift-lm` products the gated integration test target links
/// directly, alongside `hubProducts`, to construct a live `LiveModelLoader`
/// — see `mlxPackage`'s documentation above.
let liveLoaderMLXProducts: [Target.Dependency] = [
    .product(name: "MLXLMCommon", package: mlxPackage),
    .product(name: "MLXHuggingFace", package: mlxPackage),
]

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
        ),
        // Only the gated integration test target below links products from
        // these three — see their documentation above.
        .package(
            url: "https://github.com/swissarmyhammer/\(mlxPackage)",
            branch: "mlx-foundationmodels"
        ),
        .package(
            url: "https://github.com/huggingface/\(huggingFacePackage)",
            from: "0.9.0"
        ),
        .package(
            url: "https://github.com/huggingface/\(transformersPackage)",
            from: "1.3.0"
        ),
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
                // (M2), and checked-in fixture JSONL transcripts
                // `TranscriptAnalyzer`'s ungated unit tests
                // (`TranscriptAssertionTests`, M6.5a) parse. Tests read these
                // directly off disk via `#filePath`, not `Bundle.module`;
                // declared as a resource purely so SwiftPM doesn't warn about
                // an unhandled source-tree file.
                .copy("Goldens")
            ]
        ),
        // M6.5a: the gated, opt-in real-model suite — plan.md M6.5 +
        // Testing strategy "Integration tests", modeled on Router's own
        // gated `…IntegrationTests` target
        // (`../FoundationModelsRouter/Package.swift`). Every test is
        // `.enabled(if:)` the `MULTITOOL_INTEGRATION` env var, so it never
        // fires on a network/GPU-less box or in normal CI — but it still
        // *builds* under plain `swift build`/`swift test`, so it links the
        // live-inference wiring (`liveLoaderMLXProducts` + `hubProducts`)
        // needed to construct a real `LiveModelLoader` the same way Router's
        // own gated suite does.
        .testTarget(
            name: "\(packageName)IntegrationTests",
            dependencies: [
                .target(name: packageName),
                .product(name: routerDependencyName, package: routerDependencyName),
            ] + liveLoaderMLXProducts + hubProducts,
            path: "Tests/\(packageName)IntegrationTests"
        ),
    ]
)
