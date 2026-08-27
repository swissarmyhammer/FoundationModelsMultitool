import FoundationModels
import Testing

/// The time limit of one bare-session test, in minutes.
///
/// THE LIMIT IS THE DETECTOR, exactly as it is in `BackgroundTests`. The whole
/// turn is one on-device tool call and one short reply, so a run that reaches
/// this limit is a hang rather than a slow pass. Five minutes stands far over
/// any healthy run and still reports a hang inside one CI job.
let bareSessionTimeLimitMinutes = 5

/// Runs one bare-session scenario: a set of plain `FoundationModels.Tool`
/// values mounted on a `LanguageModelSession` with no Router at all.
///
/// The README's "Layering" section states the claim each caller proves: a
/// verb is a plain `Tool`, so it works with `FoundationModels` alone, and the
/// Router is a property of the mount rather than of the verb. Each
/// bare-session suite calls this one function, thus the model guard, the
/// session, the prompt, and the assertion are written one time.
///
/// The model is the on-device `SystemLanguageModel.default`, never a Router
/// profile: a resolved profile would put a `RoutedSession` in the path, and a
/// `RoutedSession` is exactly what a bare-session suite must not mount. The
/// scenario skips with a note when that model is not available on this
/// machine, the same way every other gated runner skips when live inference
/// is not wired.
///
/// - Parameters:
///   - scenarioName: the label the printed result and skip lines carry.
///   - tools: the plain tools to mount on the session.
///   - prompt: the request the model is given.
///   - marker: the text the answer must carry, which only a tool's report
///     supplies.
/// - Throws: whatever `LanguageModelSession.respond(to:)` throws.
func runBareSessionScenario(
    named scenarioName: String,
    tools: [any Tool],
    prompt: String,
    marker: String
) async throws {
    let model = SystemLanguageModel.default
    guard case .available = model.availability else {
        print("SKIP [\(scenarioName)] the system language model is not available")
        return
    }

    let session = LanguageModelSession(model: model, tools: tools)

    // Explicitly typed to pin the native FoundationModels API, exactly as
    // the root package's `ExamplesTests` does.
    let response: LanguageModelSession.Response<String> = try await session.respond(to: prompt)

    print("RESULT [\(scenarioName)] reply=\"\(response.content)\"")
    #expect(
        response.content.contains(marker),
        "expected the answer to carry \(marker), and it was: \(response.content)")
}
