import Testing
import os

import FoundationModelsRouter

@testable import multitool_cli

/// M9 coverage for `CLIRunner`: argument parsing and the Router-unavailable
/// degrade path, both exercised with **no model at all** — plan.md M9's
/// ungated acceptance criteria ("Argument parsing... is unit-tested without
/// a model" / "Router-unavailable path... unit-tested via an injected
/// failing resolver"). The full live run (a real Router resolve, the agent
/// loop, the findAPIs-then-runCode trace) is exercised separately by the
/// gated `CLISmokeTests`.
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
/// `Fixtures/MultiToolAgentFixtures.swift`'s `CallCounter`): `append` is
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
// `Fixtures/MultiToolAgentFixtures.swift` — it's `internal`, already visible
// throughout this test target, so this file doesn't redeclare it.
