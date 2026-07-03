import Foundation
import Testing
import os

@testable import multitool_cli

/// M9's gated live smoke test — plan.md M9: "The live demo is verified by
/// an automated gated smoke test in the integration target (no human
/// eyeballing): it invokes the `CLIRunner` entry function under the env var
/// and asserts the emitted trace lines (findAPIs before runCode, final
/// answer non-empty)."
///
/// Runs `CLIRunner.run(...)` end to end with its default (production)
/// resolver — a real Router resolve against `CLIRunner.demoProfile`, a real
/// agent loop, and a real trace read back from the recorded transcript — and
/// asserts on the emitted output lines rather than a human reading console
/// output. `.enabled(if: multitoolIntegrationEnabled)` gates the whole
/// suite behind `MULTITOOL_INTEGRATION`, so it never fires on a
/// network/GPU-less box or in normal CI, mirroring every other gated
/// suite in this target.
@Suite("CLI smoke test (M9)", .enabled(if: multitoolIntegrationEnabled))
struct CLISmokeTests {
    @Test("the live demo's emitted trace shows findAPIs before runCode, and a non-empty final answer")
    func demoProducesSearchThenCodeTrace() async {
        let output = OutputCollector()

        let exitCode = await CLIRunner.run(arguments: [], output: output.append)

        #expect(
            exitCode == CLIRunner.ExitCode.success,
            "expected the live demo to succeed; output:\n\(output.lines.joined(separator: "\n"))"
        )

        let findAPIsIndex = output.lines.firstIndex { $0.contains("findAPIs(") }
        let runCodeIndex = output.lines.firstIndex { $0.contains("runCode(") }
        #expect(findAPIsIndex != nil, "expected a findAPIs(...) trace line in:\n\(output.lines.joined(separator: "\n"))")
        #expect(runCodeIndex != nil, "expected a runCode(...) trace line in:\n\(output.lines.joined(separator: "\n"))")
        if let findAPIsIndex, let runCodeIndex {
            #expect(findAPIsIndex < runCodeIndex, "expected findAPIs to precede runCode in the trace")
        }

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
