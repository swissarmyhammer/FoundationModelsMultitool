import Foundation
import FoundationModelsExtras
import MCPTestServer
import Testing
import os

import FoundationModelsRouter

@testable import FoundationModelsMultitool
@testable import MultitoolCLI

/// M9 coverage for `CLIRunner`: argument parsing and the Router-unavailable
/// degrade path, both exercised with **no model at all** — plan.md M9's
/// model-free acceptance criteria ("Argument parsing... is unit-tested without
/// a model" / "Router-unavailable path... unit-tested via an injected
/// failing resolver"). The full live run (a real Router resolve, the agent
/// loop, the searchTools-then-runCode trace) is exercised separately by
/// `CLISmokeTests`, in the nested `IntegrationTests` package.
@Suite("CLIRunner")
struct CLIArgumentTests {
    // MARK: - Argument parsing

    @Test("parsing no arguments yields the all-false default")
    func parseDefaults() throws {
        let parsed = try CLIRunner.parse([])
        #expect(parsed == CLIArguments())
    }

    @Test("parsing --direct sets direct mode")
    func parseDirect() throws {
        let parsed = try CLIRunner.parse(["--direct"])
        #expect(parsed.direct)
        #expect(!parsed.help)
    }

    @Test("parsing --help sets help")
    func parseHelp() throws {
        let parsed = try CLIRunner.parse(["--help"])
        #expect(parsed.help)
        #expect(!parsed.direct)
    }

    @Test("parsing -h also sets help")
    func parseShortHelp() throws {
        let parsed = try CLIRunner.parse(["-h"])
        #expect(parsed.help)
    }

    @Test("parsing --direct and --help together sets both")
    func parseBothFlags() throws {
        let parsed = try CLIRunner.parse(["--direct", "--help"])
        #expect(parsed.direct)
        #expect(parsed.help)
    }

    @Test("parsing an unrecognized argument throws CLIArgumentError naming it")
    func parseUnknownFlagThrows() {
        #expect {
            try CLIRunner.parse(["--bogus"])
        } throws: { error in
            (error as? CLIArgumentError) == CLIArgumentError(flag: "--bogus")
        }
    }

    // MARK: - `--mcp` parsing

    /// The command every parse case below names. It is an executable that
    /// exists, so a parse case fails on the parse alone and never on a path.
    private static let parsedCommand = "/usr/bin/true"

    /// A second command, for the case that names two servers.
    private static let secondParsedCommand = "/usr/bin/false"

    @Test("parsing --mcp reads the name of the server and its command")
    func parseMCPServer() throws {
        let parsed = try CLIRunner.parse(["--mcp", "echo=\(Self.parsedCommand)"])
        #expect(
            parsed.mcpServers == [
                MCPServerSpec(name: "echo", command: Self.parsedCommand, arguments: [])
            ])
    }

    @Test("parsing --mcp reads each following argument that is not a flag of this CLI as an argument of the server")
    func parseMCPServerArguments() throws {
        let parsed = try CLIRunner.parse([
            "--mcp", "echo=\(Self.parsedCommand)", "--mode", "echo", "--direct",
        ])
        #expect(
            parsed.mcpServers == [
                MCPServerSpec(
                    name: "echo", command: Self.parsedCommand, arguments: ["--mode", "echo"])
            ])
        #expect(parsed.direct)
    }

    @Test("parsing --mcp two times reads two servers, in the order the options stand")
    func parseTwoMCPServers() throws {
        let parsed = try CLIRunner.parse([
            "--mcp", "first=\(Self.parsedCommand)", "--mcp", "second=\(Self.secondParsedCommand)",
        ])
        #expect(parsed.mcpServers.map(\.name) == ["first", "second"])
        #expect(parsed.mcpServers.map(\.command) == [Self.parsedCommand, Self.secondParsedCommand])
    }

    @Test("parsing --mcp with nothing after it throws")
    func parseMCPWithNoValueThrows() {
        #expect {
            try CLIRunner.parse(["--mcp"])
        } throws: { error in
            (error as? CLIMCPArgumentError) == .missingValue
        }
    }

    @Test("parsing a --mcp value that carries no equals sign throws")
    func parseMCPWithoutSeparatorThrows() {
        #expect {
            try CLIRunner.parse(["--mcp", "echo"])
        } throws: { error in
            (error as? CLIMCPArgumentError) == .missingSeparator("echo")
        }
    }

    @Test("parsing a --mcp value that names no server throws")
    func parseMCPWithEmptyNameThrows() {
        #expect {
            try CLIRunner.parse(["--mcp", "=\(Self.parsedCommand)"])
        } throws: { error in
            (error as? CLIMCPArgumentError) == .emptyName("=\(Self.parsedCommand)")
        }
    }

    @Test("parsing a --mcp value that names no command throws")
    func parseMCPWithEmptyCommandThrows() {
        #expect {
            try CLIRunner.parse(["--mcp", "echo="])
        } throws: { error in
            (error as? CLIMCPArgumentError) == .emptyCommand("echo=")
        }
    }

    @Test("the usage text lists the --mcp option with the value it reads")
    func usageTextListsTheMCPOption() {
        #expect(CLIRunner.usageText.contains("--mcp <name>=<command> [args...]"))
    }

    // MARK: - `run(...)`: --help exits 0 with usage text, no model touched

    @Test("run(...) with --help prints usage text and exits 0 without calling resolve")
    func runHelpExitsZero() async {
        let output = OutputCollector()
        let resolveCalls = CallCounter()
        let exitCode = await CLIRunner.run(
            arguments: ["--help"],
            resolve: { _, _, _ in
                resolveCalls.increment()
                throw CLIArgumentTestsError.shouldNotBeCalled
            },
            output: output.append
        )

        #expect(exitCode == CLIRunner.ExitCode.success)
        #expect(resolveCalls.count == 0)
        #expect(output.lines.contains { $0.contains("USAGE:") })
    }

    // MARK: - `run(...)`: an unknown flag exits nonzero with usage text, no model touched

    @Test("run(...) with an unknown flag prints the error and usage, and exits nonzero without calling resolve")
    func runUnknownFlagExitsNonzero() async {
        let output = OutputCollector()
        let resolveCalls = CallCounter()
        let exitCode = await CLIRunner.run(
            arguments: ["--bogus"],
            resolve: { _, _, _ in
                resolveCalls.increment()
                throw CLIArgumentTestsError.shouldNotBeCalled
            },
            output: output.append
        )

        #expect(exitCode == CLIRunner.ExitCode.usageError)
        #expect(exitCode != 0)
        #expect(resolveCalls.count == 0)
        #expect(output.lines.contains { $0.contains("unknown argument \"--bogus\"") })
        #expect(output.lines.contains { $0.contains("USAGE:") })
    }

    // MARK: - `run(...)`: a failing resolver degrades gracefully

    @Test("run(...) with an injected failing resolver exits nonzero with the documented message")
    func runFailingResolverExitsNonzero() async {
        let output = OutputCollector()
        let exitCode = await CLIRunner.run(
            arguments: [],
            resolve: { _, _, _ in
                throw CLIArgumentTestsError.injectedResolveFailure
            },
            output: output.append
        )

        #expect(exitCode == CLIRunner.ExitCode.unavailable)
        #expect(exitCode != 0)
        #expect(output.lines.contains { $0.contains("could not resolve a model via the Router") })
        #expect(output.lines.contains { $0.contains("Router's live inference path is not available") })
    }

    @Test("run(...) with an injected failing resolver in --direct mode also exits nonzero with the documented message")
    func runFailingResolverDirectModeExitsNonzero() async {
        let output = OutputCollector()
        let exitCode = await CLIRunner.run(
            arguments: ["--direct"],
            resolve: { _, _, _ in
                throw CLIArgumentTestsError.injectedResolveFailure
            },
            output: output.append
        )

        #expect(exitCode == CLIRunner.ExitCode.unavailable)
        #expect(output.lines.contains { $0.contains("could not resolve a model via the Router") })
    }

    // MARK: - `run(...)`: a bad `--mcp` value exits with the usage error

    @Test("run(...) with a --mcp value that carries no equals sign exits with the usage error and never resolves")
    func runBadMCPValueExitsUsageError() async {
        let output = OutputCollector()
        let resolveCalls = CallCounter()
        let exitCode = await CLIRunner.run(
            arguments: ["--mcp", "echo"],
            resolve: { _, _, _ in
                resolveCalls.increment()
                throw CLIArgumentTestsError.shouldNotBeCalled
            },
            output: output.append
        )

        #expect(exitCode == CLIRunner.ExitCode.usageError)
        #expect(resolveCalls.count == 0)
        #expect(output.lines.contains { $0.contains("carries no") })
    }

    @Test("run(...) with a --mcp command that does not start exits with the usage error on one line, and never resolves")
    func runMCPCommandThatDoesNotStartExitsUsageError() async {
        let output = OutputCollector()
        let resolveCalls = CallCounter()
        let exitCode = await CLIRunner.run(
            arguments: ["--mcp", "\(Self.mcpServerNoun)=\(Self.absentCommand)"],
            resolve: { _, _, _ in
                resolveCalls.increment()
                throw CLIArgumentTestsError.shouldNotBeCalled
            },
            output: output.append
        )

        #expect(exitCode == CLIRunner.ExitCode.usageError)
        #expect(resolveCalls.count == 0)
        let reported = output.lines.filter { $0.contains("did not start") }
        #expect(reported.count == Self.oneLine, "output was: \(output.lines)")
    }

    // MARK: - `--mcp`: the server, its verbs, and its shutdown

    /// The noun the attached server claims — the `<name>` of the `--mcp` value.
    private static let mcpServerNoun = "echo"

    /// A command no file stands at, so the spawn fails at once.
    private static let absentCommand = "/nonexistent/mcp-test-server"

    /// How many lines report one server that did not start.
    private static let oneLine = 1

    /// The text the echo verb is asked to send back.
    private static let echoedText = "the multitool-cli demo"

    /// The rendered call path of the echo verb of the attached server.
    private static let echoPath = "\(mcpServerNoun).\(ScriptedServer.echoToolName)"

    /// Builds the registry of a `--direct` demo run that attaches one
    /// `mcp-test-server` in echo mode, exactly as `run(...)` builds it.
    ///
    /// - Returns: the built registry, its servers and its pool.
    /// - Throws: what the locator or `CLIRunner.makeDemoRegistry(direct:mcpServers:)` throws.
    private static func makeEchoDemo() async throws -> CLIRunner.DemoRegistry {
        try await CLIRunner.makeDemoRegistry(
            direct: true,
            mcpServers: [
                MCPServerSpec(
                    name: mcpServerNoun,
                    command: TestServerLocator.executableURL().path,
                    arguments: [ServerMode.flagName, ServerMode.echo.rawValue])
            ])
    }

    @Test("the surface listing names every verb of the attached server")
    func mcpServerVerbsReachTheSurfaceListing() async throws {
        let demo = try await Self.makeEchoDemo()
        let output = OutputCollector()

        CLIRunner.reportSurface(demo.registry.surface, output: output.append)

        #expect(output.lines.contains("  tools.\(Self.echoPath)"), "listing was: \(output.lines)")
        await demo.pool.shutdownAll()
    }

    @Test("a direct-mode snippet calls a verb of the attached server and reads its answer")
    func directModeSnippetCallsTheAttachedServer() async throws {
        let demo = try await Self.makeEchoDemo()

        let rendered = try await MultiTool(registry: demo.registry).call(
            arguments: RunCodeArguments(
                code:
                    "return await tools.\(Self.echoPath)({ \(ScriptedServer.echoTextArgument): \"\(Self.echoedText)\" });"
            ))
        let answer = try JSONDecoder().decode(String.self, from: Data(rendered.utf8))

        #expect(answer == Self.echoedText)
        await demo.pool.shutdownAll()
    }

    @Test("the shutdown that follows the run leaves no server subprocess behind")
    func shutdownLeavesNoServerSubprocess() async throws {
        let demo = try await Self.makeEchoDemo()
        let process = try #require(demo.servers.first?.process)
        let pid = try #require(process.currentPid)
        #expect(ProcessRegistry.global.registeredPids.contains(pid))

        await demo.pool.shutdownAll()

        #expect(ProcessLiveness.isGone(pid))
        #expect(!ProcessRegistry.global.registeredPids.contains(pid))
    }
}

// MARK: - Fixtures

/// Errors this test file's scripted resolvers throw.
private enum CLIArgumentTestsError: Error, Equatable {
    /// Thrown by a resolver a test expects `CLIRunner.run(...)` to never
    /// actually call (e.g. the `--help` / unknown-flag paths, which return
    /// before model resolution).
    case shouldNotBeCalled
    /// The scripted failure `runFailingResolverExitsNonzero` injects to
    /// exercise the Router-unavailable degrade path.
    case injectedResolveFailure
}

/// A thread-safe collector for the lines `CLIRunner.run(...)`'s injectable
/// `output` closure writes — lets a test assert on what was printed without
/// touching real stdout. `final class ... Sendable` for the same reason as
/// this test target's other lock-boxed fixtures (e.g.
/// `Fixtures/AgentSessionFixtures.swift`'s `CallCounter`): `append` is
/// called from concurrent contexts (`CLIRunner`'s console-progress poller
/// runs on a background `Task` alongside the main call).
private final class OutputCollector: Sendable {
    /// Every line appended so far, in append order.
    private let linesBox = OSAllocatedUnfairLock<[String]>(initialState: [])

    /// Creates an empty collector.
    init() {}

    /// Every line appended so far, in append order.
    var lines: [String] { linesBox.withLock { $0 } }

    /// Appends one line — `CLIRunner.run(...)`'s `output` parameter.
    ///
    /// - Parameter line: the line to record.
    func append(_ line: String) {
        linesBox.withLock { $0.append(line) }
    }
}

// `CallCounter` (a thread-safe call counter) is reused as-is from
// `Fixtures/AgentSessionFixtures.swift` — it's `internal`, already visible
// throughout this test target, so this file doesn't redeclare it.
