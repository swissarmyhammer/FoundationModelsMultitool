import Foundation
import FoundationModels
import FoundationModelsMultitool
import FoundationModelsRouter
// `HuggingFace`, `MLXLMCommon` and `Tokenizers` are named by nothing in this
// file, and all three are load-bearing: the
// `#hubDownloader()`/`#huggingFaceTokenizerLoader()` macros below expand into
// `HubClient`, `MLXLMCommon.Downloader`/`MLXLMCommon.TokenizerLoader` and
// `Tokenizers` code at this call site, and the expansion resolves against the
// imports of the file it lands in. Dropping any of the three fails the build
// inside the expansion.
//
// Model *loading* itself is Router's, so every other MLX module that load
// needs — `MLXVLM` among them, whose `VLMModelFactory` is the only registry
// some checkpoints appear in — is imported by Router's own
// `LiveModelLoader.swift` rather than here; `Package.swift` links them into
// this library, and records there why that link outlives the pin that first
// needed it. The `multitool-cli` executable links this library, so the same
// modules reach the shipped binary through it.
import HuggingFace
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
    /// Whether to run in direct mode: `runCode` and `wait` are registered with the session, `searchTools` is not.
    ///
    /// When set, `searchToolsTool` is not registered with the session —
    /// plan.md "Direct mode (skip discovery)".
    var direct = false

    /// Every MCP server the `--mcp` options named, in the order the options stand.
    ///
    /// Each one becomes a spawned subprocess, a connected `MCPServer`, and one
    /// group of the rendered surface — see `CLIRunner.makeDemoRegistry(direct:mcpServers:)`.
    var mcpServers: [MCPServerSpec] = []

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

// MARK: - One `--mcp` option

/// One `--mcp` option: the name of a server, the command that serves it, and
/// the arguments of that command.
///
/// The name is the noun, so every verb of that server renders at
/// `tools.<name>.<verb>` — eventplan.md § "Registration of capabilities": "The
/// server is the noun, and the tool is the verb." Nothing here names the
/// transport, and the model never sees one.
struct MCPServerSpec: Equatable, Sendable {
    /// The name of the server, and the first segment of every path its verbs
    /// render at.
    let name: String

    /// The command that serves it, exactly as the option spelled it.
    let command: String

    /// The arguments handed to ``command`` on every spawn, in order.
    let arguments: [String]

    /// The absolute path of ``command``.
    ///
    /// `StdioServerProcess` resolves nothing through `PATH` and refuses a
    /// relative path, so a relative path of the option is resolved here,
    /// against the current directory. That is what makes the documented
    /// `--mcp echo=.build/debug/mcp-test-server` run from a checkout.
    var absoluteCommand: String {
        URL(fileURLWithPath: command).standardizedFileURL.path
    }
}

/// An error thrown by `CLIRunner.parse(_:)` for a `--mcp` value it cannot read.
enum CLIMCPArgumentError: Error, Equatable, CustomStringConvertible {
    /// The `--mcp` option stood last, with no value after it.
    case missingValue

    /// The value carries no `=`, so it separates no name from a command.
    /// Carries the value, verbatim.
    case missingSeparator(String)

    /// The value opens at the `=`, so it names no server. Carries the value,
    /// verbatim.
    case emptyName(String)

    /// The value ends at the `=`, so it names no command. Carries the value,
    /// verbatim.
    case emptyCommand(String)

    /// The shape a `--mcp` value takes, as a message spells it.
    private static let valueForm = "<name>=<command>"

    /// A human-readable description of the error, on one line.
    ///
    /// Implementation of the `CustomStringConvertible` protocol requirement.
    var description: String {
        "\(cliErrorPrefix) \(reason)"
    }

    /// What the value lacked, and what to write in its place.
    private var reason: String {
        let option = CLIRunner.mcpFlag.names[0]
        switch self {
        case .missingValue:
            return "\(option) needs a \(Self.valueForm) value after it."
        case .missingSeparator(let value):
            return "\(option) value \"\(value)\" carries no \"=\"; write \(Self.valueForm)."
        case .emptyName(let value):
            return "\(option) value \"\(value)\" names no server before the \"=\"."
        case .emptyCommand(let value):
            return "\(option) value \"\(value)\" names no command after the \"=\"."
        }
    }
}

/// An error thrown when the server a `--mcp` option names cannot be started.
///
/// A configuration failure rather than a Router failure — a command that is not
/// there, or one that never completes the `initialize` handshake — so
/// `CLIRunner.run(...)` maps it to `CLIRunner.ExitCode.usageError` and prints
/// it on one line.
struct CLIMCPStartError: Error, CustomStringConvertible {
    /// The name of the server, as the `--mcp` option spelled it.
    let name: String

    /// The command the option named, as the option spelled it.
    let command: String

    /// What the spawn or the connect reported.
    let underlying: String

    /// A human-readable description of the failure, on one line.
    ///
    /// Implementation of the `CustomStringConvertible` protocol requirement.
    var description: String {
        "\(cliErrorPrefix) MCP server \"\(name)\" did not start from \"\(command)\": \(underlying)"
    }
}

// MARK: - Flags

/// One CLI flag: its recognized spelling(s), the value it reads after its own
/// name, its `OPTIONS:` description, and the effect it has on `CLIArguments`
/// when parsed.
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

    /// How `USAGE:` and `OPTIONS:` spell the arguments this flag reads after
    /// its own name, or `nil` for a flag that reads none.
    let valueSyntax: String?

    /// The `OPTIONS:` description lines shown next to this flag's names, pre-wrapped to `usageText`'s line width.
    ///
    /// Indentation is excluded; `usageText` computes it separately from
    /// every flag's name-column width.
    let descriptionLines: [String]

    /// The effect to apply to `arguments` when `parse(_:)` matches this flag.
    ///
    /// A flag with no ``valueSyntax`` reads nothing and answers `0`; a flag
    /// that takes a value reads it out of `following` and answers how many
    /// arguments it took, which is where `parse(_:)` resumes.
    ///
    /// - Parameters:
    ///   - arguments: the flags parsed so far, which this effect updates.
    ///   - following: every argument standing after this flag's own name.
    /// - Returns: how many arguments of `following` this flag read.
    /// - Throws: what a flag throws for a value it cannot read.
    let apply: @Sendable (_ arguments: inout CLIArguments, _ following: ArraySlice<String>) throws -> Int
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
/// The canonical Router + `RoutedSession` + `MultiTool` example, and the host
/// contract `MultiTool.Registry.makeSessionTools(librarian:)` states, run
/// end to end: resolving a model profile via `Router`, mounting whatever that
/// call vends — `searchTools`, `runCode`, `wait`, or `runCode` and `wait`
/// under `--direct` — on a `RoutedSession` the resolved `.standard` slot
/// vends, and driving one turn by draining `streamEvents(to:)`. The session's
/// own tool-calling loop decides when to call `searchTools` vs `runCode` —
/// this file drives no turn-parsing loop of its own, unlike the retired
/// `MultiToolAgent`-based demo this replaces.
/// Factored out of `main.swift` as a plain, testable entry point:
///
/// - Argument parsing and the Router-unavailable degrade path are
///   unit-tested here with **no model at all**
///   (`Tests/FoundationModelsMultitoolTests/CLIArgumentTests.swift`).
/// - The full live run — resolving a real profile, mounting the vended tools
///   on the `RoutedSession` that profile vends, draining the turn, and
///   printing the model's answer — is exercised end to end by
///   `CLISmokeTests`
///   (`IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/CLISmokeTests.swift`),
///   in the nested integration package.
///
/// This type carries the only `public` surface of the `MultitoolCLI` library.
/// `main.swift` in the `multitool-cli` executable calls `run(arguments:)` and
/// nothing else, and the nested integration package reads `demoProfile`,
/// `embeddingModel`, `run(arguments:resolve:output:)` and `ExitCode`. Every
/// other declaration of this library stays `internal`, where the unit test
/// target reaches it with `@testable import MultitoolCLI`.
public enum CLIRunner {
    /// Process exit codes this runner returns.
    ///
    /// The BSD `sysexits.h` convention for the two documented failure
    /// modes; `0` for success.
    public enum ExitCode {
        /// Exit code indicating successful completion (or that `--help` was requested).
        public static let success: Int32 = 0
        /// Bad arguments; the same value as `sysexits.h`'s `EX_USAGE` (64).
        public static let usageError: Int32 = 64
        /// Exit code when the Router's live path cannot be resolved.
        ///
        /// The same value as `sysexits.h`'s `EX_UNAVAILABLE` (69).
        public static let unavailable: Int32 = 69
    }

    /// The `--direct` flag, for running in direct mode (`runCode` and `wait` registered with the session, no `searchToolsTool`).
    static let directFlag = Flag(
        names: ["--direct"],
        valueSyntax: nil,
        descriptionLines: [
            "Run in direct mode: the registry vends runCode and wait alone,",
            "with no searchTools tool; the snippet discovers tools via",
            "help()/docs() instead.",
        ],
        apply: { arguments, _ in
            arguments.direct = true
            return 0
        }
    )

    /// The `--mcp` option, for attaching one stdio MCP server to the demo.
    ///
    /// Repeatable: one option for each server. The name is the noun, so the
    /// verbs of that server render at `tools.<name>.<verb>` and the model
    /// never sees the transport.
    static let mcpFlag = Flag(
        names: ["--mcp"],
        valueSyntax: "<name>=<command> [args...]",
        descriptionLines: [
            "Attach an MCP server this CLI spawns and speaks to over stdio.",
            "The name is the noun, so the verbs of the server render at",
            "tools.<name>.<verb>. The command is the executable, resolved",
            "against the current directory when the path is relative. Each",
            "argument after it that is not a flag of this CLI goes to the",
            "server. Repeat the option to attach a second server.",
        ],
        apply: { arguments, following in
            let read = try readMCPOption(from: following)
            arguments.mcpServers.append(read.spec)
            return read.consumed
        }
    )

    /// The `--help`/`-h` flag, for printing usage text and exiting without touching the Router.
    static let helpFlag = Flag(
        names: ["--help", "-h"],
        valueSyntax: nil,
        descriptionLines: ["Print this usage text and exit."],
        apply: { arguments, _ in
            arguments.help = true
            return 0
        }
    )

    /// The flags `parse(_:)` recognizes, in `USAGE:`/`OPTIONS:` display order.
    ///
    /// The single source of truth `usageText` is generated from, and
    /// `parse(_:)` dispatches against — see `Flag`'s documentation.
    static let flags: [Flag] = [directFlag, mcpFlag, helpFlag]

    /// Every spelling ``flags`` recognizes.
    ///
    /// Where the arguments of a `--mcp` server command stop: an argument this
    /// set holds belongs to the CLI, and every other one belongs to the server
    /// — see ``readMCPOption(from:)``.
    static let flagNames: Set<String> = Set(flags.flatMap(\.names))

    /// How `USAGE:` and `OPTIONS:` spell one flag: its names, and the value
    /// syntax it reads after them.
    ///
    /// The two listings differ in how many names they show and in the brackets
    /// they wrap the result in, and in nothing else, so the value syntax is
    /// appended in one place.
    ///
    /// - Parameters:
    ///   - names: the names to spell, already joined.
    ///   - flag: the flag whose value syntax follows them.
    /// - Returns: `names`, with the value syntax after it when the flag reads one.
    private static func spelling(of names: String, for flag: Flag) -> String {
        guard let valueSyntax = flag.valueSyntax else { return names }
        return "\(names) \(valueSyntax)"
    }

    /// `--help`'s usage text, generated from `flags`.
    static var usageText: String {
        let leadingIndent = "  "
        let columnGap = "   "
        let nameColumns = flags.map { spelling(of: $0.names.joined(separator: ", "), for: $0) }
        let columnWidth = nameColumns.map(\.count).max() ?? 0
        let continuationIndent = String(repeating: " ", count: leadingIndent.count + columnWidth + columnGap.count)
        let optionsLines = zip(flags, nameColumns).flatMap { flag, nameColumn -> [String] in
            let paddedName = nameColumn.padding(toLength: columnWidth, withPad: " ", startingAt: 0)
            return flag.descriptionLines.enumerated().map { index, line in
                index == 0 ? "\(leadingIndent)\(paddedName)\(columnGap)\(line)" : "\(continuationIndent)\(line)"
            }
        }
        let usageSummary = flags.map { "[\(spelling(of: $0.names[0], for: $0))]" }.joined(separator: " ")
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
    /// `demoProfile` below puts it in `standard` and in `flash`, and the
    /// integration suite's `multitoolTinyProfile` *is* `demoProfile`
    /// (`IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/LiveRouterFixture.swift`),
    /// so changing this one line moves the CLI and every graded scenario
    /// together. That matters more than it sounds: the suite exists to measure
    /// what a host actually runs, and while the two lists were written out
    /// separately they were free to disagree — the CLI and the suite each named
    /// their own models, and nothing failed when they drifted.
    ///
    /// `LiveRouterFixture.swift` carries the measurement history behind every
    /// model that has held this slot, because that history is a record of
    /// real-model runs. This is where the choice lives; that is where the
    /// evidence lives.
    ///
    /// Deliberately `internal`, not `public`: the integration package reads
    /// `demoProfile` and `embeddingModel` and never this constant, so keeping
    /// it out of the library's public surface holds the model choice inside the
    /// one module that makes it.
    ///
    /// No `@revision`: this tracks the repository's default revision, so it is
    /// a model *choice* rather than a version lock.
    static let generationModel: ModelRef = "mlx-community/Qwen3.8-27B-mxfp4"

    /// The embedding model, unchanged across every generation-model swap and
    /// shared with Router's own gated suite so the weights are already cached.
    public static let embeddingModel: ModelRef = "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"

    /// The profile used for the demo run, and by the integration suite.
    ///
    /// Deliberate use of tool-calling-capable models. The integration suite
    /// resolves this exact value rather than a parallel definition of its
    /// own — see `generationModel` above for why.
    public static let demoProfile = ProfileDefinition(
        name: "multitool-cli-demo",
        description: "Tool-calling-capable models for the multitool-cli sample.",
        // **This is the one place any model is named.** The integration suite
        // does not keep its own pin: `multitoolTinyProfile` is this value
        // (`LiveRouterFixture.swift`), so the suite measures the models the CLI
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
        // than imposing one, exactly as the integration suite's
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
    public typealias ProfileResolver = @Sendable (
        _ router: Router,
        _ definition: ProfileDefinition,
        _ progress: ResolutionProgress
    ) async throws -> LanguageModelProfile

    /// The default profile resolution implementation.
    ///
    /// `router.resolve(profile:reporting:)`, unchanged — see `ProfileResolver`.
    ///
    /// `public` because it is the default value of `run(arguments:resolve:output:)`'s
    /// `resolve` parameter, and a caller outside this module writes that
    /// default whenever it omits the argument.
    public static let defaultResolve: ProfileResolver = { router, definition, progress in
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
    ///   recognized flag, or `CLIMCPArgumentError` for a `--mcp` value that
    ///   cannot be read.
    static func parse(_ arguments: [String]) throws -> CLIArguments {
        var result = CLIArguments()
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            guard let flag = flags.first(where: { $0.names.contains(argument) }) else {
                throw CLIArgumentError(flag: argument)
            }
            let read = try flag.apply(&result, arguments[arguments.index(after: index)...])
            // The flag's own name, plus whatever it read after it.
            index = arguments.index(index, offsetBy: read + 1)
        }
        return result
    }

    // MARK: - Reading one `--mcp` option

    /// The character a `--mcp` value separates the name of the server from the
    /// command with.
    private static let mcpNameSeparator: Character = "="

    /// Reads one `--mcp` option out of the arguments standing after the flag
    /// name.
    ///
    /// The first argument is the `<name>=<command>` value. Every argument after
    /// it that is no spelling of a flag of this CLI is an argument of the
    /// server command, so a server carries its own flags — `--mode echo` for
    /// `mcp-test-server` — with no separator of its own.
    ///
    /// - Parameter following: every argument standing after the `--mcp` name.
    /// - Returns: the server the option names, and how many arguments were read.
    /// - Throws: ``CLIMCPArgumentError`` for a value this cannot read.
    static func readMCPOption(
        from following: ArraySlice<String>
    ) throws -> (spec: MCPServerSpec, consumed: Int) {
        guard let value = following.first else {
            throw CLIMCPArgumentError.missingValue
        }
        guard let separator = value.firstIndex(of: mcpNameSeparator) else {
            throw CLIMCPArgumentError.missingSeparator(value)
        }
        let name = String(value[value.startIndex..<separator])
        guard !name.isEmpty else {
            throw CLIMCPArgumentError.emptyName(value)
        }
        let command = String(value[value.index(after: separator)...])
        guard !command.isEmpty else {
            throw CLIMCPArgumentError.emptyCommand(value)
        }
        let serverArguments = following.dropFirst().prefix { !flagNames.contains($0) }
        let spec = MCPServerSpec(name: name, command: command, arguments: Array(serverArguments))
        // The value itself, plus every argument of the server standing after it.
        return (spec, serverArguments.count + 1)
    }

    /// Runs the complete demo pipeline end-to-end.
    ///
    /// Parses `arguments`, and — unless `--help` was given or parsing
    /// failed — resolves `demoProfile`, mounts the tools the registry vends
    /// (`searchTools`, `runCode`, `wait` — or `runCode` and `wait` alone under
    /// `--direct`) on a `RoutedSession` the resolved profile vends, drives one
    /// turn against `demoPrompt` by draining `streamEvents(to:)`, and writes
    /// the answer to `output`.
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
    ///   `--help`, `ExitCode.usageError` for an argument error or for a `--mcp`
    ///   server that does not start, or `ExitCode.unavailable` if the Router
    ///   path couldn't be resolved (or the demo otherwise failed after
    ///   resolution).
    public static func run(
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
            try await runDemo(
                direct: parsed.direct, mcpServers: parsed.mcpServers, resolve: resolve,
                output: output)
            return ExitCode.success
        } catch let error as CLIMCPStartError {
            // A `--mcp` value that names no runnable server is a bad argument,
            // not an unavailable Router, so it takes the usage exit code and
            // one line rather than the two-line Router message.
            output(error.description)
            return ExitCode.usageError
        } catch let error as CLIRouterUnavailableError {
            output(error.description)
            return ExitCode.unavailable
        } catch {
            output("\(cliErrorPrefix) \(error)")
            return ExitCode.unavailable
        }
    }

    // MARK: - The registry of one demo run

    /// One server a `--mcp` option started: the connected server, and the
    /// subprocess it speaks to over stdio.
    struct StartedMCPServer {
        /// The connected server. Its name is the noun of every
        /// `tools.<name>.<verb>` path its catalog renders.
        let server: MCPServer

        /// The subprocess that serves it.
        ///
        /// Recorded into the pool, which ends it with the session.
        /// `CLIArgumentTests` reads it to prove that no subprocess outlives a
        /// run.
        let process: StdioServerProcess
    }

    /// The rendered registry of one demo run, and what a host holds beside it.
    struct DemoRegistry {
        /// The registry whose tools the session mounts.
        let registry: MultiTool.Registry

        /// The recorded registrations a rebuild renders again — the `source`
        /// the `SurfaceRefresher` reads.
        let source: MultiTool.RegistrySource

        /// Every server the `--mcp` options started, in option order.
        let servers: [StartedMCPServer]

        /// The pool that stops the attachment, disconnects each server, and
        /// ends each subprocess — in that order.
        let pool: MCPServerPool
    }

    /// Starts every server the `--mcp` options name, and renders the registry
    /// of the demo: the two fixture tools, plus one group for each server.
    ///
    /// The servers connect before the build, which is what eventplan.md asks of
    /// a host: "Servers connect before `buildRegistry()`." A failure after a
    /// server started shuts the pool down, so a call that throws leaves no
    /// subprocess behind.
    ///
    /// Not `private`:
    /// `Tests/FoundationModelsMultitoolTests/CLIArgumentTests.swift` builds the
    /// same registry to drive a direct-mode snippet against a real
    /// `mcp-test-server`, with no model and no Router.
    ///
    /// - Parameters:
    ///   - direct: whether the registry vends `runCode` and `wait` alone.
    ///   - specs: what the `--mcp` options named, in option order.
    /// - Returns: the registry, its servers, and the pool that shuts them down.
    /// - Throws: ``CLIMCPStartError`` when a server does not start, and what
    ///   `MultiTool.Builder.buildRegistry()` throws when the rendered surface
    ///   is not legal — a server name that is no identifier, or a noun another
    ///   registration already owns.
    static func makeDemoRegistry(
        direct: Bool, mcpServers specs: [MCPServerSpec]
    ) async throws -> DemoRegistry {
        let builder = MultiTool.Builder()
            .addTool(DemoTripTool())
            .addTool(DemoWeatherTool())
        let started = try await startMCPServers(specs, recordingInto: builder.serverPool)
        do {
            try await builder.withMCP(servers: started.map(\.server))
            var registry = try builder.buildRegistry()
            if direct {
                registry = registry.directMode()
            }
            return DemoRegistry(
                registry: registry, source: builder.registrySource, servers: started,
                pool: builder.serverPool)
        } catch {
            await builder.serverPool.shutdownAll()
            throw error
        }
    }

    /// Spawns and connects one server for each `--mcp` option, recording each
    /// subprocess and each server into `pool`.
    ///
    /// Each pair is recorded before the connect, so a connect that fails still
    /// leaves the pool holding the subprocess the spawn made. A failure shuts
    /// the whole pool down before it throws, and `MCPServerPool.add(server:)`
    /// records a server one time, so the later `withMCP(servers:)` adds none of
    /// these a second time.
    ///
    /// - Parameters:
    ///   - specs: what the `--mcp` options named, in option order.
    ///   - pool: where each started server and each subprocess is recorded.
    /// - Returns: the started servers, in the order of `specs`.
    /// - Throws: ``CLIMCPStartError`` when a server does not spawn or does not
    ///   connect.
    private static func startMCPServers(
        _ specs: [MCPServerSpec], recordingInto pool: MCPServerPool
    ) async throws -> [StartedMCPServer] {
        var started: [StartedMCPServer] = []
        for spec in specs {
            do {
                let process = try StdioServerProcess(
                    command: spec.absoluteCommand, args: spec.arguments, name: spec.name)
                let server = MCPServer(name: spec.name)
                await pool.add(process: process)
                await pool.add(server: server)
                try await server.connect(via: process.respawn, backoffPolicy: .default)
                started.append(StartedMCPServer(server: server, process: process))
            } catch {
                await pool.shutdownAll()
                throw CLIMCPStartError(
                    name: spec.name, command: spec.command, underlying: String(describing: error))
            }
        }
        return started
    }

    // MARK: - The surface listing

    /// The heading the surface listing opens with.
    static let surfaceListingHeading = "Tool surface:"

    /// The indent each entry of the surface listing stands under.
    private static let surfaceListingIndent = "  "

    /// Writes one line for each rendered entry of `surface`, so a reader sees
    /// which verbs the model was given — the `tools.<noun>.<verb>` of every
    /// attached MCP server among them.
    ///
    /// Not `private`: `CLIArgumentTests` reads the lines this writes.
    ///
    /// - Parameters:
    ///   - surface: the rendered catalog to list.
    ///   - output: where each line is written.
    static func reportSurface(_ surface: APISurface, output: @Sendable (String) -> Void) {
        output(surfaceListingHeading)
        for entry in surface.entries {
            output("\(surfaceListingIndent)tools.\(entry.path)")
        }
    }

    // MARK: - The demo run

    /// Starts the MCP servers, renders the registry, lists the surface, drives
    /// the turn, and shuts the pool down.
    ///
    /// Factored out of `run(...)` as its whole body, so `run(...)` only has to
    /// decide which exit code an error maps to.
    ///
    /// The servers start before the model resolves. A `--mcp` value that names
    /// no runnable command is a configuration failure, and a user reads it at
    /// once rather than after a model download.
    ///
    /// - Parameters:
    ///   - direct: whether to run in direct mode — the registry vends
    ///     `runCode` and `wait`, and `searchToolsTool` is omitted. Direct
    ///     mode takes discovery away, never the background.
    ///   - mcpServers: what the `--mcp` options named, in option order.
    ///   - resolve: the profile-resolution step.
    ///   - output: where progress/answer lines are written.
    /// - Throws: ``CLIMCPStartError`` when a server does not start,
    ///   `CLIRouterUnavailableError` if `resolve` throws; otherwise whatever
    ///   building the tools, `searchToolsTool`'s own initializer, or the turn's
    ///   own event stream throws.
    private static func runDemo(
        direct: Bool,
        mcpServers: [MCPServerSpec],
        resolve: ProfileResolver,
        output: @escaping @Sendable (String) -> Void
    ) async throws {
        let demo = try await Self.makeDemoRegistry(direct: direct, mcpServers: mcpServers)
        Self.reportSurface(demo.registry.surface, output: output)
        do {
            try await Self.runTurn(demo, resolve: resolve, output: output)
        } catch {
            // The shutdown that follows the turn, on the failure path as on the
            // success one: the pool stops the refresher, disconnects each
            // server, and ends each subprocess. A demo that drives one turn has
            // no parked run to sweep first.
            await demo.pool.shutdownAll()
            throw error
        }
        await demo.pool.shutdownAll()
    }

    /// Resolves a profile, mounts the tools `demo` vends on a `RoutedSession`,
    /// watches the catalog of each MCP server, and prints the model's answer.
    ///
    /// - Parameters:
    ///   - demo: the registry of this run, its servers, and its pool.
    ///   - resolve: the profile-resolution step.
    ///   - output: where progress/answer lines are written.
    /// - Throws: `CLIRouterUnavailableError` if `resolve` throws; otherwise
    ///   whatever building the tools, `searchToolsTool`'s own initializer, or
    ///   the turn's own event stream throws.
    private static func runTurn(
        _ demo: DemoRegistry,
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
        // `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift`'s
        // own `LiveRouterFixture.tearDown()` calls, rather than an
        // unstructured, un-awaited cleanup `Task` that `main.swift`'s
        // immediate `exit(_:)` after `run(...)` returns would likely never
        // let finish.
        do {
            // The registry vends its own mounted tools, in the order the
            // model reads them — `searchTools`, then `runCode`, then `wait`,
            // with discovery dropped once `directMode()` has taken it
            // away. The `searchTools` half's internal selection tier is backed
            // by a Router-resolved `profile.flash` session — the
            // registry-backed `SelectionTier`'s "librarian on flash" split.
            //
            // `flash` and `standard` name the same model here (`demoProfile`),
            // so that tier and the main session below share one resident
            // container. See `demoProfile` for what that costs.
            //
            // The staging half of the same call is what a rebuilt registry is
            // handed to, and it is vended here rather than made by a factory:
            // `makeSessionToolsAndStaging(librarian:)` starts nothing of its
            // own, so a host that mounts a session leaves no task behind.
            //
            // Explicitly typed, so the element type a host mounts is stated
            // where a reader meets it rather than inferred from a call in
            // another module.
            let mounted: (tools: [any FoundationModels.Tool], staging: any RegistryStaging) =
                try demo.registry.makeSessionToolsAndStaging(librarian: profile.flash)

            // The refresher starts AFTER the session tools, and the pool stops
            // it BEFORE it closes any server — the two halves of the MCP
            // lifetime a host owns. From here a `tools/list_changed`, a
            // reconnect, or a late server reaches the surface at the next turn
            // boundary with no further action of this file's.
            //
            // Made even when no `--mcp` option named a server: one path, one
            // shutdown, and a refresher over no server watches nothing and
            // costs one parked task that `shutdownAll()` ends.
            let refresher = SurfaceRefresher(
                source: demo.source, staging: mounted.staging,
                servers: demo.servers.map(\.server))
            refresher.start()
            await demo.pool.attach(attachment: refresher)

            // Vended by the resolved profile, because the session type is part
            // of the host contract and not a detail (see
            // `Registry.makeSessionTools(librarian:)`). A `RoutedSession` reads
            // each tool's own declared `ToolMount`, and `MultiTool` declares
            // `.background` with no condition on it (`MultiTool.mount`), so
            // every `runCode` call here starts a background run and answers
            // with a pending envelope the model then collects with the mounted
            // `wait` tool. Mounted on a bare
            // `FoundationModels.LanguageModelSession` the same tools cannot go
            // to the background at all: that session reads no mount
            // declaration, so the snippet blocks, no envelope is ever written,
            // and `wait` has nothing to join.
            //
            // **Every run of this demo takes the background path.**
            // `DemoTripTool` and `DemoWeatherTool` answer in microseconds, and
            // that changes nothing. There is no clock to beat and no race to
            // win: a snippet that finishes at once gets a completion token
            // exactly as a slow one does. The fixtures keep the demo quick;
            // they do not keep it synchronous.
            //
            // Which lines then print is the model's own doing rather than this
            // file's. The pending envelope carries
            // `MultiTool.collectInstruction(forCompletionToken:)`, which tells
            // the model to call `wait` with that token, so a model that follows
            // it produces a `Calling wait` line and then a settled-run line. A
            // model that ignores it produces neither, and that is a model
            // result and not a wiring defect.
            //
            // The background scenario in
            // `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests`
            // adds a deliberately slow tool, so it measures the wait instead of
            // only reaching it.
            //
            // No instructions. Mounting the vended tools is the whole host
            // contract — their descriptions carry the entire behavioral
            // contract, and a session instruction a real host may never pass
            // must not be load-bearing (see
            // `Registry.makeSessionTools(librarian:)`).
            let session = profile.standard.makeSession(tools: mounted.tools)

            // Drained, never `respond(to:)`. `RoutedSession.respond(to:)`
            // self-drains the background runs (Router `^nmpejc5`), so it would answer
            // this prompt just as well — but `streamEvents(to:)` is the surface
            // the host contract names, the surface every integration scenario drives,
            // and the only one on which a tool still working can report that it
            // is working. A demo that took the shorter call would leave out
            // half of what a host has to write.
            //
            // The choice decides who collects. `respond(to:)` awaits each
            // background run itself and re-prompts the model with the results;
            // `streamEvents(to:)` declares that it does not drain the run
            // plane, so this turn can end while the run is still going and
            // `.runSettled` below reports the ending to *this* code rather than
            // to the model. On this surface the mounted `wait` tool is how the
            // model gets a result inside the turn, which is why the registry
            // vends it and why the demo mounts it.
            let answer = try await Self.drainTurn(
                await session.streamEvents(to: demoPrompt),
                output: output
            )

            output("")
            output("Answer: \(answer)")
            await profile.release()
        } catch {
            await profile.release()
            throw error
        }
    }

    // MARK: - Driving the turn

    /// What a reported line says in place of a detail the event did not carry.
    ///
    /// Router leaves `SessionEvent.toolStatus`' `summary` `nil` for a status it
    /// has no text for, and a line that ended at its own colon would read as
    /// truncated output rather than as a tool that said nothing.
    private static let missingDetail = "no detail"

    /// Drains one turn's event stream, reporting each tool call while the turn
    /// runs, and returns the turn's answer.
    ///
    /// This is the host half of the contract
    /// `MultiTool.Registry.makeSessionTools(librarian:)` states: a session that
    /// carries the mounted tools is driven by draining `streamEvents(to:)`.
    /// Every line written here is one a `respond(to:)` caller never sees. Each
    /// `runCode` call goes to the background, and it reports itself while it is
    /// still working, where `respond(to:)` is a single await that returns only
    /// once the answer is whole.
    ///
    /// Not `private`:
    /// `Tests/FoundationModelsMultitoolTests/CLITurnDrainTests.swift` drives it
    /// over a scripted stream, so the drain is covered with no model, no Router
    /// and no network.
    ///
    /// - Parameters:
    ///   - events: the turn's event stream — `RoutedSession.streamEvents(to:)`
    ///     in production.
    ///   - output: where each reported line is written.
    /// - Returns: the turn's answer — every text fragment produced after the
    ///   last `.textReset`, which is the string `respond(to:)` returns for the
    ///   same turn.
    /// - Throws: whatever the stream throws.
    static func drainTurn(
        _ events: AsyncThrowingStream<SessionEvent, Error>,
        output: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        var answer = ""
        // A call's tool name arrives once, on its own `.toolCall`. Every later
        // event about that call carries the call's id alone, so the name is
        // kept here to report the call's progress under it.
        var toolNamesByCallID: [String: String] = [:]
        for try await event in events {
            switch event {
            case .textDelta(let fragment):
                answer += fragment
            case .textReset:
                // The model abandoned the answer it was writing and began
                // another, which is what a tool-using turn does. Clearing here
                // is what makes this drain return the same string
                // `respond(to:)` returns for the turn (Router `^w8dzvee` D2);
                // a consumer that keeps the superseded text prints the model's
                // pre-tool guess in front of the real answer.
                answer = ""
            case .toolCall(let id, let name, _):
                toolNamesByCallID[id] = name
                output("Calling \(name)")
            case .toolStatus(let id, .running, let summary, _):
                output(
                    "\(Self.toolName(of: id, in: toolNamesByCallID)) in process: \(summary ?? Self.missingDetail)"
                )
            case .toolStatus(let id, .completed, _, _):
                output("\(Self.toolName(of: id, in: toolNamesByCallID)) done")
            case .toolStatus(let id, .failed, let summary, _):
                output(
                    "\(Self.toolName(of: id, in: toolNamesByCallID)) failed: \(summary ?? Self.missingDetail)"
                )
            case .generationStalled(let stall):
                // Router reports a stall instead of imposing a timeout: no
                // token has moved for a while, which a long turn on a real
                // model does. Printed and never acted on — a demo that stayed
                // silent here reads as stuck while it is working.
                output("\(stall)")
            case .runSettled(let terminal):
                // A background call answered its envelope earlier in the
                // turn, or in an earlier one; this is the one terminal event
                // that says how that run ended. A demo that stayed silent
                // here would leave the user with a token and no ending.
                output(
                    "\(terminal.tool) run \(terminal.correlationID) settled: "
                        + "\(terminal.outcome?.rawValue ?? Self.missingDetail)"
                )
            case .toolStatus, .turnStarted, .reasoningDelta, .toolInvocation, .entryRecorded,
                .compaction, .discoveryPrimingFailed, .turnEnded:
                // `.toolStatus` here is the residue of the three statuses
                // handled above. The rest are the correlation frame, reasoning
                // fragments, the live invocation records, transcript-entry ids,
                // compaction reports, seeding reports and token usage: real
                // signal for a host that keeps a view of the session, and none
                // of it part of what this demo prints.
                break
            }
        }
        return answer
    }

    /// The name of the tool a call id belongs to, for a line reporting on that
    /// call.
    ///
    /// - Parameters:
    ///   - callID: the call's id, as `SessionEvent.toolStatus` carries it.
    ///   - namesByCallID: the names this turn's `.toolCall` events announced.
    /// - Returns: the tool's name, or the call id itself when no `.toolCall`
    ///   announced that call — an id a reader can still correlate against the
    ///   recorded transcript, where a placeholder word could not be.
    private static func toolName(of callID: String, in namesByCallID: [String: String]) -> String {
        namesByCallID[callID] ?? callID
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
    /// records every session it vends under — `searchToolsTool`'s own
    /// selection-tier sessions, and the demo's main turn, which is a
    /// `RoutedSession` too.
    ///
    /// - Returns: the created directory's URL.
    private static func makeTempRecordingsDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("multitool-cli-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
