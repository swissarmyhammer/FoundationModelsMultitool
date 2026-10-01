import FoundationModels
import Testing

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
/// After the reply, it writes one `TOOL` line for each tool call and each tool
/// output of the turn. These lines show the arguments the model gave and the
/// output it read, thus a wrong answer shows its cause in the log.
///
/// - Parameters:
///   - scenarioName: the label the printed result, tool, and skip lines carry.
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
        reportTraceLine("SKIP [\(scenarioName)] the system language model is not available")
        return
    }

    let session = LanguageModelSession(model: model, tools: tools)

    // Explicitly typed to pin the native FoundationModels API, exactly as
    // the root package's `ExamplesTests` does.
    let response: LanguageModelSession.Response<String> = try await session.respond(to: prompt)

    reportGatedResult(scenario: scenarioName, line: "reply=\"\(response.content)\"")
    for entry in response.transcriptEntries.filter(\.isToolEntry) {
        reportTraceLine("TOOL [\(scenarioName)] \(entry)")
    }
    #expect(
        response.content.contains(marker),
        "expected the answer to carry \(marker), and it was: \(response.content)")
}

extension Transcript.Entry {

    /// Whether this entry is a tool call or a tool output.
    ///
    /// A bare session has no Router, thus no recording holds its turn. The
    /// `TOOL` lines that `runBareSessionScenario` writes from these entries
    /// are the one record of the arguments the model gave and of the output
    /// the tool gave back. Without them, a wrong answer does not show if the
    /// model or the tool caused it.
    var isToolEntry: Bool {
        if case .toolCalls = self { return true }
        if case .toolOutput = self { return true }
        return false
    }
}
