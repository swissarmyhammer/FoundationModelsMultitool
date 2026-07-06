import Foundation
import FoundationModels
import FoundationModelsMultitool
import FoundationModelsRouter
import HuggingFace
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
    /// Enables direct mode: agent runs with `runCode` only, no discovery.
    ///
    /// When set, `findAPIs` is not surfaced to the model — plan.md "Direct
    /// mode (skip discovery)".
    var direct = false

    /// Prints usage text and exits without touching the Router.
    ///
    /// Set by the `--help`/`-h` flags.
    var help = false
}

/// Thrown by `CLIRunner.parse(_:)` for an argument it doesn't recognize.
struct CLIArgumentError: Error, Equatable, CustomStringConvertible {
    /// The unrecognized argument, verbatim.
    let flag: String

    /// A human-readable description of the error.
    ///
    /// Satisfies `CustomStringConvertible`.
    var description: String {
        "\(cliErrorPrefix) unknown argument \"\(flag)\". Run with --help for usage."
    }
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
/// Implements plan.md M9: "a prompt that triggers findAPIs then a
/// multi-tool runCode." Factored out of `main.swift` as a plain, testable
/// entry point:
///
/// - Argument parsing and the Router-unavailable degrade path are
///   unit-tested here with **no model at all**
///   (`Tests/FoundationModelsMultitoolTests/CLIArgumentTests.swift`).
/// - The full live run — resolving a real profile, driving the agent loop,
///   and reading back a findAPIs-then-runCode trace — is exercised end to
///   end by the gated `CLISmokeTests`
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

    /// `--help`'s usage text.
    static let usageText = """
        multitool-cli — a runnable demonstration of the FoundationModelsMultitool pipeline.

        USAGE:
          multitool-cli [--direct] [--help]

        OPTIONS:
          --direct     Run the agent in direct mode: only runCode is surfaced to the
                       model (no findAPIs discovery step); the snippet discovers tools
                       via help()/docs() instead.
          --help, -h   Print this usage text and exit.

        Resolves a small demo model profile via FoundationModelsRouter, wires up a
        couple of fixture tools (tripCities, weather), and asks one question that
        exercises the search-then-code loop (findAPIs, then a composing runCode).
        """

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
    /// Uses `router.resolve(_:reporting:)` unchanged — see `ProfileResolver`.
    static let defaultResolve: ProfileResolver = { router, definition, progress in
        try await router.resolve(definition, reporting: progress)
    }

    /// Parses command-line arguments into `CLIArguments`.
    ///
    /// Excludes the executable name; recognizes `--direct`, `--help`, and `-h`.
    ///
    /// - Parameter arguments: the raw arguments, e.g.
    ///   `CommandLine.arguments.dropFirst()`.
    /// - Returns: the parsed flags.
    /// - Throws: `CLIArgumentError` on the first argument that isn't a
    ///   recognized flag.
    static func parse(_ arguments: [String]) throws -> CLIArguments {
        var result = CLIArguments()
        for argument in arguments {
            switch argument {
            case "--direct":
                result.direct = true
            case "--help", "-h":
                result.help = true
            default:
                throw CLIArgumentError(flag: argument)
            }
        }
        return result
    }

    /// Runs the complete demo pipeline end-to-end.
    ///
    /// Parses `arguments`, and — unless `--help` was given or parsing
    /// failed — resolves `demoProfile`, wires up the demo tools, drives
    /// `MultiToolAgent.respond(to:)` against `demoPrompt`, and writes the
    /// answer plus a readable turn-by-turn trace to `output`.
    ///
    /// - Parameters:
    ///   - arguments: the raw arguments (excluding the executable name).
    ///   - resolve: the profile-resolution step. Defaults to
    ///     `defaultResolve`; a test injects a scripted failure to exercise
    ///     the Router-unavailable path with no model.
    ///   - output: where every line of output (usage, errors, the trace,
    ///     the final answer) is written. Defaults to `print(_:)`; a test
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
    ///   - direct: whether to run the agent in direct mode
    ///     (`registry.directMode()`, no librarian).
    ///   - resolve: the profile-resolution step.
    ///   - output: where trace/answer lines are written.
    /// - Throws: `CLIRouterUnavailableError` if `resolve` throws; otherwise
    ///   whatever building the registry or `MultiToolAgent.respond(to:)`
    ///   throws.
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

            let agent = try MultiToolAgent(
                registry: registry,
                model: profile.standard,
                librarian: direct ? nil : profile.flash,
                instructions: "You are a helpful trip-planning assistant. Use runCode to get things done."
            )

            let answer = try await agent.respond(to: demoPrompt)

            output("")
            output("Trace:")
            for line in Self.traceLines(routerId: router.id, recordingsDir: recordingsDir) {
                output("  \(line)")
            }
            output("")
            output("Answer: \(answer)")
            await profile.release()
        } catch {
            await profile.release()
            throw error
        }
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

    // MARK: - Turn trace

    /// Generates readable trace lines from the Router transcript.
    ///
    /// Reads back the demo run's recorded transcript and renders each
    /// successfully parsed main-loop `AgentStep` as one readable trace
    /// line — plan.md M9: "print... a readable trace of the loop turns."
    ///
    /// Mirrors the parse-by-grammar rule this package's own (internal)
    /// `TranscriptAnalyzer` uses for its trace assertions
    /// (`Tests/FoundationModelsMultitoolIntegrationTests/Support/IntegrationGate.swift`'s
    /// `LiveRouterFixture` pattern): reimplemented here, rather than
    /// reused, because that analyzer is a test-support type internal to
    /// the `FoundationModelsMultitool` module, not part of its public API.
    ///
    /// - Parameters:
    ///   - routerId: the router that ran the demo — its recording root.
    ///   - recordingsDir: the durable transcripts root the router recorded
    ///     under.
    /// - Returns: one readable line per successfully parsed `.standard`-slot
    ///   turn, in recorded order; empty if the transcript can't be read
    ///   back at all.
    private static func traceLines(routerId: ULID, recordingsDir: URL) -> [String] {
        let transcriptRoot = recordingsDir.appendingPathComponent(routerId.description)
        guard let events = try? MergedTranscript.merged(under: transcriptRoot) else {
            return []
        }
        return events
            .filter { $0.slot == .standard && $0.kind == .response }
            .compactMap { event -> String? in
                guard let text = event.text else { return nil }
                let format: any TurnFormat = event.grammar != nil ? GuidedTurnFormat() : TolerantParseTurnFormat()
                guard let step = try? format.parseTurn(text) else { return nil }
                // Renders the parsed step as a single readable trace line,
                // e.g. `findAPIs("...")`, `runCode(<n> chars)`, or `final: ...`.
                switch step {
                case .findAPIs(let task):
                    return "findAPIs(\"\(task)\")"
                case .runCode(let code):
                    return "runCode(\(code.count) chars)"
                case .final(let text):
                    return "final: \(text)"
                }
            }
    }

    // MARK: - Recordings directory

    /// Creates a temporary directory for Router transcript recordings.
    ///
    /// Returns the URL of a fresh, uniquely-named directory — the source
    /// `traceLines(routerId:recordingsDir:)` reads back from after the demo
    /// run completes.
    ///
    /// - Returns: the created directory's URL.
    private static func makeTempRecordingsDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("multitool-cli-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
