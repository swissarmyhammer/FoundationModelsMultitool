// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

/// The name of this Swift package.
private let packageName = "FoundationModelsMultitool"

/// The name of the M9 sample CLI library target (and its Sources/ subdirectory).
///
/// The CLI's whole implementation — `CLIRunner`, `DemoTools` — is a library
/// rather than part of the executable, for one structural reason: a package
/// cannot depend on another package's *executable* target at all, and the
/// nested integration package (`IntegrationTests/Package.swift`) has to reach
/// `CLIRunner.demoProfile`, `CLIRunner.embeddingModel`,
/// `CLIRunner.run(arguments:resolve:output:)` and `CLIRunner.ExitCode`. Those
/// four are the library's whole `public` surface; everything else stays
/// `internal`, where `"\(packageName)Tests"` reaches it with `@testable`.
private let cliLibraryTargetName = "MultitoolCLI"

/// The name of the M9 sample CLI executable target (and its Sources/ subdirectory).
///
/// `main.swift` alone — it calls `CLIRunner.run(arguments:)` from
/// `cliLibraryTargetName` and holds no logic of its own.
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
/// linked by the library target and the unit test target below, and by the
/// integration test target of the nested package.
private let metadataRegistryDependencyName = "FoundationModelsMetadataRegistry"

/// The name of the FoundationModelsExtras dependency package.
///
/// It is wired as a remote dependency (`main` branch) the same way
/// `routerDependencyName` is. It carries the family's shared
/// `ProcessRegistry` — the table of live process-group leaders, and the
/// `atexit` sweep behind `ProcessRegistry.global` — which the shell
/// capability's `ShellRunner` registers each spawned child into. This package
/// held a copy of that type before; the copy is gone, thus every consumer in
/// the host process now shares one registry and one sweep. The library target
/// and the unit test target below both link the product.
private let extrasDependencyName = "FoundationModelsExtras"

/// Base URL for packages published under the swissarmyhammer GitHub
/// organization — `routerDependencyName`, `metadataRegistryDependencyName`
/// and `extrasDependencyName` are fetched from here.
private let swissArmyHammerPackageOrgURL = "git@github.com:swissarmyhammer/"

/// Builds a `.package(url:branch:)` dependency for a package hosted under
/// `swissArmyHammerPackageOrgURL`, tracking `branch` (`mainBranch` by default).
///
/// This is used for `routerDependencyName`,
/// `metadataRegistryDependencyName` and `extrasDependencyName` (the default
/// branch), and for `mlxPackage` (its published `stable` branch).
private func swissArmyHammerPackage(name: String, branch: String = mainBranch) -> Package.Dependency {
    .package(url: "\(swissArmyHammerPackageOrgURL)\(name).git", branch: branch)
}

/// The MLX-backed model package `FoundationModelsRouter` itself depends on
/// (`../FoundationModelsRouter/Package.swift`'s `mlxPackage`).
///
/// Taken by URL from its published `stable` branch — see `mlxStableBranch`.
///
/// Only three of its products are declared directly here (not Router's own
/// broader `mlxProducts` set), and all three are in `liveLoaderMLXProducts`:
/// `MLXLMCommon`, whose `Downloader`/`TokenizerLoader` protocols a live
/// `LiveModelLoader` is constructed over; `MLXHuggingFace`, whose
/// `#hubDownloader()`/`#huggingFaceTokenizerLoader()` macros adapt a real
/// Hugging Face Hub client into those protocols — the same macros Router's
/// own gated `…IntegrationTests` target uses, and the M9 `MultitoolCLI`
/// library's default (production) model-resolution path uses too; and
/// `MLXVLM`, for its model registry alone (see `liveLoaderMLXProducts`).
///
/// `MLXFoundationModels` — the module `LiveModelLoader` is written over — is
/// deliberately *not* declared here. Router's own library target names it, so
/// it reaches every target below through the `FoundationModelsRouter` product,
/// and no target here names a symbol of it: this package builds no model and
/// no session of its own. Dropping it was verified against the case that
/// would break a wrong drop — a real-model run of `CLISmokeTests`, which
/// resolves and loads a real model — as well as `swift build --build-tests`
/// and `swift test`.
///
/// This package's resolved dependency graph already carries all of
/// mlx-swift-lm transitively (Router's own library target needs the *full*
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
/// live `LiveModelLoader` through the `MLXHuggingFace` macros (the M9
/// `MultitoolCLI` library, and through it the executable). This
/// mirrors `../FoundationModelsRouter/Package.swift`'s own `hubProducts`
/// (same package identities and version floors as Router's own gated
/// suite, so a machine that already ran Router's gated suite shares the
/// resolved checkout).
private let huggingFacePackage = "swift-huggingface"

/// The Swift Transformers tokenizer package, paired with
/// `huggingFacePackage` above — linked by the M9 `MultitoolCLI` library.
private let transformersPackage = "swift-transformers"

/// The Hub client + tokenizer products a live `LiveModelLoader` needs (via
/// the `MLXHuggingFace` macros) — linked by the M9 `MultitoolCLI` library.
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
    // binary. Without this link a checkpoint registered in `VLMModelFactory`
    // alone throws `unsupportedModelType` after paying for the whole
    // download. Which checkpoint is pinned is not this manifest's to state:
    // `CLIRunner.generationModel` is the single place this package names a
    // generation model, and the pin it names today carries `model_type:
    // qwen3_5`, which both `LLMModelFactory` and `VLMModelFactory` register.
    // So this link is what keeps a swap to a VLM-only checkpoint resolving —
    // Muse Glimmer (`muse_glimmer`), which held the slot before, is one —
    // rather than what the shipped pin needs today.
    .product(name: "MLXVLM", package: mlxPackage),
]

/// The child-process package the shell capability spawns commands with.
///
/// `ShellRunner` and `SandboxPreflight` import its `Subprocess` module: one
/// starts a command and reads its output, the other starts the sandbox canary.
/// The package stands under the `swiftlang` organization — the former
/// `apple/swift-subprocess` path answers 404.
private let subprocessPackage = "swift-subprocess"

/// The products of `subprocessPackage`, linked by the library target and the
/// unit test target below.
///
/// The shell capability is the one consumer. `hubProducts` and
/// `liveLoaderMLXProducts` above group their own products the same way.
private let shellProducts: [Target.Dependency] = [
    .product(name: "Subprocess", package: subprocessPackage)
]

/// The Model Context Protocol wire library the MCP capability speaks through.
///
/// eventplan.md § "Consolidation of the siblings" moves the FoundationModelsMCP
/// package into this one as `Capabilities/MCP`. The ported files — `MCPServer`,
/// `StdioServerProcess`, the `SchemaConverter` / `GeneratedContentCodec` pair,
/// `ToolContentRenderer` with its `RenderBudget`, and the `ToolCatalog` — are
/// written over this package's `MCP` module: its `Client`, its `Transport`,
/// and its `Tool` / `Value` wire types. The package stands under the
/// `modelcontextprotocol` organization, so neither helper above fits it.
///
/// The sdk depends on `swift-log` for its own logging. This package does NOT
/// declare `swift-log`: it logs with `os.Logger` (see `MultiTool.swift`), and
/// each ported MCP file does the same. `swift-log` reaches the build
/// transitively and no target here names a symbol of it.
private let mcpPackage = "swift-sdk"

/// The products of `mcpPackage`, linked by the library target and the unit
/// test target below.
///
/// The MCP capability is the one consumer. `hubProducts`,
/// `liveLoaderMLXProducts` and `shellProducts` group their own products the
/// same way.
private let mcpProducts: [Target.Dependency] = [
    .product(name: "MCP", package: mcpPackage)
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
///
/// **This manifest declares no integration test target, and that is the whole
/// unit/integration split.** The real-model suite is its own package,
/// `IntegrationTests/Package.swift`, which depends on this one by path. So
/// `swift test` here runs the unit tests and nothing else — not because a
/// person remembered a flag, and not because an environment variable was left
/// unset, but because SwiftPM cannot see a target this manifest does not
/// declare. The real-model suite runs under
/// `swift test --package-path IntegrationTests --no-parallel`.
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
        ),
        // Consumed by `IntegrationTests/Package.swift`, which cannot depend on
        // the `cliTargetName` executable — see `cliLibraryTargetName`.
        .library(
            name: cliLibraryTargetName,
            targets: [cliLibraryTargetName]
        ),
    ],
    dependencies: [
        swissArmyHammerPackage(name: routerDependencyName),
        swissArmyHammerPackage(name: metadataRegistryDependencyName),
        swissArmyHammerPackage(name: extrasDependencyName),
        // Only the M9 `cliLibraryTargetName` library below links products from
        // these three — see their documentation above.
        swissArmyHammerPackage(name: mlxPackage, branch: mlxStableBranch),
        huggingFaceOrgPackage(name: huggingFacePackage, from: "0.9.0"),
        huggingFaceOrgPackage(name: transformersPackage, from: "1.3.0"),
        // The package of `shellProducts`. It stands under an organization of
        // its own, so neither helper above fits it.
        //
        // The version is an EXACT pin, and it is the pin
        // `../FoundationModelsShelltool/Package.swift` states today. The shell
        // capability moves from that package into this one, so the two must
        // resolve the same version: a pre-release carries no compatible-range
        // promise, and a floor would let one package move alone.
        .package(url: "https://github.com/swiftlang/\(subprocessPackage).git", exact: "1.0.0-beta.1"),
        // The package of `mcpProducts` — see its documentation above. A
        // semantic-version floor, as `huggingFaceOrgPackage(name:from:)` takes,
        // because the sdk publishes tagged releases with a compatible-range
        // promise.
        .package(url: "https://github.com/modelcontextprotocol/\(mcpPackage).git", from: "0.12.1"),
    ],
    targets: [
        // Links `shellProducts` for the shell capability this library takes
        // over from `../FoundationModelsShelltool`, and `mcpProducts` for the
        // MCP capability it takes over from `../FoundationModelsMCP`.
        .target(
            name: packageName,
            dependencies: [
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: metadataRegistryDependencyName, package: metadataRegistryDependencyName),
                .product(name: extrasDependencyName, package: extrasDependencyName),
            ] + shellProducts + mcpProducts,
            path: "\(sourcesPath)\(packageName)"
        ),
        // M9: the sample CLI's whole implementation — plan.md "M9 — Sample CLI.
        // A prompt that triggers searchTools then a multi-tool runCode." Links
        // `liveLoaderMLXProducts` + `hubProducts` (see their documentation
        // above) so its default, production model-resolution path can
        // construct a real `LiveModelLoader` — the same live-inference wiring
        // the nested integration package drives — making this a genuinely
        // runnable demo rather than a stub.
        .target(
            name: cliLibraryTargetName,
            dependencies: [
                .target(name: packageName),
                .product(name: routerDependencyName, package: routerDependencyName),
            ] + liveLoaderMLXProducts + hubProducts,
            path: "\(sourcesPath)\(cliLibraryTargetName)"
        ),
        // The process entry point: `main.swift` and nothing else. It links the
        // library above, so every product that library declares reaches this
        // binary transitively — `MLXVLM`'s runtime factory registry included.
        .executableTarget(
            name: cliTargetName,
            dependencies: [
                .target(name: cliLibraryTargetName)
            ],
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
        // `shellProducts` and `mcpProducts` again: `DependencyReachTests`
        // imports `Subprocess` and `MCP` directly, and this target declares
        // each product it imports, as it does for the two products above.
        .testTarget(
            name: "\(packageName)Tests",
            dependencies: [
                .target(name: packageName),
                .target(name: cliLibraryTargetName),
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: metadataRegistryDependencyName, package: metadataRegistryDependencyName),
                .product(name: extrasDependencyName, package: extrasDependencyName),
            ] + shellProducts + mcpProducts,
            path: "\(testsPath)\(packageName)Tests",
            resources: [
                // Golden files pinning `ToolAPIRenderer`'s rendered surface
                // (M2). Tests read these directly off disk via `#filePath`,
                // not `Bundle.module`; declared as a resource purely so
                // SwiftPM doesn't warn about an unhandled source-tree file.
                .copy("Goldens"),
                // Golden vectors that pin the files capability's hashline
                // anchor dialect against the Rust `swissarmyhammer-hashline`
                // crate. `HashlineTests` loads these through `Bundle.module`.
                // The sibling `Fixtures/` directory must NOT get a resource
                // rule: it holds compiled `.swift` files, and a resource rule
                // would stop their compilation and break this target.
                .copy("FilesGoldens"),
                // A corpus of real-world MCP tool `inputSchema` documents, ported
                // from `../FoundationModelsMCP`. The `SchemaConverter` suites
                // load these through `Bundle.module`, as `HashlineTests` loads
                // its goldens.
                .copy("MCPFixtures"),
            ]
        ),
    ]
)
