// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

/// The name of this Swift package.
private let packageName = "FoundationModelsMultitool"

/// The name of the M9 sample CLI executable target (and its Sources/ subdirectory).
private let cliTargetName = "multitool-cli"

/// The git branch tracked by the `.package(url:branch:)` declarations for
/// `routerDependencyName` and `metadataRegistryDependencyName` below — both
/// dependencies are wired to their respective `main` branches.
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
/// surface `FindAPIsTool`'s registry-backed selection tier (`SelectionTier`,
/// generalizing this package's own former `Librarian`) is built over —
/// linked by the library target, the unit test target, and the gated
/// integration test target below.
private let metadataRegistryDependencyName = "FoundationModelsMetadataRegistry"

/// Base URL for packages published under the swissarmyhammer GitHub
/// organization — `routerDependencyName`, `metadataRegistryDependencyName`,
/// and `mlxPackage` are all fetched from here.
private let swissArmyHammerOrgURL = "git@github.com:swissarmyhammer/"

/// Builds a `.package(url:branch:)` dependency for a package hosted under
/// `swissArmyHammerOrgURL`, tracking `branch` (`mainBranch` by default).
///
/// This is used for `routerDependencyName` and `metadataRegistryDependencyName`
/// (default `mainBranch`) and `mlxPackage` (its own fork branch), whose
/// declarations would otherwise be near-verbatim copies differing only in the
/// package name and tracked branch.
private func swissArmyHammerPackage(name: String, branch: String = mainBranch) -> Package.Dependency {
    .package(url: "\(swissArmyHammerOrgURL)\(name).git", branch: branch)
}

/// The MLX-backed model package `FoundationModelsRouter` itself depends on
/// (`../FoundationModelsRouter/Package.swift`'s `mlxPackage`).
///
/// Only two of its products are declared directly here (not Router's own
/// broader `mlxProducts` set): `MLXLMCommon`, whose
/// `Downloader`/`TokenizerLoader` protocols a live `LiveModelLoader` is
/// constructed over, and `MLXHuggingFace`, whose
/// `#hubDownloader()`/`#huggingFaceTokenizerLoader()` macros adapt a real
/// Hugging Face Hub client into those protocols — the same macros Router's
/// own gated `…IntegrationTests` target uses, and the M9 `multitool-cli`
/// executable's default (production) model-resolution path uses too. This
/// is already part of this package's resolved dependency graph transitively
/// (Router's own library target needs the *full* mlx-swift-lm product set
/// to build at all), so declaring these two directly for the targets below
/// adds no new MLX/C++ compilation, only linking.
private let mlxPackage = "mlx-swift-lm"

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
]

/// Resolves the active Xcode install's `Contents` directory (the parent of
/// its embedded `Developer/…` tree), or `nil` if `xcode-select` isn't
/// available or its output isn't a usable path (e.g. command-line-tools-only,
/// which couldn't build this package's FoundationModels-framework code at
/// all anyway).
///
/// Apple's test-only `Evaluations` framework (imported directly by
/// `FoundationModelsMultitoolIntegrationTests`'
/// `NativeToolCallEvaluation.swift`) lives under the Xcode toolchain's
/// platform `Developer/Library/Frameworks` (the same place `XCTest
/// .framework`/`Testing.framework` live). `swift test`'s
/// `swiftpm-testing-helper` arranges the search paths that resolve it there,
/// but CI's gated integration job invokes the built `.xctest` bundle
/// directly via `xcrun xctest <bundle>` (see `swift-ci.yaml`'s integration
/// job) — bypassing that helper — so the test binary's default rpaths
/// (`.build/…/Products/Debug`, its `PackageFrameworks` subdirectory) don't
/// include it, and the bundle fails to load at all (`dlopen`: `Library not
/// loaded`, naming the *relative* `@rpath/Developer/Platforms/MacOSX
/// .platform/Developer/Library/Frameworks/Evaluations.framework/…`) —
/// resolved once an rpath entry for the Xcode `Contents` directory (the
/// parent of that embedded `Developer/…` path) is present, fed into
/// `integrationTestLinkerSettings` below.
///
/// - Returns: the `Contents` directory's absolute path, or `nil`.
private func xcodeContentsDirectory() -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    process.arguments = ["-p"]
    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let developerPath = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !developerPath.isEmpty
        else { return nil }
        return URL(fileURLWithPath: developerPath).deletingLastPathComponent().path
    } catch {
        return nil
    }
}

/// Linker settings that let `FoundationModelsMultitoolIntegrationTests`'
/// built `.xctest` bundle actually *load*, not just link, when CI's gated
/// integration job invokes it directly via `xcrun xctest` — an `-rpath`
/// pointing at `xcodeContentsDirectory()`, computed fresh (never hardcoded)
/// so it resolves correctly on any machine/CI runner with a full Xcode
/// install — the same install this package's macOS-27-SDK build already
/// requires.
///
/// It's empty (no extra flags) when `xcodeContentsDirectory()` can't resolve
/// one.
private let integrationTestLinkerSettings: [LinkerSetting] = {
    guard let xcodeContentsDirectory = xcodeContentsDirectory() else { return [] }
    return [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", xcodeContentsDirectory])]
}()

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
        swissArmyHammerPackage(name: routerDependencyName),
        swissArmyHammerPackage(name: metadataRegistryDependencyName),
        // Only the M9 CLI executable and the gated integration test target
        // below link products from these three — see their documentation
        // above.
        swissArmyHammerPackage(name: mlxPackage, branch: "foundationmodels-fixes"),
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
        // that triggers findAPIs then a multi-tool runCode." Links
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
                // `LanguageModelSession(tools: [multiTool, findAPIsTool])`, not
                // `MultiToolAgent`'s retired hand-rolled loop.
                .product(name: "MLXFoundationModels", package: mlxPackage),
            ] + liveLoaderMLXProducts + hubProducts,
            path: "\(testsPath)\(packageName)IntegrationTests",
            // See `integrationTestLinkerSettings`'s documentation: without
            // this, CI's gated integration job (which invokes this target's
            // built `.xctest` bundle directly via `xcrun xctest`, bypassing
            // `swift test`'s `swiftpm-testing-helper`) fails to load the
            // bundle at all (`dlopen`: `Library not loaded`) resolving
            // `NativeToolCallEvaluation.swift`'s `import Evaluations`.
            linkerSettings: integrationTestLinkerSettings
        ),
    ]
)
