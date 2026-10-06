// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

/// The name of this Swift package.
private let packageName = "FoundationModelsMultitool"

/// The git branch tracked by the `.package(url:branch:)` declaration for
/// `metadataRegistryDependencyName` below, and the branch that
/// `swissArmyHammerPackage(name:)` tracks.
///
/// The `mcpPackage` declaration below names it too. That dependency is a fork
/// this package follows on its `main` branch, and it does not go through the
/// helper — see `mcpPackage`.
private let mainBranch = "main"

/// The name of the FoundationModelsRouter dependency package.
///
/// The library target does not link it: FoundationModelsExtras owns tool
/// hosting (`extrasDependencyName`). `scenarioGradingTargetName` and the unit
/// test target link it for `TranscriptEvent` and `SubmissionID`, which stay
/// in Router.
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
/// the host process now shares one registry and one sweep.
///
/// It also owns tool hosting: `ToolContext`, `BackgroundTool`, `ToolMount`,
/// `ToolMounting`, `SubmissionBoundaryTool`, `LostRunError`, `ToolCallReport`,
/// `OperationEvent` and the `RunPlane` that mints each completion token. The
/// library target takes each of these from here, and not from Router. The
/// library target and the unit test target below both link the product.
private let extrasDependencyName = "FoundationModelsExtras"

/// Base URL for packages published under the swissarmyhammer GitHub
/// organization — `routerDependencyName`, `metadataRegistryDependencyName`
/// and `extrasDependencyName` are fetched from here.
private let swissArmyHammerPackageOrgURL = "git@github.com:swissarmyhammer/"

/// Builds a `.package(url:branch:)` dependency for a package hosted under
/// `swissArmyHammerPackageOrgURL`, tracking `mainBranch`.
///
/// This is used for `routerDependencyName`,
/// `metadataRegistryDependencyName` and `extrasDependencyName`.
private func swissArmyHammerPackage(name: String) -> Package.Dependency {
    .package(url: "\(swissArmyHammerPackageOrgURL)\(name).git", branch: mainBranch)
}

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
/// The shell capability is the one consumer. `mcpProducts` below groups its
/// own products the same way.
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
/// and its `Tool` / `Value` wire types.
///
/// **A fork.** The package comes from `swissarmyhammer/swift-sdk`. That
/// repository is this organization's fork of `modelcontextprotocol/swift-sdk`.
/// Upstream writes the module and each type above. The fork adds no module and
/// changes no name, thus each ported file stays the same.
///
/// The fork exists for one correction, card `^qba8j6x`. The upstream
/// `HTTPClientTransport` keeps one `lastEventID` for all of its SSE streams
/// together. Thus a stream that connects again asks the server for the events
/// of a different stream. The fork carries the correction, and upstream does
/// not carry it yet.
/// The dependency goes back to `modelcontextprotocol` when a released version
/// there carries that correction, and not before. `MCPConsolidationTests`
/// reads this URL and fails on a change back to upstream, thus a commit that
/// goes back must change that suite too.
///
/// The helper above does not fit it. `swissArmyHammerPackage(name:)`
/// builds the `git@github.com:` URL of the three packages this repository
/// develops. This one is a public fork, and it keeps the HTTPS URL it always
/// had, thus a machine with no SSH key resolves it. The organization name is
/// the whole change from the upstream URL.
///
/// The sdk depends on `swift-log` for its own logging. Its `Transport`
/// protocol requires a `Logging.Logger` property. This package declares
/// `swift-log` itself — see `loggingPackage`.
private let mcpPackage = "swift-sdk"

/// The products of `mcpPackage`, linked by the library target and the unit
/// test target below.
///
/// The MCP capability is the one consumer. `shellProducts` groups its own
/// products the same way.
private let mcpProducts: [Target.Dependency] = [
    .product(name: "MCP", package: mcpPackage)
]

/// The logging API package (apple/swift-log).
///
/// The OpenTelemetry design of 2026-09-28: a library of the family uses the
/// telemetry APIs only — `swift-distributed-tracing`, `swift-log` and
/// `swift-metrics`. It links no backend and it bootstraps none. An executable
/// depends on `swift-otel` and bootstraps the exporters. Until one does, each
/// logger writes through the default handler of swift-log, and each metric
/// does nothing. `PackageManifestTests` reads this manifest and fails when a
/// library target links a `swift-otel` product.
///
/// `Tracing` is not declared here. It reaches the library target through
/// FoundationModelsExtras, which links it for the tool span. The version floor
/// is the floor that Extras states, thus the two packages resolve one version.
private let loggingPackage = "swift-log"

/// The metrics API package (apple/swift-metrics). See `loggingPackage` for
/// the API-only rule. The version floor is the floor that Extras states.
private let metricsPackage = "swift-metrics"

/// The products of `loggingPackage` and `metricsPackage`, linked by the
/// library target below.
///
/// `MultitoolTelemetry` holds the log label, the log metadata keys, the metric
/// names and the dimension keys that these APIs carry. `shellProducts`,
/// `mcpProducts` and `webProducts` group their own products the same way.
private let telemetryProducts: [Target.Dependency] = [
    .product(name: "Logging", package: loggingPackage),
    .product(name: "Metrics", package: metricsPackage),
]

/// The products that the unit test target uses to read back the telemetry of
/// the library target.
///
/// `TelemetryTestSupport` is the test helper of FoundationModelsExtras.
/// `TelemetryCapture` gives a test an in-memory tracer, log handler and
/// metrics factory for the task of the test. It bootstraps the logging system
/// one time for each process. Thus no code of the unit test target calls
/// `LoggingSystem.bootstrap`. `Logging` gives the suites the `Logger.Metadata`
/// type. `TelemetryTestSupport` itself gives them the
/// `TelemetryCapture.LogRecord` type of each log record. `MetricsTestKit` gives
/// them the `TestMetrics` factory of the capture, and its `TestCounter` and
/// `TestTimer` types. A library target does not link these products.
private let telemetryTestProducts: [Target.Dependency] = [
    .product(name: "TelemetryTestSupport", package: extrasDependencyName),
    .product(name: "Logging", package: loggingPackage),
    .product(name: "MetricsTestKit", package: metricsPackage),
]

/// The time-sortable identifier package (yaslab/ULID.swift).
///
/// FoundationModelsExtras declares `ElicitationRequest.elicitationId` as a
/// `ULID`, thus the library target makes a `ULID` for each elicitation it
/// raises (`MultiTool+SandboxGlobals.swift` and
/// `MCPServer+Elicitation.swift`). Router re-exported this module before, and
/// the library does not depend on Router now. Thus the library target links
/// the product itself. The version floor is the floor that Extras states.
private let ulidPackage = "ULID.swift"

/// The products of `ulidPackage`, linked by the library target below.
///
/// `shellProducts`, `mcpProducts` and `webProducts` group their own products
/// the same way.
private let ulidProducts: [Target.Dependency] = [
    .product(name: "ULID", package: ulidPackage)
]

/// The HTML parser package the web capability reads pages with.
///
/// web.md § "Decisions", item 1, selects it. SwiftSoup is pure Swift, has an
/// MIT license, and parses HTML5 into a DOM that CSS selectors can query.
/// Foundation `XMLDocument` with `.documentTidyHTML` needs no new dependency,
/// but its tidy step is not an HTML5 parser, and it changes or drops modern
/// markup. `HTMLMarkdown` walks the SwiftSoup DOM, and the search providers
/// that read a results page use its selectors.
///
/// The version is a floor at the release that was current when the dependency
/// was added. SwiftSoup follows semantic versions, thus a floor takes each
/// compatible release.
private let htmlParserPackage = "SwiftSoup"

/// The products of `htmlParserPackage`, linked by the library target below.
///
/// The web capability is the one consumer. `shellProducts` and `mcpProducts`
/// group their own products the same way.
private let webProducts: [Target.Dependency] = [
    .product(name: "SwiftSoup", package: htmlParserPackage)
]

/// The libgit2 package that the git capability reads repositories with.
///
/// git.md § "Decisions", item 10, selects it. The package compiles libgit2
/// from C source as a SwiftPM target, thus there is no binary artifact and no
/// host setup. The code calls the C API directly through the `libgit2`
/// module. There is no Swift wrapper package between them.
///
/// **The version must stay equal to the version in FoundationModelsExtras.**
/// That package declares the same URL with the same exact version for its
/// `Marketplace` target, thus SwiftPM resolves one copy. Two exact versions
/// that are not equal do not resolve. A second libgit2 package stops the
/// build, because two packages cannot declare a target with the same name
/// `libgit2` — the first spike of git.md found this with SwiftGitX. Thus a
/// change of the version here needs the same change in FoundationModelsExtras.
private let libgit2Package = "swift-libgit2"

/// The products of `libgit2Package`, linked by the library target and by the
/// `multitoolTestSupportTargetName` target below.
///
/// The git capability is the one consumer in the library. In the test
/// support code, `TemporaryGitRepository` builds the repository of a test
/// with it. `shellProducts`, `mcpProducts` and `webProducts` group their own
/// products the same way.
private let gitProducts: [Target.Dependency] = [
    .product(name: "libgit2", package: libgit2Package)
]

/// The tree-sitter package that the code plugin of the git semantic diff
/// parses source files with (ChimeHQ/SwiftTreeSitter).
///
/// git.md § "Decisions", item 6, selects tree-sitter, and § "Spike result"
/// ("Tree-sitter packages") records this package and its version. It wraps
/// the C runtime of `tree-sitter/tree-sitter`, which it resolves at 0.25.10.
/// Some grammar manifests name the runtime as `tree-sitter/swift-tree-sitter`,
/// but only their test targets use it, and SwiftPM does not resolve those.
/// Thus there is no conflict.
///
/// The version is an EXACT pin at the version that the spike linked. The
/// golden tests of the code plugin compare each parse with the Rust
/// `swissarmyhammer-sem` crate, thus a new runtime must not come in
/// without a new run of those tests.
private let treeSitterPackage = "SwiftTreeSitter"

/// The C runtime package of tree-sitter (tree-sitter/tree-sitter), which
/// `treeSitterPackage` wraps.
///
/// The code plugin imports its `TreeSitter` module for one value:
/// `TSInputEncodingUTF8`. The plugin parses the UTF-8 bytes of a file, thus
/// each byte offset of a node is a UTF-8 offset, as in the Rust crate. The
/// `parse(_:)` call of SwiftTreeSitter parses UTF-16 and gives UTF-16
/// offsets.
///
/// The URL is the URL that `treeSitterPackage` writes (with no `.git`), and
/// the version is the exact version that it resolves, thus SwiftPM resolves
/// one copy.
private let treeSitterRuntimePackage = "tree-sitter"

/// The organization of the tree-sitter grammars that the `tree-sitter`
/// project itself publishes. `treeSitterGrammarPackage(name:version:)`
/// builds the URL of each one.
private let treeSitterGrammarOrgURL = "https://github.com/tree-sitter/"

/// The Rust grammar package of the code plugin (tree-sitter/tree-sitter-rust).
///
/// Its product `TreeSitterRust` gives the language of `.rs` files. The
/// version is the version of the Rust `swissarmyhammer-sem` crate, thus the
/// two crates parse each Rust file the same way.
private let treeSitterRustPackage = "tree-sitter-rust"

/// The Go grammar package of the code plugin (tree-sitter/tree-sitter-go).
///
/// Its product `TreeSitterGo` gives the language of `.go` files. The version
/// is the version of the Rust `swissarmyhammer-sem` crate, thus the two
/// crates parse each Go file the same way.
private let treeSitterGoPackage = "tree-sitter-go"

/// The Java grammar package of the code plugin (tree-sitter/tree-sitter-java).
///
/// Its product `TreeSitterJava` gives the language of `.java` files. The
/// version is the version of the Rust `swissarmyhammer-sem` crate, thus the
/// two crates parse each Java file the same way.
private let treeSitterJavaPackage = "tree-sitter-java"

/// The C grammar package of the code plugin (tree-sitter/tree-sitter-c).
///
/// Its product `TreeSitterC` gives the language of `.c` and `.h` files. The
/// version is the version of the Rust `swissarmyhammer-sem` crate, thus the
/// two crates parse each C file the same way.
private let treeSitterCPackage = "tree-sitter-c"

/// The C++ grammar package of the code plugin (tree-sitter/tree-sitter-cpp).
///
/// Its product `TreeSitterCPP` gives the language of `.cpp`, `.cc`, `.cxx`,
/// `.hpp`, `.hh`, and `.hxx` files. The version is the version of the Rust
/// `swissarmyhammer-sem` crate, thus the two crates parse each C++ file the
/// same way.
private let treeSitterCPPPackage = "tree-sitter-cpp"

/// The Ruby grammar package of the code plugin (tree-sitter/tree-sitter-ruby).
///
/// Its product `TreeSitterRuby` gives the language of `.rb` files. The
/// version is the version of the Rust `swissarmyhammer-sem` crate, thus the
/// two crates parse each Ruby file the same way.
private let treeSitterRubyPackage = "tree-sitter-ruby"

/// The C# grammar package of the code plugin
/// (tree-sitter/tree-sitter-c-sharp).
///
/// Its product `TreeSitterCSharp` gives the language of `.cs` files. The
/// version is the version of the Rust `swissarmyhammer-sem` crate, thus the
/// two crates parse each C# file the same way.
private let treeSitterCSharpPackage = "tree-sitter-c-sharp"

/// The PHP grammar package of the code plugin (tree-sitter/tree-sitter-php).
///
/// Its product `TreeSitterPHP` gives the language of `.php` files. The pin is
/// the version that git.md § "Spike result" ("Tree-sitter packages")
/// records. The Rust `swissarmyhammer-sem` crate uses the grammar at 0.24.2,
/// thus the two crates can parse some PHP source differently. The golden
/// tests show each such difference.
private let treeSitterPHPPackage = "tree-sitter-php"

/// The Fortran grammar package of the code plugin
/// (stadelmanma/tree-sitter-fortran).
///
/// Its product `TreeSitterFortran` gives the language of `.f90`, `.f95`,
/// `.f03`, `.f08`, `.f`, and `.for` files. The version is the version of the
/// Rust `swissarmyhammer-sem` crate, thus the two crates parse each Fortran
/// file the same way.
private let treeSitterFortranPackage = "tree-sitter-fortran"

/// The Elixir grammar package of the code plugin
/// (elixir-lang/tree-sitter-elixir).
///
/// Its product `TreeSitterElixir` gives the language of `.ex` and `.exs`
/// files. The version is the version of the Rust `swissarmyhammer-sem` crate,
/// thus the two crates parse each Elixir file the same way.
private let treeSitterElixirPackage = "tree-sitter-elixir"

/// The Bash grammar package of the code plugin (tree-sitter/tree-sitter-bash).
///
/// Its product `TreeSitterBash` gives the language of `.sh` files. The
/// version is the version of the Rust `swissarmyhammer-sem` crate, thus the
/// two crates parse each Bash file the same way.
private let treeSitterBashPackage = "tree-sitter-bash"

/// The Swift grammar package of the code plugin
/// (alex-pinkus/tree-sitter-swift).
///
/// Its product `TreeSitterSwift` gives the language of `.swift` files. The
/// pin is `exact:` on the tag `0.7.4-with-generated-files`, not `from:
/// "0.7.4"`: git.md § "Spike result", note 2, found that the plain tag
/// `0.7.4` has no `src/parser.c`, and a `from:` rule selects that tag. The
/// Rust `swissarmyhammer-sem` crate uses the grammar at 0.7.2, thus the two
/// crates can parse some Swift source differently. The golden tests show
/// each such difference.
private let treeSitterSwiftPackage = "tree-sitter-swift"

/// Builds a `.package(url:exact:)` dependency for a grammar package under
/// `treeSitterGrammarOrgURL`.
///
/// The pin is exact for the reason that `treeSitterPackage` gives: the golden
/// tests compare each parse with the Rust crate.
private func treeSitterGrammarPackage(name: String, version: Version) -> Package.Dependency {
    .package(url: "\(treeSitterGrammarOrgURL)\(name).git", exact: version)
}

/// The products of `treeSitterPackage` and of the grammar packages, linked by
/// the library target below.
///
/// The code plugin of the git semantic diff is the one consumer.
/// `shellProducts`, `mcpProducts` and `webProducts` group their own products
/// the same way. Each language task of git.md adds the product of its
/// grammar here.
private let codeParserProducts: [Target.Dependency] = [
    .product(name: "SwiftTreeSitter", package: treeSitterPackage),
    .product(name: "TreeSitter", package: treeSitterRuntimePackage),
    .product(name: "TreeSitterRust", package: treeSitterRustPackage),
    .product(name: "TreeSitterGo", package: treeSitterGoPackage),
    .product(name: "TreeSitterJava", package: treeSitterJavaPackage),
    .product(name: "TreeSitterC", package: treeSitterCPackage),
    .product(name: "TreeSitterCPP", package: treeSitterCPPPackage),
    .product(name: "TreeSitterRuby", package: treeSitterRubyPackage),
    .product(name: "TreeSitterCSharp", package: treeSitterCSharpPackage),
    .product(name: "TreeSitterPHP", package: treeSitterPHPPackage),
    .product(name: "TreeSitterFortran", package: treeSitterFortranPackage),
    .product(name: "TreeSitterSwift", package: treeSitterSwiftPackage),
    .product(name: "TreeSitterElixir", package: treeSitterElixirPackage),
    .product(name: "TreeSitterBash", package: treeSitterBashPackage),
]

/// The name of the scripted MCP test server library target, and of the
/// product that exports it.
///
/// **Test support, declared as a product.** The MCP suites run against a
/// scripted `MCP.Server` (`ScriptedServer`), ported from
/// `../FoundationModelsMCP/Sources/MCPTestServer/`. It stands under
/// `Tests/Support/` because no shipped target links it: the library target
/// above never depends on it. It is a product all the same, because
/// `IntegrationTests/Package.swift` is a separate package that reaches this
/// one through `.package(path: "..")`, and a package can import the products
/// of another package only — never its targets. The unit test target below
/// links it as a target.
private let testServerTargetName = "MCPTestServer"

/// The name of the shared test-support concurrency library, and of the product
/// that exports it.
///
/// **Test support, declared as a product**, for the same reason as
/// `testServerTargetName`. It carries `ConcurrencyGate` alone — the actor that
/// holds one shared resource to one user at a time. Two callers share it, and
/// they stand in two packages: `LoopbackHTTPServer` in `testServerTargetName`
/// below, and `liveProfileTurnstile` in the nested `IntegrationTests` package.
/// Each one held a gate of its own before, and the two were the same actor with
/// two sets of names.
///
/// A target of its own, and not a file of `testServerTargetName`: that target
/// is the scripted MCP server and it links the `MCP` product, while a gate over
/// a resident model profile has nothing to do with MCP. This target links
/// nothing.
private let testConcurrencyTargetName = "TestConcurrency"

/// The name of the shared gated-scenario grading library, and of the product
/// that exports it.
///
/// **Test support, declared as a product**, for the same reason as
/// `testServerTargetName`. It carries the model-free half of the gated
/// scenario suite: the fixture tools a scenario mounts, the log those tools
/// record into, the readers over one run's record, the failure-mode
/// instrument, and the grading rules. Every one of them reads plain values, so
/// the unit test target below grades them on each commit, while the nested
/// `IntegrationTests` package drives the same rules against a real model.
///
/// The two halves used to be one file. `ScenarioRunner.swift` in the nested
/// package held the grading beside the live-model driving, so 50 tests that
/// need no model ran only when a person opted into a 14-minute suite.
///
/// A target of its own, and not a file of `testServerTargetName`: that target
/// is the scripted MCP server. This one links Router — for `TranscriptEvent`
/// and `SubmissionID`, which stay in Router, and for `ToolContext` and
/// `BackgroundRun`, which Router re-exports from FoundationModelsExtras — and
/// the metadata registry, for `Selection`. It does not link the library
/// target, because no file of it names a symbol of this package.
private let scenarioGradingTargetName = "ScenarioGrading"

/// The name of the shared test-support library that reads the `internal`
/// symbols of the library target, and of the product that exports it.
///
/// **Test support, declared as a product**, for the same reason as
/// `testServerTargetName`. The unit test target and the live web suites of the
/// nested `IntegrationTests` package use the same helpers: `RunOutput`, the
/// decode of a `runCode` output; `WebVerbCall`, the one call of each web verb;
/// `WebPageHead`, the value of each page of the goal snippet of web.md;
/// `TestPoll`, the one poll loop of the test support code, which
/// `IntegrationPoll` of the nested package uses too; and
/// `TemporaryGitRepository`, the git repository of one test, which the git
/// suites of both packages make with libgit2. A package can import the
/// products of another package only, thus a helper that both of them read
/// must stand in a product.
/// Before this target, the nested package held a copy of each one.
///
/// A target of its own, and not a file of `scenarioGradingTargetName`: that
/// target links Router and no target of this package. The helpers here name
/// the `internal` web verbs, thus this target links the library target and
/// reads it with `@testable import`. It also links `gitProducts`, because
/// `TemporaryGitRepository` calls the libgit2 C API to build its repository.
/// Each consumer reads this target with `@testable import` too, because a
/// helper whose signature names an `internal` type of the library cannot be
/// `public`. SwiftPM builds each target with testability in a debug build,
/// and each test build is a debug build.
private let multitoolTestSupportTargetName = "MultitoolTestSupport"

/// The name of the stdio executable over `testServerTargetName`, and of the
/// product that exports it.
///
/// **Test support, declared as a product** for the same reason as
/// `testServerTargetName`: a test that cannot script a server in-process
/// spawns this binary through `StdioServerProcess` and talks to it over
/// stdio. `main.swift` alone — it parses `--mode`, registers the tool set
/// that mode names, and serves until the connection closes.
private let testServerExecutableName = "mcp-test-server"

/// The `Sources/` subdirectory prefix used by every source target's `path`
/// below.
private let sourcesPath = "Sources/"

/// The `Tests/` subdirectory prefix used by every test target's `path`
/// below.
private let testsPath = "Tests/"

/// The `Tests/Support/` subdirectory prefix used by the five test-support
/// targets (`testServerTargetName`, `testConcurrencyTargetName`,
/// `scenarioGradingTargetName`, `multitoolTestSupportTargetName`,
/// `testServerExecutableName`) below. A target of
/// test support is not a test target, so it cannot stand under
/// `Tests/<Name>Tests`, and it is not shipped, so it does not stand under
/// `Sources/`.
private let testSupportPath = "\(testsPath)Support/"

/// SwiftPM manifest for FoundationModelsMultitool.
///
/// A code-mode tool over the system FoundationModels and JavaScriptCore
/// frameworks. The library takes tool hosting from FoundationModelsExtras and
/// does not depend on FoundationModelsRouter. Only the test support code and
/// the test target link Router.
///
/// **This manifest declares no integration test target, and that is the whole
/// unit/integration split.** The integration suite — the real-model scenarios
/// and the live web tests — is its own package,
/// `IntegrationTests/Package.swift`, which depends on this one by path. So
/// `swift test` here runs the unit tests and nothing else — not because a
/// person remembered a flag, and not because an environment variable was left
/// unset, but because SwiftPM cannot see a target this manifest does not
/// declare. The integration suite runs under
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
        // Test support. Consumed by `IntegrationTests/Package.swift`, which
        // can import products only — see `testServerTargetName`.
        .library(
            name: testServerTargetName,
            targets: [testServerTargetName]
        ),
        // Test support. Consumed by `IntegrationTests/Package.swift`, for the
        // same reason as the product above — see `testConcurrencyTargetName`.
        .library(
            name: testConcurrencyTargetName,
            targets: [testConcurrencyTargetName]
        ),
        // Test support. Consumed by `IntegrationTests/Package.swift`, for the
        // same reason as the two products above — see
        // `scenarioGradingTargetName`.
        .library(
            name: scenarioGradingTargetName,
            targets: [scenarioGradingTargetName]
        ),
        // Test support. Consumed by `IntegrationTests/Package.swift`, for
        // the same reason as the three products above — see
        // `multitoolTestSupportTargetName`.
        .library(
            name: multitoolTestSupportTargetName,
            targets: [multitoolTestSupportTargetName]
        ),
        // Test support. The stdio binary a test spawns through
        // `StdioServerProcess` — see `testServerExecutableName`. A product,
        // so that `swift build --product mcp-test-server` names it and the
        // nested integration package can spawn what this package built.
        .executable(
            name: testServerExecutableName,
            targets: [testServerExecutableName]
        ),
    ],
    dependencies: [
        swissArmyHammerPackage(name: routerDependencyName),
        swissArmyHammerPackage(name: metadataRegistryDependencyName),
        swissArmyHammerPackage(name: extrasDependencyName),
        // The package of `shellProducts`. It stands under an organization of
        // its own, so the helper above does not fit it.
        //
        // The version is an EXACT pin, and it is the pin
        // `../FoundationModelsShelltool/Package.swift` states today. The shell
        // capability moves from that package into this one, so the two must
        // resolve the same version: a pre-release carries no compatible-range
        // promise, and a floor would let one package move alone.
        .package(url: "https://github.com/swiftlang/\(subprocessPackage).git", exact: "1.0.0-beta.1"),
        // The package of `mcpProducts` — see its documentation above for the
        // fork and the defect behind it.
        //
        // The `main` branch of the fork, and not a version tag. The correction
        // of card `^qba8j6x` lands on that branch, and this package follows it
        // there. A tag cannot do that. Upstream releases this package, and a
        // tag of the fork would be one more release to cut for each change to
        // the correction.
        //
        // The cost is that a branch carries no compatible-range promise, thus
        // `swift package update` moves this dependency to whatever the branch
        // holds that day. `Package.resolved` is what keeps the build the same
        // until then, because it pins one revision of the branch. To stop the
        // movement, change `branch: mainBranch` to `revision:` with the
        // revision that file names.
        .package(url: "https://github.com/swissarmyhammer/\(mcpPackage).git", branch: mainBranch),
        // The package of `webProducts` — see `htmlParserPackage`. It stands
        // under an organization of its own, so the helper above does not fit
        // it.
        .package(url: "https://github.com/scinfu/\(htmlParserPackage).git", from: "2.13.9"),
        // The package of `gitProducts` — see `libgit2Package`. It stands under
        // an organization of its own, so the helper above does not fit it.
        //
        // The version is an EXACT pin, and it is the pin
        // FoundationModelsExtras states today. The two packages must resolve
        // one copy of libgit2, thus the two pins must stay equal.
        .package(url: "https://github.com/danielctull-forks/\(libgit2Package).git", exact: "1.9.7"),
        // The packages of `codeParserProducts` — see `treeSitterPackage` and
        // each grammar package. SwiftTreeSitter and the Fortran, Swift, and
        // Elixir grammars stand under organizations of their own, so the
        // grammar helper above does not fit them.
        .package(url: "https://github.com/ChimeHQ/\(treeSitterPackage).git", exact: "0.25.0"),
        .package(url: "\(treeSitterGrammarOrgURL)\(treeSitterRuntimePackage)", exact: "0.25.10"),
        treeSitterGrammarPackage(name: treeSitterRustPackage, version: "0.24.2"),
        treeSitterGrammarPackage(name: treeSitterGoPackage, version: "0.25.0"),
        treeSitterGrammarPackage(name: treeSitterJavaPackage, version: "0.23.5"),
        treeSitterGrammarPackage(name: treeSitterCPackage, version: "0.24.2"),
        treeSitterGrammarPackage(name: treeSitterCPPPackage, version: "0.23.4"),
        treeSitterGrammarPackage(name: treeSitterRubyPackage, version: "0.23.1"),
        treeSitterGrammarPackage(name: treeSitterCSharpPackage, version: "0.23.5"),
        treeSitterGrammarPackage(name: treeSitterPHPPackage, version: "0.25.0"),
        .package(url: "https://github.com/stadelmanma/\(treeSitterFortranPackage).git", exact: "0.6.0"),
        .package(
            url: "https://github.com/alex-pinkus/\(treeSitterSwiftPackage).git",
            exact: "0.7.4-with-generated-files"),
        .package(url: "https://github.com/elixir-lang/\(treeSitterElixirPackage).git", exact: "0.3.5"),
        treeSitterGrammarPackage(name: treeSitterBashPackage, version: "0.25.1"),
        // The package of `ulidProducts` — see `ulidPackage`. It stands under
        // an organization of its own, so the helper above does not fit it.
        .package(url: "https://github.com/yaslab/\(ulidPackage).git", from: "1.3.1"),
        // The packages of `telemetryProducts` — see `loggingPackage`. They
        // stand under an organization of their own, so the helper above does
        // not fit them.
        .package(url: "https://github.com/apple/\(loggingPackage).git", from: "1.15.1"),
        .package(url: "https://github.com/apple/\(metricsPackage).git", from: "2.11.0"),
    ],
    targets: [
        // Links `shellProducts` for the shell capability this library takes
        // over from `../FoundationModelsShelltool`, and `mcpProducts` for the
        // MCP capability it takes over from `../FoundationModelsMCP`, and
        // `webProducts` for the HTML parser of the web capability, and
        // `ulidProducts` for the identifier of each elicitation, and
        // `telemetryProducts` for the logging and metrics APIs, and
        // `gitProducts` for the libgit2 C API of the git capability, and
        // `codeParserProducts` for the tree-sitter parse of its semantic diff.
        //
        // It does NOT link Router. FoundationModelsExtras owns the tool
        // hosting — `ToolContext`, `BackgroundTool`, `ToolMount`,
        // `SubmissionBoundaryTool`, `LostRunError` and `RunPlane` — and the
        // library takes each one from there. No shipped target links Router.
        // `PackageManifestTests` reads this declaration and fails when Router
        // comes back.
        .target(
            name: packageName,
            dependencies: [
                .product(name: metadataRegistryDependencyName, package: metadataRegistryDependencyName),
                .product(name: extrasDependencyName, package: extrasDependencyName),
            ] + shellProducts + mcpProducts + webProducts + ulidProducts + telemetryProducts + gitProducts
                + codeParserProducts,
            path: "\(sourcesPath)\(packageName)"
        ),
        // The scripted MCP test server — see `testServerTargetName`. Links
        // `mcpProducts` for the sdk's `Server`, which is what it wraps.
        // `FlakyConnectTransport` names `Logging.Logger` because the
        // `Transport` protocol requires the property.
        //
        // It links `testConcurrencyTargetName` for the one gate
        // `LoopbackHTTPServer` holds the loopbacks of the process with.
        //
        // It links the library target above for one file:
        // `LargeCatalogSurface.swift` mounts the large catalog through
        // `MultiTool.Builder`, so that the two suites which measure a catalog
        // above the selection budget — one in each package — read one mount
        // rather than a copy each. A package can import the products of
        // another package only, so a mount both of them read must stand in a
        // product, and this is the product both of them already link. The edge
        // makes no cycle: the library target names no target of this package.
        .target(
            name: testServerTargetName,
            dependencies: [
                .target(name: packageName),
                .target(name: testConcurrencyTargetName),
            ] + mcpProducts,
            path: "\(testSupportPath)\(testServerTargetName)"
        ),
        // The shared gate of the test support code — see
        // `testConcurrencyTargetName`. It links nothing: the actor is written
        // over the standard library alone.
        .target(
            name: testConcurrencyTargetName,
            path: "\(testSupportPath)\(testConcurrencyTargetName)"
        ),
        // The model-free half of the gated scenario suite — see
        // `scenarioGradingTargetName`. It links Router and the metadata
        // registry, and no target of this package.
        .target(
            name: scenarioGradingTargetName,
            dependencies: [
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: metadataRegistryDependencyName, package: metadataRegistryDependencyName),
            ],
            path: "\(testSupportPath)\(scenarioGradingTargetName)"
        ),
        // The helpers that the unit tests and the live web suites share — see
        // `multitoolTestSupportTargetName`. It links the library target, and
        // `gitProducts` for the libgit2 calls of `TemporaryGitRepository`.
        .target(
            name: multitoolTestSupportTargetName,
            dependencies: [
                .target(name: packageName)
            ] + gitProducts,
            path: "\(testSupportPath)\(multitoolTestSupportTargetName)"
        ),
        // The stdio entry point over the test server — see
        // `testServerExecutableName`. `main.swift` and nothing else.
        .executableTarget(
            name: testServerExecutableName,
            dependencies: [
                .target(name: testServerTargetName)
            ] + mcpProducts,
            path: "\(testSupportPath)\(testServerExecutableName)"
        ),
        // `shellProducts` and `mcpProducts` again: `DependencyReachTests`
        // imports `Subprocess` and `MCP` directly, and this target declares
        // each product it imports, as it does for the two products above.
        // `telemetryTestProducts` gives the log read-back of the suites — see
        // its documentation.
        // `testServerTargetName` is the scripted server the MCP suites run
        // against; the executable over it is not a dependency, because a
        // test target cannot depend on an executable, and `swift test`
        // builds every target of the package regardless.
        .testTarget(
            name: "\(packageName)Tests",
            dependencies: [
                .target(name: packageName),
                .target(name: testServerTargetName),
                .target(name: testConcurrencyTargetName),
                .target(name: scenarioGradingTargetName),
                .target(name: multitoolTestSupportTargetName),
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: metadataRegistryDependencyName, package: metadataRegistryDependencyName),
                .product(name: extrasDependencyName, package: extrasDependencyName),
            ] + shellProducts + mcpProducts + telemetryTestProducts,
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
                // Hand-written HTML pages and the markdown and text that
                // `HTMLMarkdown` must make from each one. `HTMLMarkdownTests`
                // loads these through `Bundle.module`, as `HashlineTests`
                // loads its goldens.
                .copy("WebGoldens"),
                // Golden vectors that pin the hash of the git semantic diff
                // against the Rust `swissarmyhammer-sem` crate
                // (`utils/hash.rs`). `SemanticHashTests` loads these through
                // `Bundle.module`, as `HashlineTests` loads its goldens.
                .copy("GitGoldens"),
                // Golden diffs that pin the code plugin of the git semantic
                // diff against the Rust `swissarmyhammer-sem` crate: for each
                // language and each case, a before file, an after file, and
                // the expected JSON that the Rust crate wrote.
                // `CodeParserPluginGoldenTests` loads these through
                // `Bundle.module`, as `HashlineTests` loads its goldens.
                .copy("GitSemanticGoldens"),
            ]
        ),
    ]
)
