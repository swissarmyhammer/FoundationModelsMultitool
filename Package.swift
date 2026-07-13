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
/// Wired as a remote dependency (`main` branch) the same way
/// `routerDependencyName` is — the registry is already consumable by URL
/// (`../FoundationModelsMetadataRegistry/Package.swift`'s own `main` is in
/// sync with `origin/main`), so no registry-side change is needed here.
/// Supplies `SearchableMetadata`/`MetadataSearcher` — the catalog-search
/// surface `FindAPIsTool`'s registry-backed selection tier (`SelectionTier`,
/// generalizing this package's own former `Librarian`) is built over —
/// linked by the library target, the unit test target, and the gated
/// integration test target below.
private let metadataRegistryDependencyName = "FoundationModelsMetadataRegistry"

/// Base URL for packages published under the swissarmyhammer GitHub
/// organization — `routerDependencyName`, `metadataRegistryDependencyName`,
/// and `mlxPackage` are all fetched from here.
private let swissArmyHammerOrgURL = "https://github.com/swissarmyhammer/"

/// Builds a `.package(url:branch:)` dependency for a package hosted under
/// `swissArmyHammerOrgURL`, tracking `mainBranch`. Used for
/// `routerDependencyName` and `metadataRegistryDependencyName`, whose
/// declarations would otherwise be near-verbatim copies differing only in
/// the package name.
private func swissArmyHammerPackage(name: String) -> Package.Dependency {
    .package(url: "\(swissArmyHammerOrgURL)\(name)", branch: mainBranch)
}

/// The MLX-backed model package `FoundationModelsRouter` itself depends on
/// (`../FoundationModelsRouter/Package.swift`'s `mlxPackage`). Only two of
/// its products are declared directly here (not Router's own broader
/// `mlxProducts` set): `MLXLMCommon`, whose `Downloader`/`TokenizerLoader`
/// protocols a live `LiveModelLoader` is constructed over, and
/// `MLXHuggingFace`, whose `#hubDownloader()`/`#huggingFaceTokenizerLoader()`
/// macros adapt a real Hugging Face Hub client into those protocols — the
/// same macros Router's own gated `…IntegrationTests` target uses, and the
/// M9 `multitool-cli` executable's default (production) model-resolution
/// path uses too. Already part of this package's resolved dependency graph
/// transitively (Router's own library target needs the *full* mlx-swift-lm
/// product set to build at all), so declaring these two directly for the
/// targets below adds no new MLX/C++ compilation, only linking.
private let mlxPackage = "mlx-swift-lm"

/// Base URL for packages published under the Hugging Face GitHub
/// organization — `huggingFacePackage` and `transformersPackage` are both
/// fetched from here.
private let huggingFaceOrgURL = "https://github.com/huggingface/"

/// Builds a `.package(url:from:)` dependency for a package hosted under
/// `huggingFaceOrgURL`, pinned to a minimum semantic version floor. Used for
/// `huggingFacePackage` and `transformersPackage`, whose declarations would
/// otherwise be near-verbatim copies differing only in the package name and
/// version floor — mirrors `swissArmyHammerPackage(name:)` above.
private func huggingFaceOrgPackage(name: String, from version: Version) -> Package.Dependency {
    .package(url: "\(huggingFaceOrgURL)\(name)", from: version)
}

/// Hugging Face Hub client and tokenizer packages. Needed by every target
/// below that constructs a real, live `LiveModelLoader` through the
/// `MLXHuggingFace` macros (the gated integration test target, and the M9
/// `multitool-cli` executable) — mirrors
/// `../FoundationModelsRouter/Package.swift`'s own `hubProducts` (same
/// package identities and version floors as Router's own gated suite, so a
/// machine that already ran Router's gated suite shares the resolved
/// checkout).
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

/// Resolves the active Xcode installation's `Contents` directory (the
/// parent of `Contents/Developer`) via `xcode-select -p`.
///
/// A discovered, real runtime gap motivates this: `Sources/
/// FoundationModelsMultitool/Agent/AgentEvaluators.swift` (M6.5b) `import`s
/// Apple's `Evaluations` framework — pure test infrastructure per plan.md,
/// but declared in the *library* target, so its autolink metadata is part
/// of the compiled `FoundationModelsMultitool` module and propagates to
/// every consumer, including the M9 `multitool-cli` executable below.
/// `Evaluations.framework` lives under the Xcode toolchain's platform
/// `Developer/Library/Frameworks` (the same place `XCTest.framework`/
/// `Testing.framework` live) — Xcode's `xctest` launcher arranges the
/// search paths that resolve it there, which is why `swift test` runs
/// fine, but a plain `swift build`/`swift run` executable's default rpaths
/// (`.build/…/Products/Debug`, its `PackageFrameworks` subdirectory) don't
/// include it, so the executable fails to launch at all (`dyld: Library
/// not loaded`) — confirmed against this Xcode install: the failing load
/// command is the *relative* `@rpath/Developer/Platforms/MacOSX.platform/
/// Developer/Library/Frameworks/Evaluations.framework/…`, which resolves
/// once an rpath entry for the Xcode `Contents` directory (the parent of
/// that embedded `Developer/…` path) is present — exactly what this
/// function resolves, fed into `cliLinkerSettings` below.
///
/// This is a workaround for the *symptom* (an unresolved runtime search
/// path), not the underlying design gap — `Evaluations` belongs in a
/// test-only target, not the shipped library — which is out of the M9
/// executable-target task's scope to restructure.
///
/// - Returns: the `Contents` directory's absolute path, or `nil` if
///   `xcode-select` isn't available or its output isn't a usable path
///   (e.g. command-line-tools-only, which couldn't build this package's
///   FoundationModels-framework code at all anyway).
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

/// Linker settings that make `multitool-cli` able to actually *launch*, not
/// just link — an `-rpath` pointing at `xcodeContentsDirectory()`, computed
/// fresh (never hardcoded) so it resolves correctly on any machine/CI
/// runner with a full Xcode install — the same install this package's
/// macOS-27-SDK build already requires. Empty (no extra flags) when
/// `xcodeContentsDirectory()` can't resolve one — see its documentation for
/// the full story.
private let cliLinkerSettings: [LinkerSetting] = {
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
        swissArmyHammerPackage(name: routerDependencyName),
        swissArmyHammerPackage(name: metadataRegistryDependencyName),
        // Only the M9 CLI executable and the gated integration test target
        // below link products from these three — see their documentation
        // above.
        .package(
            url: "\(swissArmyHammerOrgURL)\(mlxPackage)",
            branch: "foundationmodels-fixes"
        ),
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
            path: "\(sourcesPath)\(cliTargetName)",
            // See `cliLinkerSettings`'s documentation: without this, the
            // built executable fails to launch (`dyld: Library not
            // loaded`) trying to resolve the test-only `Evaluations`
            // framework the library target transitively imports.
            linkerSettings: cliLinkerSettings
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
                .target(name: cliTargetName),
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: metadataRegistryDependencyName, package: metadataRegistryDependencyName),
            ] + liveLoaderMLXProducts + hubProducts,
            path: "\(testsPath)\(packageName)IntegrationTests"
        ),
    ]
)
