import Foundation
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
/// shipped host contract, so the run exercises the mounted detachment path
/// rather than a bare session that cannot detach. Unlike the retired
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
    @Test("the live demo succeeds and prints a non-empty final answer")
    func demoProducesNonEmptyAnswer() async {
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
        let exitCode = await CLIRunner.run(arguments: [], output: output.append)
        await LiveProfileTurnstile.shared.leave()

        #expect(
            exitCode == CLIRunner.ExitCode.success,
            "expected the live demo to succeed; output:\n\(output.lines.joined(separator: "\n"))"
        )

        let answerLine = output.lines.first { $0.hasPrefix("Answer: ") }
        #expect(answerLine != nil, "expected an \"Answer: ...\" line in:\n\(output.lines.joined(separator: "\n"))")
        if let answerLine {
            let answer = answerLine.dropFirst("Answer: ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!answer.isEmpty, "expected a non-empty final answer")
        }
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
