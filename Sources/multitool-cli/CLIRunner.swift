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
/// Ensures error output is consistently attributable to `multitool-cli` —
/// reused by `CLIArgumentError.description`,
/// `CLIRouterUnavailableError.description`, and `CLIRunner.run(...)`'s
/// catch-all branch.
private let cliErrorPrefix = "multitool-cli:"

// MARK: - Argument parsing

/// The command-line flags `CLIRunner.parse(_:)` recognizes.
struct CLIArguments: Equatable {
    /// Enables direct mode: only `multiTool`/`runCode` is registered with
    /// the session, no discovery.
    ///
    /// When set, `findAPIsTool` is not registered with the session —
    /// plan.md "Direct mode (skip discovery)".
    var direct = false

    /// Prints usage text and exits without touching the Router.
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
    /// Satisfies `CustomStringConvertible`.
    var description: String {
        "\(cliErrorPrefix) unknown argument \"\(flag)\". Run with \(CLIRunner.helpFlag.names[0]) for usage."
    }
}

// MARK: - Flags

/// One CLI flag: its recognized spelling(s), `OPTIONS:` description, and the
/// effect it has on `CLIArguments` when parsed.
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

    /// The `OPTIONS:` description lines shown next to this flag's names,
    /// pre-wrapped to `usageText`'s line width (excluding indentation, which
    /// `usageText` computes from every flag's name-column width).
    let descriptionLines: [String]

    /// Applies this flag's effect to `arguments` when `parse(_:)` matches it.
    let apply: @Sendable (_ arguments: inout CLIArguments) -> Void
}

// MARK: - The Router-unavailable degrade path

/// Error thrown when the Router's live path cannot be resolved.
///
/// Thrown by `CLIRunner.run(...)`'s internals when the demo can't proceed
/// past model resolution — plan.md M9: "degrade gracefully (clear message +
/// nonzero exit) when the Router live path is unavailable."
struct CLIRouterUnavailableError: Error, CustomStringConvertible {
    /// What `resolve` threw.
    let underlying: Error

    /// A human-readable message describing the Router unavailability.
    ///
    /// Explains what went wrong, plus why (the Router's live inference path
    /// not being wired up in this environment is the expected cause
    /// pre-Router-M7, but any resolution failure — including an
    /// unsatisfiable profile or a download error — surfaces the same way).
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
/// resolves a model profile via `Router`, wraps the resolved `.standard`
/// generation slot as a real `FoundationModels.LanguageModel`
/// (`MLXLanguageModel`), and registers `multiTool` (and, unless `--direct`,
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
    /// Follows the BSD `sysexits.h` convention for the two documented
    /// failure modes; `0` for success.
    enum ExitCode {
        /// Ran to completion (or `--help` was requested).
        static let success: Int32 = 0
        /// Bad arguments — mirrors `sysexits.h`'s `EX_USAGE` (64).
        static let usageError: Int32 = 64
        /// Exit code when the Router's live path cannot be resolved.
        ///
        /// Mirrors `sysexits.h`'s `EX_UNAVAILABLE` (69).
        static let unavailable: Int32 = 69
    }

    /// The `--direct` flag: run in direct mode (only `multiTool`/`runCode`
    /// registered with the session, no `findAPIsTool`).
    static let directFlag = Flag(
        names: ["--direct"],
        descriptionLines: [
            "Run in direct mode: only the runCode tool is registered with the",
            "session (no findAPIs tool); the snippet discovers tools via",
            "help()/docs() instead.",
        ],
        apply: { $0.direct = true }
    )

    /// The `--help`/`-h` flag: print usage text and exit without touching the Router.
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
    /// Deliberately uses tiny, tool-calling-capable models, matching the
    /// gated integration suite's own `multitoolTinyProfile`
    /// (`Tests/FoundationModelsMultitoolIntegrationTests/Support/IntegrationGate.swift`)
    /// so a machine that already ran that suite shares the cached weights.
    static let demoProfile = ProfileDefinition(
        name: "multitool-cli-demo",
        description: "Small tool-calling-capable models for the multitool-cli sample.",
        standard: ["mlx-community/Qwen2.5-1.5B-Instruct-4bit"],
        flash: ["mlx-community/Qwen2.5-1.5B-Instruct-4bit"],
        embedding: ["mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"],
        context: 8192
    )

    /// The demo prompt that exercises the agent.
    ///
    /// Triggers both findAPIs and runCode to compose an answer — plan.md
    /// M9: "one prompt that triggers findAPIs then a composing runCode,"
    /// mirroring plan.md's own worked `tripCities` -> `weather` -> warmest
    /// example.
    static let demoPrompt = "Of the cities on my trip, which is warmest right now?"

    /// Resolves a profile definition into a language model profile.
    ///
    /// Converts an authored `ProfileDefinition` into a resolved, resident
    /// `LanguageModelProfile` on a given `Router` — injectable so
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
    /// Uses `router.resolve(profile:reporting:)` unchanged — see `ProfileResolver`.
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

    /// The resolve-through-print body of `run(...)`.
    ///
    /// Factored out so `run(...)` only has to decide which exit code an
    /// error maps to.
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
                instructions: "You are a helpful trip-planning assistant. Use runCode to get things done."
            )

            let response = try await session.respond(to: demoPrompt)

            output("")
            output("Answer: \(response.content)")
            await profile.release()
        } catch {
            await profile.release()
            throw error
        }
    }

    /// Wraps a resolved Router generation slot as a real
    /// `FoundationModels.LanguageModel`, so a native `LanguageModelSession`
    /// can be built directly over it.
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
    /// - Parameter routedLLM: the resolved Router generation slot to wrap —
    ///   typically `profile.standard`.
    /// - Returns: an `MLXLanguageModel` over the same resident model.
    private static func makeMLXLanguageModel(for routedLLM: RoutedLLM) -> MLXLanguageModel {
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

    /// Resolves a model id to its on-disk weights directory, for
    /// `MLXLanguageModel`'s availability checks (`modelExistsOnDisk()`,
    /// `freeDiskSpaceBytes`) — never consulted by the load path itself,
    /// which always goes through `ModelCache`/`load` (see
    /// `makeMLXLanguageModel(for:)`).
    ///
    /// Mirrors `MLXLanguageModel`'s own doc-comment example: resolves
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
