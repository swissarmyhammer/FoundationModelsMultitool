import Foundation
import FoundationModels
import FoundationModelsMultitool
import FoundationModelsRouter
import HuggingFace
import MLXFoundationModels
import MLXHuggingFace
import MLXLMCommon
// Load-bearing although this file names no `MLXVLM` symbol: keep it.
// `loadModelContainer` below selects a factory through `MLXLMCommon`'s
// `ModelFactoryRegistry`, which finds its built-in trampolines with
// `NSClassFromString`, so a factory whose module the linker dropped is
// silently absent from that list. Whether the model `generationModel`
// names needs it is not a thing to check and drop: Muse Glimmer
// (`muse_glimmer`) was registered in `VLMModelFactory` alone, and dropping
// this import cost a full download before `.unsupportedModelType` was
// thrown. Keeping it makes both factories reachable whatever the pin is.
import MLXVLM
import Tokenizers

/// Prefix for all user-facing CLI error messages.
///
/// This prefix is reused by `CLIArgumentError.description`,
/// `CLIRouterUnavailableError.description`, and `CLIRunner.run(...)`'s
/// catch-all branch, so error output is consistently attributable to
/// `multitool-cli`.
private let cliErrorPrefix = "multitool-cli:"

// MARK: - Argument parsing

/// The command-line flags `CLIRunner.parse(_:)` recognizes.
struct CLIArguments: Equatable {
    /// Whether to run in direct mode: only `multiTool`/`runCode` is registered with the session, no discovery.
    ///
    /// When set, `searchToolsTool` is not registered with the session —
    /// plan.md "Direct mode (skip discovery)".
    var direct = false

    /// Whether to print usage text and exit without touching the Router.
    ///
    /// Set by the `--help`/`-h` flags.
    var help = false
}

/// An error thrown by `CLIRunner.parse(_:)` for an unrecognized argument.
struct CLIArgumentError: Error, Equatable, CustomStringConvertible {
    /// The unrecognized argument, verbatim.
    let flag: String

    /// A human-readable description of the error.
    ///
    /// Implementation of the `CustomStringConvertible` protocol requirement.
    var description: String {
        "\(cliErrorPrefix) unknown argument \"\(flag)\". Run with \(CLIRunner.helpFlag.names[0]) for usage."
    }
}

// MARK: - Flags

/// One CLI flag: its recognized spelling(s), `OPTIONS:` description, and the effect it has on `CLIArguments` when parsed.
///
/// The single source of truth for a flag's name(s) — `CLIRunner.parse(_:)`'s
/// dispatch, `CLIRunner.usageText`'s `OPTIONS:` listing, and
/// `CLIArgumentError.description`'s "Run with --help" hint are all generated
/// from (or reference) `CLIRunner.flags`/`CLIRunner.helpFlag`, instead of
/// each site separately repeating a flag's literal spelling.
struct Flag: Sendable {
    /// The flag's recognized spellings, e.g. `["--help", "-h"]`.
    ///
    /// The first name is the canonical spelling shown in `USAGE:` and
    /// referenced by error messages.
    let names: [String]

    /// The `OPTIONS:` description lines shown next to this flag's names, pre-wrapped to `usageText`'s line width.
    ///
    /// Indentation is excluded; `usageText` computes it separately from
    /// every flag's name-column width.
    let descriptionLines: [String]

    /// The effect to apply to `arguments` when `parse(_:)` matches this flag.
    let apply: @Sendable (_ arguments: inout CLIArguments) -> Void
}

// MARK: - The Router-unavailable degrade path

/// Error thrown when the Router's live path cannot be resolved.
///
/// Thrown by `CLIRunner.run(...)`'s internals when the demo can't proceed
/// past model resolution — plan.md M9: "degrade gracefully (clear message +
/// nonzero exit) when the Router live path is unavailable."
struct CLIRouterUnavailableError: Error, CustomStringConvertible {
    /// The error that `resolve` threw.
    let underlying: Error

    /// A human-readable message describing the Router unavailability.
    ///
    /// Explanation of what went wrong, plus why (the Router's live
    /// inference path not being wired up in this environment is the
    /// expected cause pre-Router-M7, but any resolution failure —
    /// including an unsatisfiable profile or a download error — surfaces
    /// the same way).
    var description: String {
        """
        \(cliErrorPrefix) could not resolve a model via the Router: \(underlying)
        The Router's live inference path is not available in this environment.
        """
    }
}

/// A runnable demonstration of the FoundationModelsMultitool pipeline.
///
/// The canonical Router + `LanguageModelSession` + `MultiTool` example:
/// resolving a model profile via `Router`, wrapping the resolved `.standard`
/// generation slot as a real `FoundationModels.LanguageModel`
/// (`MLXLanguageModel`), and mounting whatever
/// `MultiTool.Registry.makeSessionTools(librarian:)` vends — `searchTools`,
/// `runCode`, `wait`, or `runCode` and `wait` under `--direct` — directly on a native
/// `FoundationModels.LanguageModelSession`. Apple's own tool-calling loop decides when to
/// call `searchTools` vs `runCode` — this file drives no turn-parsing loop of
/// its own, unlike the retired `MultiToolAgent`-based demo this replaces.
/// Factored out of `main.swift` as a plain, testable entry point:
///
/// - Argument parsing and the Router-unavailable degrade path are
///   unit-tested here with **no model at all**
///   (`Tests/FoundationModelsMultitoolTests/CLIArgumentTests.swift`).
/// - The full live run — resolving a real profile, constructing the native
///   session, and printing the model's answer — is exercised end to end by
///   the gated `CLISmokeTests`
///   (`Tests/FoundationModelsMultitoolIntegrationTests/CLISmokeTests.swift`).
enum CLIRunner {
    /// Process exit codes this runner returns.
    ///
    /// The BSD `sysexits.h` convention for the two documented failure
    /// modes; `0` for success.
    enum ExitCode {
        /// Exit code indicating successful completion (or that `--help` was requested).
        static let success: Int32 = 0
        /// Bad arguments; the same value as `sysexits.h`'s `EX_USAGE` (64).
        static let usageError: Int32 = 64
        /// Exit code when the Router's live path cannot be resolved.
        ///
        /// The same value as `sysexits.h`'s `EX_UNAVAILABLE` (69).
        static let unavailable: Int32 = 69
    }

    /// The `--direct` flag, for running in direct mode (only `multiTool`/`runCode` registered with the session, no `searchToolsTool`).
    static let directFlag = Flag(
        names: ["--direct"],
        descriptionLines: [
            "Run in direct mode: only the runCode tool is registered with the",
            "session (no searchTools tool); the snippet discovers tools via",
            "help()/docs() instead.",
        ],
        apply: { $0.direct = true }
    )

    /// The `--help`/`-h` flag, for printing usage text and exiting without touching the Router.
    static let helpFlag = Flag(
        names: ["--help", "-h"],
        descriptionLines: ["Print this usage text and exit."],
        apply: { $0.help = true }
    )

    /// The flags `parse(_:)` recognizes, in `USAGE:`/`OPTIONS:` display order.
    ///
    /// The single source of truth `usageText` is generated from, and
    /// `parse(_:)` dispatches against — see `Flag`'s documentation.
    static let flags: [Flag] = [directFlag, helpFlag]

    /// `--help`'s usage text, generated from `flags`.
    static var usageText: String {
        let leadingIndent = "  "
        let columnGap = "   "
        let nameColumns = flags.map { $0.names.joined(separator: ", ") }
        let columnWidth = nameColumns.map(\.count).max() ?? 0
        let continuationIndent = String(repeating: " ", count: leadingIndent.count + columnWidth + columnGap.count)
        let optionsLines = zip(flags, nameColumns).flatMap { flag, nameColumn -> [String] in
            let paddedName = nameColumn.padding(toLength: columnWidth, withPad: " ", startingAt: 0)
            return flag.descriptionLines.enumerated().map { index, line in
                index == 0 ? "\(leadingIndent)\(paddedName)\(columnGap)\(line)" : "\(continuationIndent)\(line)"
            }
        }
        let usageSummary = flags.map { "[\($0.names[0])]" }.joined(separator: " ")
        return """
            multitool-cli — a runnable demonstration of the FoundationModelsMultitool pipeline.

            USAGE:
              multitool-cli \(usageSummary)

            OPTIONS:
            \(optionsLines.joined(separator: "\n"))

            Resolves a small demo model profile via FoundationModelsRouter, wires up a
            couple of fixture tools (getTrip, getWeather), and asks one question that
            exercises the search-then-code loop (searchTools, then a composing runCode).
            """
    }

    /// The generation model both slots resolve — **the single place a
    /// generation model is named in this package.**
    ///
    /// `demoProfile` below puts it in `standard` and in `flash`, and the gated
    /// integration suite's `multitoolTinyProfile` *is* `demoProfile`
    /// (`Tests/FoundationModelsMultitoolIntegrationTests/Support/IntegrationGate.swift`),
    /// so changing this one line moves the CLI and every gated scenario
    /// together. That matters more than it sounds: the suite exists to measure
    /// what a host actually runs, and while the two lists were written out
    /// separately they were free to disagree — the CLI and the suite each named
    /// their own models, and nothing failed when they drifted.
    ///
    /// `IntegrationGate.swift` carries the measurement history behind every
    /// model that has held this slot, because that history is a record of gated
    /// runs. This is where the choice lives; that is where the evidence lives.
    ///
    /// No `@revision`: this tracks the repository's default revision, so it is
    /// a model *choice* rather than a version lock.
    static let generationModel: ModelRef = "mlx-community/Qwen3.8-27B-MTP-mxfp4"

    /// The embedding model, unchanged across every generation-model swap and
    /// shared with Router's own gated suite so the weights are already cached.
    static let embeddingModel: ModelRef = "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"

    /// The profile used for the demo run, and by the gated integration suite.
    ///
    /// Deliberate use of tool-calling-capable models. The gated suite resolves
    /// this exact value rather than a parallel definition of its own — see
    /// `generationModel` above for why.
    static let demoProfile = ProfileDefinition(
        name: "multitool-cli-demo",
        description: "Tool-calling-capable models for the multitool-cli sample.",
        // **This is the one place any model is named.** The gated suite does
        // not keep its own pin: `multitoolTinyProfile` is this value
        // (`IntegrationGate.swift`), so the suite measures the models the CLI
        // ships and a swap here moves both. Two lists drifted apart once and
        // the suite spent its runs grading a configuration no host had.
        //
        // One model in both slots: it drives the main session, and the
        // selection tier `searchTools` runs on `flash` is the same model.
        //
        // One reference means one resident container, and that is a known
        // deadlock today — not an unexplained one. A container carries a
        // single `generationGate`, `beginTurn()` takes its one permit and
        // holds it for the whole turn including tool rounds, so a
        // `searchTools` call made from inside a turn waits for a permit only
        // that turn's end can free. Measured at `permits=0 waiters=1` for the
        // life of the run. It is Router's defect, tracked on their `^1zt7vyg`,
        // and this package's regression test for it is
        // `NestedGenerationProbeTests`.
        //
        // The earlier split onto two models was a workaround for this, written
        // when the cause was still unknown and wrongly blamed on a container
        // lock in `mlx-swift-lm` — an explanation that repository's own test
        // (`ca8e22f`) refuted by generating from a tool body on one container
        // safely.
        standard: [generationModel],
        flash: [generationModel],
        embedding: [embeddingModel],
        // `nil`, not a number: resolve the model's own context window rather
        // than imposing one, exactly as the gated suite's
        // `multitoolTinyProfile` does. A pinned figure is always wrong on the
        // wrong side — too small, and a generation turn loses the very tool
        // definitions and discovery output it is supposed to act on.
        // `ProfileDefinition.defaultContext` remains the fallback if the
        // lookup fails, so this cannot resolve to nothing.
        context: nil
    )

    /// The demo prompt that exercises the agent.
    ///
    /// Triggering both searchTools and runCode to compose an answer — plan.md
    /// M9: "one prompt that triggers searchTools then a composing runCode,"
    /// mirroring the sample's own worked `getTrip` -> `getWeather` -> warmest
    /// example.
    static let demoPrompt = "Of the cities on my trip, which is warmest right now?"

    /// A function type for profile resolution, converting a profile definition into a language model profile.
    ///
    /// Conversion of an authored `ProfileDefinition` into a resolved,
    /// resident `LanguageModelProfile` on a given `Router` — injectable so
    /// `CLIArgumentTests` can exercise the Router-unavailable degrade path
    /// with a scripted failure, with no real model download/load involved.
    ///
    /// - Parameters:
    ///   - router: the router to resolve against.
    ///   - definition: the profile to resolve.
    ///   - progress: the UI/console-bindable progress to report through.
    /// - Returns: the resolved language model profile.
    /// - Throws: any error the resolution process encounters.
    typealias ProfileResolver = @Sendable (
        _ router: Router,
        _ definition: ProfileDefinition,
        _ progress: ResolutionProgress
    ) async throws -> LanguageModelProfile

    /// The default profile resolution implementation.
    ///
    /// `router.resolve(profile:reporting:)`, unchanged — see `ProfileResolver`.
    static let defaultResolve: ProfileResolver = { router, definition, progress in
        try await router.resolve(profile: definition, reporting: progress)
    }

    /// Parses command-line arguments into `CLIArguments`.
    ///
    /// Excludes the executable name; recognizes every flag in `flags`.
    ///
    /// - Parameter arguments: the raw arguments, e.g.
    ///   `CommandLine.arguments.dropFirst()`.
    /// - Returns: the parsed flags.
    /// - Throws: `CLIArgumentError` on the first argument that isn't a
    ///   recognized flag.
    static func parse(_ arguments: [String]) throws -> CLIArguments {
        var result = CLIArguments()
        for argument in arguments {
            guard let flag = flags.first(where: { $0.names.contains(argument) }) else {
                throw CLIArgumentError(flag: argument)
            }
            flag.apply(&result)
        }
        return result
    }

    /// Runs the complete demo pipeline end-to-end.
    ///
    /// Parses `arguments`, and — unless `--help` was given or parsing
    /// failed — resolves `demoProfile`, constructs a native
    /// `LanguageModelSession` over the tools the registry vends (`searchTools`,
    /// `runCode`, `wait` — or `runCode` and `wait` alone under `--direct`),
    /// calls `session.respond(to:)` once against `demoPrompt`, and writes the
    /// answer to `output`.
    ///
    /// **This is a bare `LanguageModelSession`, not the `RoutedSession` the
    /// host contract names** (`MultiTool.Registry.makeSessionTools`). On a bare
    /// session the mounted tools cannot detach, so a slow `runCode` blocks
    /// rather than answering with a pending envelope and `wait` has nothing to
    /// join. The demo reads correctly because its fixtures are fast. Recorded
    /// as a divergence on task `^tkrdwb8`.
    ///
    /// - Parameters:
    ///   - arguments: the raw arguments (excluding the executable name).
    ///   - resolve: the profile-resolution step. Defaults to
    ///     `defaultResolve`; a test injects a scripted failure to exercise
    ///     the Router-unavailable path with no model.
    ///   - output: where every line of output (usage, errors, progress, the
    ///     final answer) is written. Defaults to `print(_:)`; a test
    ///     injects a collector to assert on the emitted lines.
    /// - Returns: the process exit code — `ExitCode.success` on success or
    ///   `--help`, `ExitCode.usageError` for an argument error, or
    ///   `ExitCode.unavailable` if the Router path couldn't be resolved (or
    ///   the demo otherwise failed after resolution).
    static func run(
        arguments: [String],
        resolve: @escaping ProfileResolver = defaultResolve,
        output: @escaping @Sendable (String) -> Void = { print($0) }
    ) async -> Int32 {
        let parsed: CLIArguments
        do {
            parsed = try parse(arguments)
        } catch {
            output(String(describing: error))
            output(usageText)
            return ExitCode.usageError
        }

        if parsed.help {
            output(usageText)
            return ExitCode.success
        }

        do {
            try await runDemo(direct: parsed.direct, resolve: resolve, output: output)
            return ExitCode.success
        } catch let error as CLIRouterUnavailableError {
            output(error.description)
            return ExitCode.unavailable
        } catch {
            output("\(cliErrorPrefix) \(error)")
            return ExitCode.unavailable
        }
    }

    // MARK: - The demo run

    /// Resolves a profile, builds the tool-equipped session, and prints the
    /// model's answer.
    ///
    /// Factored out of `run(...)` as its resolve-through-print body, so
    /// `run(...)` only has to decide which exit code an error maps to.
    ///
    /// - Parameters:
    ///   - direct: whether to run in direct mode — only `multiTool` is
    ///     registered with the session, `searchToolsTool` is omitted.
    ///   - resolve: the profile-resolution step.
    ///   - output: where progress/answer lines are written.
    /// - Throws: `CLIRouterUnavailableError` if `resolve` throws; otherwise
    ///   whatever building the tools, `searchToolsTool`'s own initializer, or
    ///   `session.respond(to:)` throws.
    private static func runDemo(
        direct: Bool,
        resolve: ProfileResolver,
        output: @escaping @Sendable (String) -> Void
    ) async throws {
        let recordingsDir = Self.makeTempRecordingsDir()
        let router = Router(
            recordingsDir: recordingsDir,
            recordingLevel: .full,
            loader: LiveModelLoader(downloader: #hubDownloader(), tokenizerLoader: #huggingFaceTokenizerLoader())
        )
        let progress = await MainActor.run { ResolutionProgress() }
        let progressTask = Self.trackProgress(progress, output: output)
        defer { progressTask.cancel() }

        let profile: LanguageModelProfile
        do {
            profile = try await resolve(router, demoProfile, progress)
        } catch {
            throw CLIRouterUnavailableError(underlying: error)
        }

        // `profile.release()` is async, so it can't run in a synchronous
        // `defer`; explicitly release on every exit path instead — success
        // or thrown error alike — mirroring
        // `Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift`'s
        // own `LiveRouterFixture.tearDown()` calls, rather than an
        // unstructured, un-awaited cleanup `Task` that `main.swift`'s
        // immediate `exit(_:)` after `run(...)` returns would likely never
        // let finish.
        do {
            var registry = try MultiTool.Builder()
                .addTool(DemoTripTool())
                .addTool(DemoWeatherTool())
                .buildRegistry()
            if direct {
                registry = registry.directMode()
            }

            // The registry vends its own mounted tools, in the order the
            // model reads them — `searchTools`, then `runCode`, then `wait`,
            // with discovery dropped once `directMode()` above has taken it
            // away. The `searchTools` half's internal selection tier is backed
            // by a Router-resolved `profile.flash` session — the
            // registry-backed `SelectionTier`'s "librarian on flash" split.
            //
            // `flash` and `standard` name the same model here (`demoProfile`),
            // so that tier and the main session below share one resident
            // container. See `demoProfile` for what that costs.
            //
            // Explicitly typed for the same reason the local was before:
            // disambiguation against `MLXLMCommon.Tool`, also in scope via
            // `MLXFoundationModels`/`MLXLMCommon`.
            let tools: [any FoundationModels.Tool] = try registry.makeSessionTools(librarian: profile.flash)

            let mlxModel = Self.makeMLXLanguageModel(for: profile.standard)
            // No instructions. Mounting the vended tools is the whole host
            // contract — their descriptions carry the entire behavioral
            // contract, and a session instruction a real host may never pass
            // must not be load-bearing (see
            // `Registry.makeSessionTools(librarian:)`).
            let session = LanguageModelSession(
                model: mlxModel,
                tools: tools
            )

            // Explicitly typed: `FoundationModelsRanker` (pulled in
            // transitively by the metadata registry) adds a shadowing
            // `LanguageModelSession.respond(to:) -> String` extension for its
            // `AgentSession` conformance; the annotation pins this call to
            // the native FoundationModels API.
            let response: LanguageModelSession.Response<String> = try await session.respond(to: demoPrompt)

            output("")
            output("Answer: \(response.content)")
            await profile.release()
        } catch {
            await profile.release()
            throw error
        }
    }

    /// Wraps a resolved Router generation slot as a real `FoundationModels.LanguageModel`, so a native `LanguageModelSession` can be built directly over it.
    ///
    /// Builds a fresh, lightweight `MLXLanguageModel` value over the same
    /// model id `routedLLM` already resolved and loaded. `MLXLanguageModel`
    /// loads and caches its `ModelContainer` in a process-global cache keyed
    /// by model id (see its own documentation) — a second value constructed
    /// over the same id reuses the already-resident weights the Router
    /// loaded rather than re-resolving or re-downloading anything. This
    /// declares `.toolCalling` alongside `.guidedGeneration` — which
    /// Router's own internal model does not, since Router's generation
    /// surface never exposes native tool-calling — so a session built over
    /// it can register real `Tool` conformers and drive Apple's own native
    /// tool-calling loop.
    ///
    /// Not `private`: the gated integration test target's own scenario suite
    /// (`Tests/FoundationModelsMultitoolIntegrationTests/Support/
    /// ScenarioRunner.swift`) reuses this exact production wiring via
    /// `@testable import` to build its own `LanguageModelSession`s, rather
    /// than reimplementing it — extracted as its own factory so the gated
    /// integration test target can drive this exact production wiring (the
    /// same rationale the retired `MultiToolAgent`'s searcher factory
    /// followed).
    ///
    /// - Parameter routedLLM: the resolved Router generation slot to wrap —
    ///   typically `profile.standard`.
    /// - Returns: an `MLXLanguageModel` over the same resident model.
    static func makeMLXLanguageModel(for routedLLM: RoutedLLM) -> MLXLanguageModel {
        let modelConfiguration = ModelConfiguration(
            id: routedLLM.chosen.repo,
            revision: routedLLM.chosen.revision ?? "main"
        )
        return MLXLanguageModel(
            configuration: modelConfiguration,
            // `.reasoning` is not optional for a model that always reasons,
            // which every model pinned here so far has been. A caller that
            // does not declare the capability is asking `MLXLanguageModel` to
            // suppress thinking —
            // which it cannot do, so the call throws
            // `LanguageModelError.unsupportedCapability` ("This model always
            // reasons; .reasoning must be declared at MLXLanguageModel init to
            // receive its output") *after* the whole model has loaded. The
            // gated CLI smoke test caught exactly that. Declaring it also puts
            // the tool path into its think-then-call phase rather than forcing
            // thinking off, which is the behaviour an agentic model is trained
            // for. Router's own `LiveModelLoader` declares the same three.
            capabilities: [.guidedGeneration, .toolCalling, .reasoning],
            weightsLocation: Self.weightsLocation,
            load: { configuration, progressHandler in
                try await loadModelContainer(
                    from: #hubDownloader(),
                    using: #huggingFaceTokenizerLoader(),
                    configuration: configuration,
                    progressHandler: progressHandler
                )
            }
        )
    }

    /// Resolves a model id to its on-disk weights directory.
    ///
    /// For `MLXLanguageModel`'s availability checks (`modelExistsOnDisk()`,
    /// `freeDiskSpaceBytes`) — never consulted by the load path itself,
    /// which always goes through `ModelCache`/`load` (see
    /// `makeMLXLanguageModel(for:)`). Following `MLXLanguageModel`'s own
    /// doc-comment example, this resolves
    /// against the same `HubCache` the injected `#hubDownloader()` downloads
    /// into, so the availability checks see the weights the Router already
    /// downloaded — the same cache directory `LiveModelLoader`'s default
    /// `weightsLocation` stub deliberately does *not* resolve into (it
    /// exists purely so `LoadedLLMContainer.availability` isn't Router's
    /// concern), but does matter here since this instance's `.toolCalling`
    /// capability makes it plausible a caller could check `.availability` on
    /// it directly.
    ///
    /// - Parameter id: the model id (`ModelConfiguration.name`) to resolve.
    /// - Returns: the resolved snapshot directory if the model is cached
    ///   under a known revision; otherwise the repository's cache directory
    ///   (present once any download has started) or, failing that, the
    ///   cache root itself.
    private static func weightsLocation(for id: String) -> URL {
        let cache = HubCache.default
        guard let repo = Repo.ID(rawValue: id) else { return cache.cacheDirectory }
        if let commit = cache.resolveRevision(repo: repo, kind: .model, ref: "main"),
            let snapshot = try? cache.snapshotPath(repo: repo, kind: .model, commitHash: commit)
        {
            return snapshot
        }
        return cache.repoDirectory(repo: repo, kind: .model)
    }

    // MARK: - Console progress

    /// How long ``trackProgress(_:output:)`` waits between reads of
    /// `progress.phase`, in nanoseconds.
    ///
    /// A tenth of a second, the granularity at which a phase change reaches
    /// the console.
    private static let progressPollIntervalNanoseconds: UInt64 = 100_000_000

    /// Monitors and prints resolution progress.
    ///
    /// Starts a background task that prints one line to `output` each time
    /// `progress.phase` changes, until cancelled — plan.md M9's "console
    /// progress."
    ///
    /// - Parameters:
    ///   - progress: the progress to observe.
    ///   - output: where to print progress lines.
    /// - Returns: the polling task; cancel it once resolution finishes
    ///   (success or failure) so it doesn't outlive the call.
    private static func trackProgress(
        _ progress: ResolutionProgress,
        output: @escaping @Sendable (String) -> Void
    ) -> Task<Void, Never> {
        Task {
            var lastPhase: ResolutionProgress.Phase?
            while !Task.isCancelled {
                let phase = await MainActor.run { progress.phase }
                if phase != lastPhase {
                    lastPhase = phase
                    output("Resolving model profile: \(phase)")
                }
                try? await Task.sleep(nanoseconds: progressPollIntervalNanoseconds)
            }
        }
    }

    // MARK: - Recordings directory

    /// Creates a temporary directory for Router transcript recordings.
    ///
    /// Returns the URL of a fresh, uniquely-named directory the `Router`
    /// records `searchToolsTool`'s own selection-tier sessions under (the main
    /// `LanguageModelSession` `runDemo` builds directly over `mlxModel` is
    /// never Router-vended, so it is never recorded here).
    ///
    /// - Returns: the created directory's URL.
    private static func makeTempRecordingsDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("multitool-cli-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
