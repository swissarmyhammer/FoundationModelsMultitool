import Foundation
import MCPTestServer
import Testing
import os

import MultitoolCLI

/// The gated live smoke test for the canonical Router + `RoutedSession` +
/// `MultiTool` example: it invokes the `CLIRunner` entry function against a
/// real model and asserts a non-empty final answer.
///
/// Runs `CLIRunner.run(...)` end to end with its default (production)
/// resolver — a real Router resolve against `CLIRunner.demoProfile`, the
/// vended tools mounted on a `RoutedSession` over `profile.standard`, and one
/// turn drained through `streamEvents(to:)` — and asserts on the emitted
/// output lines rather than a human reading console output. This is the
/// shipped host contract, so the run exercises the mounted background path
/// rather than a bare session that cannot background. Unlike the retired
/// `MultiToolAgent`-based demo this replaces, there is no hand-rolled turn
/// trace to assert on: `runDemo` prints the tool calls it made and the final
/// answer, so this only asserts that the answer is present and non-empty.
///
/// A deeper, scenario-level port of this suite (prefix reuse,
/// selection accuracy, multi-tool-call composition) is the dedicated
/// gated-suite migration task's job — see that task for the broader port.
/// The whole suite sits in the nested `IntegrationTests` package, which the
/// root manifest declares no target for, so it never fires on a network/GPU-less
/// box or in normal CI. It runs under
/// `swift test --package-path IntegrationTests --no-parallel`, like every other
/// suite in this target.
@Suite("CLI smoke test", .serialized, .timeLimit(.minutes(30)))
struct CLISmokeTests {
    /// The prefix the demo writes the model's answer under.
    private static let answerPrefix = "Answer: "

    /// The name of the stdio MCP server executable the ROOT package builds.
    private static let testServerName = "mcp-test-server"

    /// The noun the attached server claims in the `--mcp` case below.
    private static let mcpServerNoun = "echo"

    @Test("the live demo succeeds and prints a non-empty final answer")
    func demoProducesNonEmptyAnswer() async {
        let run = await Self.runDemo(arguments: [])

        Self.expectSuccess(of: run)
        Self.expectNonEmptyAnswer(in: run.lines)
    }

    @Test("the live demo attaches a stdio MCP server, lists its verbs, and still answers")
    func demoAttachesAnMCPServer() async throws {
        let command = try Self.testServerPath()

        let run = await Self.runDemo(arguments: [
            "--mcp", "\(Self.mcpServerNoun)=\(command)", ServerMode.flagName,
            ServerMode.echo.rawValue,
        ])

        Self.expectSuccess(of: run)
        let verb = "tools.\(Self.mcpServerNoun).\(ScriptedServer.echoToolName)"
        #expect(
            run.lines.contains { $0.hasSuffix(verb) },
            "expected the surface listing to name \(verb); output:\n\(run.lines.joined(separator: "\n"))"
        )
        Self.expectNonEmptyAnswer(in: run.lines)
    }

    // MARK: - One live run

    /// Runs the demo with `arguments` against a real model, and collects every
    /// line it wrote.
    ///
    /// - Parameter arguments: the command-line arguments of the run.
    /// - Returns: the exit code, and every line the run wrote.
    private static func runDemo(arguments: [String]) async -> (exitCode: Int32, lines: [String]) {
        // `swift test`'s binary layout defeats mlx-swift's default metallib
        // lookup (see `MetalLibraryTestBootstrap`'s documentation) — must run
        // before `CLIRunner.run(...)` resolves a live model.
        _ = MetalLibraryTestBootstrap.ensureColocatedMetallib
        let output = OutputCollector()

        // This suite resolves its own profile through `CLIRunner`, not
        // `LiveRouterFixture`, so it takes the target's one-resident-profile
        // turnstile itself — otherwise it would generate alongside whichever
        // scenario suite Swift Testing is running in parallel with it, which
        // measurably destroys grounding (see `LiveProfileTurnstile`).
        await LiveProfileTurnstile.shared.enter()
        let exitCode = await CLIRunner.run(arguments: arguments, output: output.append)
        await LiveProfileTurnstile.shared.leave()
        return (exitCode, output.lines)
    }

    /// Asserts that the run succeeded, and prints every line it wrote when it
    /// did not.
    ///
    /// - Parameter run: what ``runDemo(arguments:)`` answered.
    private static func expectSuccess(of run: (exitCode: Int32, lines: [String])) {
        #expect(
            run.exitCode == CLIRunner.ExitCode.success,
            "expected the live demo to succeed; output:\n\(run.lines.joined(separator: "\n"))"
        )
    }

    /// Asserts that `lines` carry one non-empty answer line.
    ///
    /// - Parameter lines: every line the run wrote.
    private static func expectNonEmptyAnswer(in lines: [String]) {
        let answerLine = lines.first { $0.hasPrefix(answerPrefix) }
        #expect(
            answerLine != nil,
            "expected an \"\(answerPrefix)...\" line in:\n\(lines.joined(separator: "\n"))")
        if let answerLine {
            let answer = answerLine.dropFirst(answerPrefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!answer.isEmpty, "expected a non-empty final answer")
        }
    }

    /// The path of the `mcp-test-server` executable the ROOT package builds.
    ///
    /// This nested package builds no executable of its own over `MCPTestServer`,
    /// and a test target can depend on no executable, so the binary stands in
    /// the products directory of the ROOT build rather than beside this test
    /// bundle. `#filePath` names this file inside the checkout, so four steps up
    /// reach the repository root, and the root build writes the product under
    /// `.build/debug`.
    ///
    /// - Returns: the path of the executable.
    /// - Throws: when no executable stands there, naming the command that
    ///   writes it.
    private static func testServerPath() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // FoundationModelsMultitoolIntegrationTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // IntegrationTests
            .deletingLastPathComponent()  // the repository root
        let candidate = repositoryRoot.appendingPathComponent(".build/debug/\(testServerName)")
        try #require(
            FileManager.default.isExecutableFile(atPath: candidate.path),
            """
            no \(testServerName) executable at \(candidate.path); run \
            `swift build --product \(testServerName)` at the repository root first.
            """)
        return candidate.path
    }
}

/// A thread-safe collector for the lines `CLIRunner.run(...)`'s injectable
/// `output` closure writes — mirrors
/// `Tests/FoundationModelsMultitoolTests/CLIArgumentTests.swift`'s
/// `OutputCollector`, redeclared here since that fixture lives in a
/// different test target.
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
