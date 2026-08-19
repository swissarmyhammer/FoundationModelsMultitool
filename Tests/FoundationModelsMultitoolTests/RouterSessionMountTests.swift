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
        // Called directly, with no session and no run plane to park in, the
        // same snippet still returns its own value. Both halves of one rule.
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
    /// - Parameter tool: the tool to mount.
    /// - Returns: the composed, model-facing tool.
    private static func sessionMounted(_ tool: any Tool) -> any Tool {
        ToolDetachment.wrapping(
            tool: tool,
            sessionID: ULID(),
            mailbox: SessionMailbox(),
            sink: DiscardingSink(),
            configuration: .nativeSessionMount
        )
    }
}
