// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The name of the package under test, and the directory `..` holds.
private let productPackageName = "FoundationModelsMultitool"

/// The name of the FoundationModelsRouter dependency package.
private let routerDependencyName = "FoundationModelsRouter"

/// The name of the FoundationModelsMetadataRegistry dependency package.
private let metadataRegistryDependencyName = "FoundationModelsMetadataRegistry"

/// The name of the FoundationModelsExtras dependency package.
///
/// The root manifest links its core product for `ProcessRegistry`. This
/// manifest links its `Operations` product: the `@Operation` macro and
/// `OperationTool` that `Fixtures/IntegrationNotesOperationTool.swift` builds
/// the one real operation tool of this suite from.
private let extrasDependencyName = "FoundationModelsExtras"

/// The MLX-backed model package a live `LiveModelLoader` is built over.
private let mlxPackage = "mlx-swift-lm"

/// The Hugging Face Hub client package.
private let huggingFacePackage = "swift-huggingface"

/// The Swift Transformers tokenizer package.
private let transformersPackage = "swift-transformers"

/// SwiftPM manifest for the integration suite: the real-model scenarios, and
/// the live web tests that load no model (`Web/`, web.md § "Testing",
/// Level 2).
///
/// **Why this is a package of its own.** `swift test` at the repository root
/// must run the unit tests and nothing else, and it must do that structurally
/// rather than by convention. `swift test --filter`/`--skip` make separate
/// *runs* easy, but SwiftPM offers no manifest-level way to hold a target out
/// of the default run, so a bare `swift test` would still start the real-model
/// suite — 12 to 15 minutes locally. A package the root manifest never names
/// is invisible to the root's `swift test`, so the split is a property of the
/// build graph rather than of anyone's memory.
///
/// **The environment rule.** The predecessor of this suite read an opt-in
/// environment variable to decide if it ran. Then a green run that measured
/// nothing looked the same as a green run that measured everything. Thus a
/// test here never reads the environment to decide if it runs, and no test
/// may start to do so. A test can read a value from the environment as
/// configuration when the test always runs.
///
/// There is one exception, by the user's decision of 2026-09-26 (final,
/// web.md § "Testing", Level 2): each of the six keyed live tests of
/// `Web/KeyedProviderLiveTests.swift` runs only when its API key (or
/// `SEARXNG_URL`) is set. When the key is not set, the test is skipped, not
/// failed, and the skip comment names the variable. This is a written
/// exception to the review rule `test-integrity/test-partitioning`, for these
/// six tests only. `Web/Support/LiveProviderSetting.swift` holds the one
/// enable condition, and `Web/LiveProviderSettingTests.swift` checks it with
/// no real key. No other test reads the environment to decide if it runs.
///
/// The two commands are:
///
///     swift test                                                  # unit tests
///     swift test --package-path IntegrationTests --no-parallel    # this suite
///
/// `--no-parallel` is not a preference. Every real-model scenario here queues behind
/// `liveProfileTurnstile`, which admits one live scenario at a time because
/// concurrent generation destroys grounding. Swift Testing runs suites
/// concurrently and starts a test's `.timeLimit` when the test starts, so a
/// parallel run spends the limit on queue time and a queued suite fails in
/// the same way as a hang. `LiveRouterFixture.swift` records the measurement.
/// The live web suites of `Web/` load no model and do not queue behind the
/// turnstile. For them, `--no-parallel` and `.serialized` on each suite keep
/// the request rate to each web provider low.
///
/// **The compile coupling this package owes CI.** While the suite was a target
/// of the root manifest, a broken integration test broke a plain
/// `swift build --build-tests` at the root, so it could never rot unnoticed
/// between real-model runs. A separate package ends that coupling: the root
/// build no longer compiles these files at all. `.github/workflows/ci.yml`
/// restores it — the unit job runs
/// `swift build --package-path IntegrationTests --build-tests` on **every**
/// run, whether or not the expensive suite executes. A build of this package
/// is cheap; only the run is expensive. Do not drop that step.
///
/// **Why the dependency list below repeats the root manifest's.** A SwiftPM
/// manifest cannot import code from another manifest, and a package may only
/// name the products of packages it declares itself. The declarations are
/// therefore restated here rather than shared, and each URL and requirement
/// matches `../Package.swift` exactly — a mismatch is a resolution conflict,
/// not a second opinion. `../Package.swift` carries the reasoning behind each
/// one; this manifest carries only what SwiftPM needs to resolve them.
let package = Package(
    name: "FoundationModelsMultitoolIntegrationTests",
    // Commit to macOS 27 / FoundationModels v2, exactly as `../Package.swift`
    // does; a lower floor here would not resolve against it.
    platforms: [
        .macOS("27.0")
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "git@github.com:swissarmyhammer/\(routerDependencyName).git", branch: "main"),
        .package(url: "git@github.com:swissarmyhammer/\(metadataRegistryDependencyName).git", branch: "main"),
        .package(url: "git@github.com:swissarmyhammer/\(extrasDependencyName).git", branch: "main"),
        .package(url: "git@github.com:swissarmyhammer/\(mlxPackage).git", branch: "stable"),
        .package(url: "https://github.com/huggingface/\(huggingFacePackage)", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/\(transformersPackage)", from: "1.3.0"),
    ],
    targets: [
        // M6.5a: the real-model suite — plan.md M6.5 + Testing strategy
        // "Integration tests". Each scenario outside `Web/` resolves a real
        // profile through `Router` and generates on the GPU, so this is the
        // target CI runs in a job of its own. The suites of `Web/` send real
        // web requests and load no model.
        //
        // `MultitoolCLI` is the library half of the sample CLI. The suite
        // resolves `CLIRunner.demoProfile` rather than a pin of its own, so it
        // measures the configuration a host really gets; a package cannot
        // depend on another package's executable target, which is why that
        // logic is a library in the first place.
        //
        // The MLX and Hugging Face products are the live-inference wiring:
        // `MLXLMCommon` and `MLXHuggingFace` for the
        // `#hubDownloader()`/`#huggingFaceTokenizerLoader()` macros a real
        // `LiveModelLoader` is built from, `HuggingFace` and `Tokenizers` for
        // what those macros expand into, and `MLXVLM` for its model registry
        // alone — `MLXLMCommon`'s `ModelFactoryRegistry` resolves its built-in
        // trampolines with `NSClassFromString`, so a checkpoint registered in
        // `VLMModelFactory` alone throws `unsupportedModelType` after paying
        // for the whole download unless that module is linked into the binary.
        // `../Package.swift`'s `liveLoaderMLXProducts` states this at length.
        .testTarget(
            name: "FoundationModelsMultitoolIntegrationTests",
            dependencies: [
                .product(name: productPackageName, package: productPackageName),
                .product(name: "MultitoolCLI", package: productPackageName),
                // The scripted MCP test server, a test-support product of the
                // root package — `../Package.swift`'s `testServerTargetName`.
                // A gated MCP scenario scripts its server in-process through
                // it, or spawns the `mcp-test-server` binary the root build
                // produces.
                .product(name: "MCPTestServer", package: productPackageName),
                // The shared gate of the test support code, another test-support
                // product of the root package — `../Package.swift`'s
                // `testConcurrencyTargetName`. `liveProfileTurnstile` is one of
                // them, and it holds this target to one live scenario at a time.
                .product(name: "TestConcurrency", package: productPackageName),
                // The model-free half of this suite's own harness, a third
                // test-support product of the root package —
                // `../Package.swift`'s `scenarioGradingTargetName`. It carries
                // the fixture tools every scenario below mounts, their call
                // log, the readers over one run's record, the failure-mode
                // instrument and the grading rules. The root package grades
                // those rules on each commit; this target drives them against
                // a real model.
                .product(name: "ScenarioGrading", package: productPackageName),
                // The shared web test support, a fourth test-support product
                // of the root package — `../Package.swift`'s
                // `multitoolTestSupportTargetName`. The live web suites of
                // `Web/` call each web verb through its `WebVerbCall`, and
                // decode a `runCode` output through its `RunOutput`, the same
                // helpers that the unit tests use.
                .product(name: "MultitoolTestSupport", package: productPackageName),
                // The `@Operation` macro and `OperationTool` — see
                // `extrasDependencyName`. The root package expands an
                // `OperationTool` into one verb for each operation, and the
                // suite that proves that with a real model builds its fixture
                // from this product. The core `FoundationModelsExtras` product
                // is not linked: no file of this target names a symbol of it.
                .product(name: "Operations", package: extrasDependencyName),
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: metadataRegistryDependencyName, package: metadataRegistryDependencyName),
                .product(name: "MLXLMCommon", package: mlxPackage),
                .product(name: "MLXHuggingFace", package: mlxPackage),
                .product(name: "MLXVLM", package: mlxPackage),
                .product(name: "HuggingFace", package: huggingFacePackage),
                .product(name: "Tokenizers", package: transformersPackage),
            ],
            path: "Tests/FoundationModelsMultitoolIntegrationTests"
        )
    ]
)
