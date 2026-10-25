import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing
import ULID

@testable import FoundationModelsMultitool

/// The MultiTool-to-Router boundary: a mounted tool must answer exactly as the
/// unmounted one does.
///
/// The integration scenarios score 0/4 on Router's session and 1/4-3/4 on a plain
/// `LanguageModelSession`, with the model reporting that it has no functions
/// at all (task `tkrdwb8`). Router's per-session tool wiring was the first
/// suspect, since it wraps every tool in `BackgroundToolRunner` or
/// `RunToCompletionRunner` before the model sees it. These tests exist to keep
/// that suspicion answered: the wrapper is transparent, so a future regression
/// there is caught here rather than in a twenty-minute integration run.
@Suite("Router session mount", .ownsTemporaryDirectories)
struct RouterSessionMountTests {
    @Test("searchTools returns the same text through Router's session mount as it does direct")
    func searchToolsIsTransparentThroughTheMount() async throws {
        try await withOuterRunContext { context in
            let registry = try Self.registry()
            let searchTools = try SearchToolsTool(registry: registry, selection: nil)
            let task = "the cities on the trip"

            let direct = try await searchTools.call(arguments: SearchToolsArguments(task: task))
            let mounted = try #require(
                Self.makeSessionMounted(searchTools, on: context) as? any Tool<SearchToolsArguments, String>
            )
            let throughMount = try await mounted.call(arguments: SearchToolsArguments(task: task))

            #expect(throughMount == direct)
            #expect(!direct.isEmpty)
        }
    }

    @Test("a short snippet returns the same value through the mount as it does direct")
    func runCodeIsTransparentThroughTheMountInsideTheSettlePeriod() async throws {
        try await withOuterRunContext { context in
            let registry = try Self.registry()
            let runCode = MultiTool(registry: registry)
            let snippet = "const r = await tools.getCities({}); return r.cities.length;"

            let direct = try await runCode.call(arguments: RunCodeArguments(code: snippet))
            let mounted = try #require(
                Self.makeSessionMounted(runCode, on: context) as? any Tool<RunCodeArguments, String>
            )
            let throughMount = try await mounted.call(arguments: RunCodeArguments(code: snippet))

            // Mounted, `runCode` is a background tool, but a background call goes
            // to the background only when it takes longer than its settle period
            // (the rule of the user). This snippet is over at once, so the mount
            // gives its own result, the same as the direct call, and no envelope.
            // A snippet that runs longer gets a pending envelope: see
            // `runCodeEnvelopeCarriesTheSharedPendingText` below.
            #expect(!PendingRunEnvelope.isRendered(text: throughMount))
            #expect(throughMount == direct)
            // Called directly, with no session and no background runs to post into,
            // the same snippet still returns its own value. Both halves of one rule.
            //
            // A city count derived from the names the call returned shares no text
            // with them, so the run also closes with `ToolReturnLedger`'s notice —
            // the detector reporting the fact it reports, not noise this test
            // should assert around. The whole output is compared, and the notice is
            // read from its one source, so a reword reaches here too.
            #expect(direct == "3\n\n\(ToolReturnLedger.uncarriedReturnNotice)")
        }
    }

    @Test("the mount leaves the model-facing name and description untouched")
    func theMountPreservesTheModelFacingSurface() async throws {
        try await withOuterRunContext { context in
            let registry = try Self.registry()
            let searchTools = try SearchToolsTool(registry: registry, selection: nil)

            let mounted = Self.makeSessionMounted(searchTools, on: context)

            #expect(mounted.name == searchTools.name)
            #expect(mounted.description == searchTools.description)
        }
    }

    @Test("a snippet that is still running hands back an envelope that carries the shared pending text, not a call to a wait tool or another snippet")
    func runCodeEnvelopeCarriesTheSharedPendingText() async throws {
        // The live-lock of task ^4qcf1v9: every mounted `runCode` call
        // backgrounds, so a snippet that is still running is tracked and hands
        // back a token. An envelope whose `next` told the model to run another
        // snippet made the model chase tokens, one generation a round. A
        // settled run now comes back to the session as mail (Router
        // `generation-queue.md` §5.5), so the envelope's `next` carries the
        // shared pending text (task ^1dzf1za). It names no `wait` tool, because
        // no `wait` tool is mounted, and the sandbox has no `wait()` global.
        let gate = ReleaseGate()
        try await withOuterRunContext { context in
            // `ReleaseGate.wait()` does not end on cancellation, and `close()`
            // waits for each run body to end. Thus the gate opens on every path
            // before the session closes. A second release has no effect.
            try await ensuring({ await gate.release() }) {
                let runCode = MultiTool(
                    registry: try MultiTool.Builder().addTool(GatedCodeTool(gate: gate)).buildRegistry(),
                    configuration: MultiToolConfiguration(inlineSettleGrace: 0)
                )
                let mounted = try #require(
                    Self.makeSessionMounted(runCode, on: context) as? any Tool<RunCodeArguments, String>
                )

                let rendered = try await mounted.call(arguments: RunCodeArguments(code: gatedCodeSnippet))

                #expect(PendingRunEnvelope.isRendered(text: rendered))
                let envelope = try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(rendered.utf8))
                let described = CallDescription.of(verb: runCode.name, text: gatedCodeSnippet)
                #expect(
                    envelope.next
                        == PendingRunEnvelope.defaultCollectInstruction(
                            forCompletionToken: envelope.completionToken, describing: described))
                // The sentence names the snippet and this envelope's token,
                // and asks for a status. Its own words, the snippet aside,
                // name no `wait` tool.
                let words = envelope.next.replacingOccurrences(of: described, with: "")
                #expect(words.contains("Waiting on"))
                #expect(words.contains(envelope.completionToken))
                #expect(!words.contains("wait tool"))
                #expect(!words.localizedCaseInsensitiveContains("call the wait"))
                // It prescribes no snippet (task `^cf57dtd`).
                #expect(!words.contains("Call this tool again"))
                #expect(!words.contains("return await wait"))
                // The envelope is a short report: shorter than one capped `runCode`
                // return value.
                #expect(rendered.count < MultiToolConfiguration.default.returnValueCharacterLimit)

                // Open the gate the snippet waits on; the background snippet then
                // finishes, and the token the envelope names resolves to a result.
                await gate.release()
                let collected = await context
                    .wait(completionToken: envelope.completionToken, seconds: scriptedRunSettlementSeconds)
                guard case .settled = collected else {
                    Issue.record("the background snippet never settled: \(collected)")
                    return
                }
            }
        }
    }

    // MARK: - Fixtures

    /// A registry carrying one real tool.
    private static func registry() throws -> MultiTool.Registry {
        try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
    }

    /// Wraps `tool` the way a Router session wraps every tool it mounts.
    ///
    /// `ToolMount.synchronous` is the one configuration
    /// `RoutedModel.makeSession` applies, so this is the same composition the
    /// integration scenarios run through.
    ///
    /// - Parameters:
    ///   - tool: the tool to mount.
    ///   - context: the session context the mount tracks runs on.
    /// - Returns: the composed, model-facing tool.
    private static func makeSessionMounted(
        _ tool: any Tool, on context: ToolContext
    ) -> any Tool {
        context.mount(tool, as: .synchronous)
    }
}
