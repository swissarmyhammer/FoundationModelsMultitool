import Foundation
import FoundationModels
import Testing

import FoundationModelsMultitool

/// The bare-session scenario: the shell verbs mounted on a plain
/// `LanguageModelSession` with no Router at all.
///
/// With no ambient `ToolContext`, `Execute` mints its own `commandID`, runs
/// the command to completion and answers with the report; the model then
/// reads the output out of that report and repeats it. `runBareSessionScenario`
/// carries the model guard, the session, and the assertion; this suite
/// supplies the tools and the prompt.
///
/// Serialized exactly like the other gated suites, and unreachable from the
/// root `swift test`, which declares no target for this nested
/// `IntegrationTests` package.
@Suite(
    "A shell command on a bare LanguageModelSession",
    .serialized,
    .timeLimit(.minutes(bareSessionTimeLimitMinutes))
)
struct ShellBareSessionTests {

    @Test("execute runs to completion on a bare session, and the answer carries the output")
    func executeRunsToCompletionOnABareSession() async throws {
        let capability = try ShellCapability(storeDirectory: LiveRouterFixture.makeTempDir())

        try await runBareSessionScenario(
            named: bareSessionScenarioName,
            tools: capability.tools,
            prompt: bareSessionPrompt,
            marker: bareSessionMarker)
    }
}

/// The label the printed result and skip lines carry.
private let bareSessionScenarioName = "bareSessionShellCommand"

/// The text the command writes, and the text the answer must carry.
private let bareSessionMarker = "bare"

/// The command the model is asked to run.
private let bareSessionCommand = "echo \(bareSessionMarker)"

/// The request the model is given.
///
/// It names the command and asks for its output word for word, so an answer
/// that carries the marker is one the tool's report supplied.
private let bareSessionPrompt =
    "Use the execute tool to run the shell command \(bareSessionCommand), then reply with "
    + "exactly the text the command printed."
