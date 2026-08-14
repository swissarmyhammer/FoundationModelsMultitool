// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

/// The name of this Swift package.
private let packageName = "FoundationModelsMultitool"

/// The name of the M9 sample CLI executable target (and its Sources/ subdirectory).
private let cliTargetName = "multitool-cli"

/// The git branch tracked by the `.package(url:branch:)` declaration for
/// `metadataRegistryDependencyName` below, and the default for
/// `swissArmyHammerPackage(name:branch:)`.
private let mainBranch = "main"

/// The name of the FoundationModelsRouter dependency package.
private let routerDependencyName = "FoundationModelsRouter"

/// The name of the FoundationModelsMetadataRegistry dependency package.
///
/// It's wired as a remote dependency (`main` branch) the same way
/// `routerDependencyName` is — the registry is already consumable by URL
/// (`../FoundationModelsMetadataRegistry/Package.swift`'s own `main` is in
/// sync with `origin/main`), so no registry-side change is needed here.
/// It supplies `SearchableMetadata`/`MetadataSearcher` — the catalog-search
/// surface `SearchToolsTool`'s registry-backed selection tier (`SelectionTier`,
/// generalizing this package's own former `Librarian`) is built over —
/// linked by the library target, the unit test target, and the gated
/// integration test target below.
private let metadataRegistryDependencyName = "FoundationModelsMetadataRegistry"

/// Base URL for packages published under the swissarmyhammer GitHub
/// organization — `routerDependencyName` and `metadataRegistryDependencyName`
/// are fetched from here.
private let swissArmyHammerPackageOrgURL = "git@github.com:swissarmyhammer/"

/// Builds a `.package(url:branch:)` dependency for a package hosted under
/// `swissArmyHammerPackageOrgURL`, tracking `branch` (`mainBranch` by default).
///
/// This is used for `metadataRegistryDependencyName` (the default branch),
/// for `mlxPackage` (its published `stable` branch), and for
/// `routerDependencyName` again once the temporary local-path declaration
/// below is restored.
private func swissArmyHammerPackage(name: String, branch: String = mainBranch) -> Package.Dependency {
    .package(url: "\(swissArmyHammerPackageOrgURL)\(name).git", branch: branch)
}

/// The MLX-backed model package `FoundationModelsRouter` itself depends on
/// (`../FoundationModelsRouter/Package.swift`'s `mlxPackage`).
///
/// Taken by URL from its published `stable` branch — see `mlxStableBranch`.
///
/// Only three of its products are declared directly here (not Router's own
/// broader `mlxProducts` set): `MLXLMCommon`, whose
/// `Downloader`/`TokenizerLoader` protocols a live `LiveModelLoader` is
/// constructed over; `MLXHuggingFace`, whose
/// `#hubDownloader()`/`#huggingFaceTokenizerLoader()` macros adapt a real
/// Hugging Face Hub client into those protocols — the same macros Router's
/// own gated `…IntegrationTests` target uses, and the M9 `multitool-cli`
/// executable's default (production) model-resolution path uses too; and
/// `MLXVLM`, for its model registry alone (see `liveLoaderMLXProducts`).
/// This is already part of this package's resolved dependency graph
/// transitively (Router's own library target needs the *full* mlx-swift-lm
/// product set to build at all), so declaring these three directly for the
/// targets below adds no new MLX/C++ compilation, only linking.
private let mlxPackage = "mlx-swift-lm"

/// The `mlxPackage` branch this package builds against.
///
/// `stable` rather than the sibling checkout this used to take by path. Both
/// carry the same fork work — the local `catch-up-upstream` branch has merged
/// `stable` — but a published branch is a *snapshot*, and a working copy is
/// whatever another session happens to have saved. Building against a working
/// copy is how this package spent a morning failing on someone else's
/// half-finished edit (`^ev0zca7`).
///
/// `stable` also carries `ml-explore/mlx-swift-lm` upstream: the fork has
/// caught up, so this is upstream plus the fork's own landed work rather than
/// a divergent branch.
private let mlxStableBranch = "stable"

/// Base URL for packages published under the Hugging Face GitHub
/// organization — `huggingFacePackage` and `transformersPackage` are both
/// fetched from here.
private let huggingFaceOrgURL = "https://github.com/huggingface/"

/// Builds a `.package(url:from:)` dependency for a package hosted under
/// `huggingFaceOrgURL`, pinned to a minimum semantic version floor.
///
/// This is used for `huggingFacePackage` and `transformersPackage`, whose
/// declarations would otherwise be near-verbatim copies differing only in the
/// package name and version floor — mirrors `swissArmyHammerPackage(name:)`
/// above.
private func huggingFaceOrgPackage(name: String, from version: Version) -> Package.Dependency {
    .package(url: "\(huggingFaceOrgURL)\(name)", from: version)
}

/// Hugging Face Hub client and tokenizer packages.
///
/// These packages are needed by every target below that constructs a real,
/// live `LiveModelLoader` through the `MLXHuggingFace` macros (the gated
/// integration test target, and the M9 `multitool-cli` executable). This
/// mirrors `../FoundationModelsRouter/Package.swift`'s own `hubProducts`
/// (same package identities and version floors as Router's own gated
/// suite, so a machine that already ran Router's gated suite shares the
/// resolved checkout).
private let huggingFacePackage = "swift-huggingface"

/// The Swift Transformers tokenizer package, paired with
/// `huggingFacePackage` above — linked by the gated integration test target
/// and the M9 `multitool-cli` executable.
private let transformersPackage = "swift-transformers"

/// The Hub client + tokenizer products a live `LiveModelLoader` needs (via
/// the `MLXHuggingFace` macros) — linked by the gated integration test
/// target and the M9 `multitool-cli` executable.
private let hubProducts: [Target.Dependency] = [
    .product(name: "HuggingFace", package: huggingFacePackage),
    .product(name: "Tokenizers", package: transformersPackage),
]

/// The `mlx-swift-lm` products a live `LiveModelLoader` needs, alongside
/// `hubProducts` — see `mlxPackage`'s documentation above.
private let liveLoaderMLXProducts: [Target.Dependency] = [
    .product(name: "MLXLMCommon", package: mlxPackage),
    .product(name: "MLXHuggingFace", package: mlxPackage),
    // Linked for its model registry, not for vision, exactly as Router links
    // it (`../FoundationModelsRouter/Package.swift`). `loadModelContainer`
    // finds a factory through `MLXLMCommon`'s `ModelFactoryRegistry`, which
    // resolves its built-in trampolines with `NSClassFromString`, so a
    // factory reaches that registry only when its module is linked into the
    // binary. Muse Glimmer (`muse_glimmer`) — the model both the CLI demo
    // profile and the gated suite pin — is registered in `VLMModelFactory`
    // alone, and without this the id throws `unsupportedModelType` after
    // paying for the whole download.
    .product(name: "MLXVLM", package: mlxPackage),
]

/// The `Sources/` subdirectory prefix used by every source target's `path`
/// below.
private let sourcesPath = "Sources/"

/// The `Tests/` subdirectory prefix used by every test target's `path`
/// below.
private let testsPath = "Tests/"

/// SwiftPM manifest for FoundationModelsMultitool.
///
/// Integration of the FoundationModelsRouter package alongside the system
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
        // TEMPORARY (human-directed 2026-08-10): Router by local path rather than
        // by branch, so a Router fix can be tested here the moment it lands
        // without waiting on a push + re-resolve. Restore
        // `swissArmyHammerPackage(name: routerDependencyName)` before this
        // package is consumed anywhere but this machine.
        .package(path: "../\(routerDependencyName)"),
        swissArmyHammerPackage(name: metadataRegistryDependencyName),
        // Only the M9 CLI executable and the gated integration test target
        // below link products from these three — see their documentation
        // above.
        swissArmyHammerPackage(name: mlxPackage, branch: mlxStableBranch),
        huggingFaceOrgPackage(name: huggingFacePackage, from: "0.9.0"),
        huggingFaceOrgPackage(name: transformersPackage, from: "1.3.0"),
    ],
    targets: [
        .target(
            name: packageName,
            dependencies: [
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: metadataRegistryDependencyName, package: metadataRegistryDependencyName),
            ],
            path: "\(sourcesPath)\(packageName)"
        ),
        // M9: the sample CLI executable — plan.md "M9 — Sample CLI. A prompt
        // that triggers searchTools then a multi-tool runCode." Links
        // `liveLoaderMLXProducts` + `hubProducts` (see their documentation
        // above) so its default, production model-resolution path can
        // construct a real `LiveModelLoader` — the same live-inference
        // wiring the gated `…IntegrationTests` target below uses — making
        // this a genuinely runnable demo, not just a stub, when run outside
        // this package's own gated-off sandbox.
        .executableTarget(
            name: cliTargetName,
            dependencies: [
                .target(name: packageName),
                .product(name: routerDependencyName, package: routerDependencyName),
                // Needed to wrap a resolved Router generation slot as a real
                // `FoundationModels.LanguageModel` (`MLXLanguageModel`), so
                // the CLI can build a native `LanguageModelSession` directly
                // over it — see `CLIRunner.makeMLXLanguageModel(for:)`.
                .product(name: "MLXFoundationModels", package: mlxPackage),
            ] + liveLoaderMLXProducts + hubProducts,
            path: "\(sourcesPath)\(cliTargetName)"
            // No custom linker settings needed: the rpath workaround that
            // used to live here existed only because the retired
            // `Agent/AgentEvaluators.swift` made the *library* target import
            // Apple's test-only `Evaluations` framework, whose autolink
            // metadata propagated into this executable and broke its launch
            // (`dyld: Library not loaded`). With that file deleted, the
            // library no longer imports `Evaluations` and the executable
            // launches with SwiftPM's default rpaths — verified by running
            // the built binary directly.
        ),
        .testTarget(
            name: "\(packageName)Tests",
            dependencies: [
                .target(name: packageName),
                .target(name: cliTargetName),
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: metadataRegistryDependencyName, package: metadataRegistryDependencyName),
            ],
            path: "\(testsPath)\(packageName)Tests",
            resources: [
                // Golden files pinning `ToolAPIRenderer`'s rendered surface
                // (M2). Tests read these directly off disk via `#filePath`,
                // not `Bundle.module`; declared as a resource purely so
                // SwiftPM doesn't warn about an unhandled source-tree file.
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
                .target(name: cliTargetName),
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: metadataRegistryDependencyName, package: metadataRegistryDependencyName),
                // Needed to construct `MLXLanguageModel`/`LanguageModelSession`
                // directly, the same way `multitool-cli` itself does (via
                // `CLIRunner.makeMLXLanguageModel(for:)`) — the gated scenarios
                // in this target drive a real, native
                // `LanguageModelSession` over the tools
                // `MultiTool.Registry.makeSessionTools(librarian:)` vends, not
                // `MultiToolAgent`'s retired hand-rolled loop.
                .product(name: "MLXFoundationModels", package: mlxPackage),
            ] + liveLoaderMLXProducts + hubProducts,
            path: "\(testsPath)\(packageName)IntegrationTests"
        ),
    ]
)
