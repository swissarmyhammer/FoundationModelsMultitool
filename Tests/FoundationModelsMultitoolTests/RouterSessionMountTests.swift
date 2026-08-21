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
/// suspect, since it wraps every tool in `DetachingTool` before the model sees
/// it. These tests exist to keep that suspicion answered: the wrapper is
/// transparent, so a future regression there is caught here rather than in a
/// twenty-minute integration run.
@Suite("Router session mount")
struct RouterSessionMountTests {
    /// A sink that drops every event.
    ///
    /// The mount requires one; these tests assert on returned output, not on
    /// posted progress.
    private struct DiscardingSink: OperationEventSink {
        /// Drops `event`.
        ///
        /// - Parameter event: the event to discard.
        func post(event: OperationEvent) async {}
    }

    @Test("searchTools returns the same text through Router's session mount as it does direct")
    func searchToolsIsTransparentThroughTheMount() async throws {
        let registry = try Self.registry()
        let searchTools = try SearchToolsTool(registry: registry, librarian: nil)
        let task = "the cities on the trip"

        let direct = try await searchTools.call(arguments: SearchToolsArguments(task: task))
        let mounted = try #require(
            Self.sessionMounted(searchTools) as? any Tool<SearchToolsArguments, String>
        )
        let throughMount = try await mounted.call(arguments: SearchToolsArguments(task: task))

        #expect(throughMount == direct)
        #expect(!direct.isEmpty)
    }

    @Test("the mount returns a token where a direct call returns the value")
    func runCodeBackgroundsThroughTheMount() async throws {
        let registry = try Self.registry()
        let runCode = MultiTool(registry: registry)
        let snippet = "const r = await tools.getCities({}); return r.cities.length;"

        let direct = try await runCode.call(arguments: RunCodeArguments(code: snippet))
        let mounted = try #require(
            Self.sessionMounted(runCode) as? any Tool<RunCodeArguments, String>
        )
        let throughMount = try await mounted.call(arguments: RunCodeArguments(code: snippet))

        // Transparency through the mount can never hold again, and this is the
        // rule that replaced it: mounted, `runCode` always backgrounds and
        // always hands back a completion token, whatever the mount's own wait
        // clock says (task ^cv98vff). It is the stronger claim — it defines the
        // mount, where the old one only said the mount changed nothing.
        #expect(PendingRunEnvelope.isRendered(text: throughMount))
        #expect(throughMount != direct)
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

    @Test("the mount leaves the model-facing name and description untouched")
    func theMountPreservesTheModelFacingSurface() async throws {
        let registry = try Self.registry()
        let searchTools = try SearchToolsTool(registry: registry, librarian: nil)

        let mounted = Self.sessionMounted(searchTools)

        #expect(mounted.name == searchTools.name)
        #expect(mounted.description == searchTools.description)
    }

    @Test("a snippet that waits on a pending run hands back an envelope that leads to the wait tool, not to another snippet")
    func runCodeEnvelopeLeadsToTheWaitTool() async throws {
        // The live-lock of task ^4qcf1v9: every mounted `runCode` call
        // backgrounds, so a snippet that waits on a pending token is itself
        // parked and hands back a fresh token. An envelope whose `next` told the
        // model to run another snippet made the model chase tokens, one
        // generation a round, until it used the `wait` tool. The envelope's
        // `next` is this package's own sentence, and it must name the `wait`
        // tool and never a snippet.
        let registry = try Self.registry()
        let mailbox = SessionMailbox()
        let pendingRun = try await startScriptedRun(in: mailbox)
        let runCode = MultiTool(registry: registry)
        let mounted = try #require(
            Self.sessionMounted(runCode, mailbox: mailbox) as? any Tool<RunCodeArguments, String>
        )

        let rendered = try await mounted.call(
            arguments: RunCodeArguments(code: "return await wait(\"\(pendingRun.completionToken)\", 60);")
        )

        #expect(PendingRunEnvelope.isRendered(text: rendered))
        let envelope = try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(rendered.utf8))
        #expect(envelope.next == runCode.detachmentCollectInstruction(forCompletionToken: envelope.completionToken))
        // The sentence leads to the top-level `wait` tool with this envelope's
        // token, and it names the wait tool's own report values.
        #expect(envelope.next.contains("wait tool"))
        #expect(envelope.next.contains(envelope.completionToken))
        #expect(envelope.next.contains("\"\(RunState.complete)\""))
        #expect(envelope.next.contains("\"\(CallResult.timeout)\""))
        // It prescribes no snippet and never names the parked tool itself.
        #expect(!envelope.next.contains("runCode"))
        #expect(!envelope.next.contains("Call this tool again"))
        #expect(!envelope.next.contains("return await wait"))
        #expect(rendered.count < ToolContext.terminalDetailTailLimit)

        // Release the run the snippet waits on; the parked snippet then
        // finishes, and the token the envelope names resolves to a result.
        await settle(pendingRun, in: mailbox)
        let collected = await backgroundRuns(over: mailbox)
            .wait(completionToken: envelope.completionToken, seconds: scriptedRunSettlementSeconds)
        guard case .settled = collected else {
            Issue.record("the parked snippet never settled: \(collected)")
            return
        }
    }

    // MARK: - Fixtures

    /// A registry carrying one real tool.
    private static func registry() throws -> MultiTool.Registry {
        try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
    }

    /// Wraps `tool` the way a Router session wraps every tool it mounts.
    ///
    /// `DetachConfiguration.nativeSessionMount` is the one configuration
    /// `RoutedModel.makeSession` applies, so this is the same composition the
    /// integration scenarios run through.
    ///
    /// - Parameters:
    ///   - tool: the tool to mount.
    ///   - mailbox: the session mailbox the mount parks runs in; a fresh one
    ///     when the test holds no background run of its own.
    /// - Returns: the composed, model-facing tool.
    private static func sessionMounted(_ tool: any Tool, mailbox: SessionMailbox = SessionMailbox()) -> any Tool {
        ToolDetachment.wrapping(
            tool: tool,
            sessionID: ULID(),
            mailbox: mailbox,
            sink: DiscardingSink(),
            configuration: .nativeSessionMount
        )
    }
}
