import Foundation
import FoundationModels
import FoundationModelsMultitool
import FoundationModelsRouter
import HuggingFace
import MLXFoundationModels
import MLXHuggingFace
import MLXLMCommon
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
    /// When set, `findAPIsTool` is not registered with the session —
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
/// (`MLXLanguageModel`), and registering `multiTool` (and, unless `--direct`,
/// `findAPIsTool`) directly on a native `FoundationModels
/// .LanguageModelSession`. Apple's own tool-calling loop decides when to
/// call `findAPIs` vs `runCode` — this file drives no turn-parsing loop of
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

    /// The `--direct` flag, for running in direct mode (only `multiTool`/`runCode` registered with the session, no `findAPIsTool`).
    static let directFlag = Flag(
        names: ["--direct"],
        descriptionLines: [
            "Run in direct mode: only the runCode tool is registered with the",
            "session (no findAPIs tool); the snippet discovers tools via",
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
            couple of fixture tools (tripCities, weather), and asks one question that
            exercises the search-then-code loop (findAPIs, then a composing runCode).
            """
    }

    /// The profile used for the demo run.
    ///
    /// Deliberate use of tiny, tool-calling-capable models, matching the
    /// gated integration suite's own `multitoolTinyProfile`
    /// (`Tests/FoundationModelsMultitoolIntegrationTests/Support/IntegrationGate.swift`)
    /// so a machine that already ran that suite shares the cached weights.
    static let demoProfile = ProfileDefinition(
        name: "multitool-cli-demo",
        description: "Small tool-calling-capable models for the multitool-cli sample.",
        // Split pins, mirroring the gated suite's `multitoolTinyProfile`
        // (see `IntegrationGate.swift`'s pin history): the natively
        // tool-calling-trained Qwen3-4B drives the main session (the
        // 1.5B pin never grounded its runCode snippets in the discovered
        // `tools.*` surface), while the 1.5B stays on `flash` for the
        // selection tier, where it is empirically the more accurate and
        // decisive grammar-constrained selector of the two.
        standard: ["mlx-community/Qwen3-4B-Instruct-2507-4bit"],
        flash: ["mlx-community/Qwen2.5-1.5B-Instruct-4bit"],
        embedding: ["mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"],
        context: 8192
    )

    /// The demo prompt that exercises the agent.
    ///
    /// Triggering both findAPIs and runCode to compose an answer — plan.md
    /// M9: "one prompt that triggers findAPIs then a composing runCode,"
    /// mirroring plan.md's own worked `tripCities` -> `weather` -> warmest
    /// example.
    static let demoPrompt = "Of the cities on my trip, which is warmest right now?"

    /// The session instructions driving the model toward real tool use —
    /// shared verbatim by this CLI's own session and the gated integration
    /// suite's scenario sessions (`ScenarioRunner.swift`,
    /// `NativeToolCallEvaluation.swift`), so the suite measures exactly the
    /// instructions the product ships.
    ///
    /// Every clause targets an empirically observed failure mode of small
    /// tool-calling models (recorded on tasks `9hchxj6`/`k4mj1gm`,
    /// real-hardware runs on the pinned models):
    ///
    /// - "connected … you have real, working access … never refuse for lack
    ///   of access": the over-refusal mode — a capable model discovering the
    ///   right function via findAPIs and then *still* deflecting with "I
    ///   can't access real-time data, check a weather website".
    /// - "always call findAPIs first": the model skipping discovery and
    ///   guessing function names under a many-tool surface.
    /// - "never simulate or invent data in a snippet": the model calling
    ///   `runCode` with hardcoded made-up city/temperature arrays, invented
    ///   `fetch` calls to external APIs, or `console.log`ged answers instead
    ///   of actually invoking the discovered `tools.*` functions.
    /// - "read each discovered function's declared return type and
    ///   destructure it accordingly": the model treating a declared
    ///   `{ cities: string[] }` return as a bare array and bailing out on
    ///   its own graceful-degradation branch.
    /// - "finds no relevant function, say so": off-topic requests degrading
    ///   to an invented answer instead of an honest miss.
    ///
    /// Deliberately example-free and affirmatively framed: one earlier draft
    /// embedded a worked `return tools.weather({city: "Austin"});` example,
    /// and on real hardware the model pattern-matched it into
    /// `console.log`-ing an invented Austin temperature as its *first*
    /// action; another, negation-heavy draft ("you have NO built-in
    /// knowledge … you cannot answer …") primed over-refusals. The
    /// instructions must neither mention a concrete tool or value the model
    /// could parrot, nor talk it into believing it lacks access.
    static let toolUseInstructions = """
        You are a helpful assistant connected to the user's live data and services through \
        tools. You have real, working access: always call findAPIs first to discover the \
        functions available for the task, then call runCode with a JavaScript snippet that \
        calls those functions under tools.* and returns the result. The tools genuinely execute \
        and return real data — trust their outputs and use them to answer. Read each discovered \
        function's declared return type and destructure it accordingly. Never answer data \
        questions from your own knowledge, never simulate or invent data in a snippet, and \
        never refuse for lack of access — you have access through the tools. If findAPIs truly \
        finds no relevant function, say so.
        """

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
    /// `LanguageModelSession` over `multiTool` (and, unless `--direct`,
    /// `findAPIsTool`), calls `session.respond(to:)` once against
    /// `demoPrompt`, and writes the answer to `output`.
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
    ///     registered with the session, `findAPIsTool` is omitted.
    ///   - resolve: the profile-resolution step.
    ///   - output: where progress/answer lines are written.
    /// - Throws: `CLIRouterUnavailableError` if `resolve` throws; otherwise
    ///   whatever building the tools, `findAPIsTool`'s own initializer, or
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
                .addTool(DemoTripCitiesTool())
                .addTool(DemoWeatherTool())
                .buildRegistry()
            if direct {
                registry = registry.directMode()
            }

            let multiTool = MultiTool(registry: registry)
            // Disambiguated against `MLXLMCommon.Tool` (also in scope via
            // `MLXFoundationModels`/`MLXLMCommon`): the session's tools must
            // be `FoundationModels.Tool` conformers.
            var tools: [any FoundationModels.Tool] = [multiTool]
            if !direct {
                // `findAPIsTool`'s own internal selection tier is backed by a
                // separate, Router-resolved `profile.flash` session — the
                // registry-backed `SelectionTier`'s "librarian on flash"
                // split — independent of `mlxModel`/the main session below.
                tools.append(try FindAPIsTool(registry: registry, librarian: profile.flash))
            }

            let mlxModel = Self.makeMLXLanguageModel(for: profile.standard)
            let session = LanguageModelSession(
                model: mlxModel,
                tools: tools,
                instructions: toolUseInstructions
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
            capabilities: [.guidedGeneration, .toolCalling],
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
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    // MARK: - Recordings directory

    /// Creates a temporary directory for Router transcript recordings.
    ///
    /// Returns the URL of a fresh, uniquely-named directory the `Router`
    /// records `findAPIsTool`'s own selection-tier sessions under (the main
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
