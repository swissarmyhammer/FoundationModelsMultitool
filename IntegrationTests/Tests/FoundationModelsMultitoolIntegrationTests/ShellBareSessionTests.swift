import Foundation
import FoundationModels
import Testing

import FoundationModelsMultitool

/// The bare-session scenario: the shell verbs mounted on a plain
/// `LanguageModelSession` with no Router at all.
///
/// The README's "Layering" section states the claim this suite proves: each
/// verb is a plain `FoundationModels.Tool`, so it works with `FoundationModels`
/// alone, and background is a property of the Router mount rather than of the
/// verb. With no ambient `ToolContext`, `Execute` mints its own `commandID`,
/// runs the command to completion and answers with the report; the model then
/// reads the output out of that report and repeats it.
///
/// The model is the on-device `SystemLanguageModel.default`, never a Router
/// profile: a resolved profile would put a `RoutedSession` in the path, and a
/// `RoutedSession` is exactly what this suite must not mount. The suite skips
/// with a note when that model is not available on this machine, the same way
/// every other gated runner skips when live inference is not wired.
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
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            print("SKIP [\(bareSessionScenarioName)] the system language model is not available")
            return
        }

        let capability = try ShellCapability(storeDirectory: LiveRouterFixture.makeTempDir())
        let session = LanguageModelSession(model: model, tools: capability.tools)

        // Explicitly typed to pin the native FoundationModels API, exactly as
        // the root package's `ExamplesTests` does.
        let response: LanguageModelSession.Response<String> = try await session.respond(
            to: bareSessionPrompt)

        print("RESULT [\(bareSessionScenarioName)] reply=\"\(response.content)\"")
        #expect(
            response.content.contains(bareSessionMarker),
            "expected the answer to carry \(bareSessionMarker), and it was: \(response.content)")
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

/// The time limit of the one test, in minutes.
///
/// THE LIMIT IS THE DETECTOR, exactly as it is in `BackgroundTests`. The whole
/// turn is one on-device tool call and one short reply, so a run that reaches
/// this limit is a hang rather than a slow pass. Five minutes stands far over
/// any healthy run and still reports a hang inside one CI job.
private let bareSessionTimeLimitMinutes = 5
