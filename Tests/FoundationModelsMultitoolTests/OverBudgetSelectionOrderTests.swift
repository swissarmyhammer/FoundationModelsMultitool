import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import MCPTestServer
import Testing
import os

@testable import FoundationModelsMultitool

/// Coverage for what `searchTools` answers when the catalog stands above
/// `SelectionConfig.defaultCapacityCharacterLimit`, where `SelectionTier`
/// stops prompting once over the whole catalog and splits it into slices.
///
/// **The surface is real and the budget is untouched.** The suite mounts the
/// files and shell capabilities and four connected MCP servers of ten verbs
/// each — the shape a host builds when it connects an issue tracker, a
/// database, an observability stack and a delivery pipeline. That catalog
/// assembles a prefix above the shipped budget on its own. Nothing here
/// lowers the budget: a test that lowered it would measure the test.
///
/// **The model is scripted, and the slicing is not.** The selection tier is
/// driven through a `.factory` session source that answers each slice from
/// the ids of that slice, so the slice count, the slice contents and the
/// merge order are the tier's own work over the real prefix, while the
/// answer is deterministic and costs no GPU. The live half of this ground —
/// a real model over the same size of surface — is
/// `OverBudgetSurfaceDiscoveryTests` in the gated `IntegrationTests`
/// package.
///
/// The order rule the second test holds is written on
/// `SearchToolsTool.format(task:matches:sample:)`, which is the function
/// that splices the blocks in that order.
@Suite("OverBudgetSelectionOrderTests", .serialized)
struct OverBudgetSelectionOrderTests {

    // MARK: - Shared test constants

    /// Owns the temporary directories this test makes, so they go away when
    /// the test ends and they do not collect in `$TMPDIR`.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test, so a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "over-budget-selection-tests"

    /// The name of the shell store directory inside the session root.
    private static let shellStoreDirectoryName = ".shell"

    /// The heading that opens one candidate entry of an assembled prefix,
    /// with its trailing space — `SelectionTier` renders every candidate as
    /// `## <id>` above that id's summary block, so a prompt's own slice is
    /// readable off its instructions and off nothing else.
    private static let candidateHeadingPrefix = "## "

    /// The banner line every spliced catalog block opens with, up to the
    /// path — `APISurface.Entry.summaryBlock` and `block` both open with
    /// `// tools.<path>`, so the order the result hands the model is
    /// readable off the banner lines.
    private static let catalogBannerPrefix = "// tools."

    /// The task text every search of this suite passes.
    ///
    /// The scripted model answers from the slice it is given and never from
    /// the task, so one task serves every case and no case implies that its
    /// text decided the answer.
    private static let searchTask = "find the verb for this task"

    // MARK: - The over-budget surface

    @Test("the surface four connected platform servers build stands above the budget, and every entry reaches exactly one slice")
    func theSurfaceIsAboveTheBudgetAndEveryEntryReachesOneSlice() async throws {
        let mounted = try await makeOverBudgetSurface()
        let entries = mounted.registry.surface.entries
        let prefix = SelectionTier.assemblePrefix(
            preamble: .selectionDefault, catalog: MetadataIndex(items: entries))

        // Built in one piece because `#expect` takes a `Comment`, which a
        // concatenation of string literals is not.
        let size = "\(entries.count) entries assemble \(prefix.count) characters"
        let budget = "the budget is \(SelectionConfig.defaultCapacityCharacterLimit)"
        #expect(
            prefix.count > SelectionConfig.defaultCapacityCharacterLimit,
            "\(size), and \(budget): this suite would then measure the under-budget path"
        )

        let recorder = SliceRecorder()
        _ = try await Self.search(
            over: mounted.registry, recorder: recorder, answering: { _ in [] })

        #expect(recorder.slices.count > 1)
        // Every id, in catalog order, in exactly one slice: the tier splits
        // the catalog and never cuts it.
        #expect(recorder.slices.flatMap { $0 } == entries.map(\.path))
        withExtendedLifetime(mounted.servers) {}
    }

    // MARK: - The order rule

    @Test("matches from more than one slice are spliced in slice order, and in the model's order inside each slice")
    func matchesAreSplicedInSliceOrderThenModelOrder() async throws {
        let mounted = try await makeOverBudgetSurface()
        let recorder = SliceRecorder()

        // Each slice answers its own last id before its own first id. A
        // score cannot tell those apart — every slice's first pick scores
        // `1 / 1` — so an implementation that ordered by score could not
        // produce this sequence, and one that ordered by catalog position
        // could not either.
        let feedback = try await Self.search(
            over: mounted.registry, recorder: recorder,
            answering: { ids in [ids.last, ids.first].compactMap { $0 } })

        let expected = recorder.slices.flatMap { slice in [slice.last, slice.first].compactMap { $0 } }
        #expect(recorder.slices.count > 1, "the answer must span more than one slice for this to hold anything")
        #expect(Self.catalogPaths(in: feedback) == expected)
        withExtendedLifetime(mounted.servers) {}
    }

    @Test("an id the model answers twice is spliced one time")
    func aRepeatedIdIsSplicedOneTime() async throws {
        let mounted = try await makeOverBudgetSurface()
        let recorder = SliceRecorder()

        let feedback = try await Self.search(
            over: mounted.registry, recorder: recorder,
            answering: { ids in [ids.first, ids.first].compactMap { $0 } })

        let paths = Self.catalogPaths(in: feedback)
        #expect(paths == recorder.slices.compactMap(\.first))
        #expect(Set(paths).count == paths.count)
        withExtendedLifetime(mounted.servers) {}
    }

    @Test("the merged answer of every slice is cut to the limit the call asked for")
    func theMergedAnswerObeysTheLimit() async throws {
        let mounted = try await makeOverBudgetSurface()
        let recorder = SliceRecorder()

        let feedback = try await Self.search(
            over: mounted.registry, recorder: recorder, limit: Self.oneMatchLimit,
            answering: { ids in ids })

        #expect(Self.catalogPaths(in: feedback).count == Self.oneMatchLimit)
        withExtendedLifetime(mounted.servers) {}
    }

    /// The limit the cut-to-limit case asks for: one match, against a
    /// scripted answer of every candidate in every slice.
    private static let oneMatchLimit = 1

    // MARK: - The ground of one test

    /// A registry over the large surface, beside the scripted servers behind
    /// it, which the caller keeps alive for the length of its test.
    private struct MountedSurface {
        /// The built registry, whose surface the searcher indexes.
        let registry: MultiTool.Registry

        /// The scripted servers the registry's MCP verbs are served by.
        let servers: [ScriptedServer]
    }

    /// Mounts the large surface: the files and shell capabilities of a host,
    /// plus one connected MCP server for each ``LargeCatalogDomain``.
    ///
    /// The production mount, never a reimplementation of its wiring — the
    /// same `MultiTool.Builder` chain a host writes. The gated
    /// `OverBudgetSurfaceDiscoveryTests` builds the same shape in the nested
    /// `IntegrationTests` package: a package cannot import another package's
    /// test target, so the shared half is the verbs, which live in the
    /// `MCPTestServer` product both targets link.
    ///
    /// - Returns: the registry and the servers behind it.
    /// - Throws: what the connect, the capability mounts or `buildRegistry()`
    ///   throws.
    private func makeOverBudgetSurface() async throws -> MountedSurface {
        let root = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        var scriptedServers: [ScriptedServer] = []
        var connectedServers: [MCPServer] = []
        for domain in LargeCatalogDomain.allCases {
            let scripted = ScriptedServer(name: domain.serverName)
            await scripted.addLargeCatalogTools(of: domain)
            let connected = MCPServer(name: domain.serverName)
            try await connected.connect(via: scripted.startOnInMemoryPair())
            scriptedServers.append(scripted)
            connectedServers.append(connected)
        }
        let registry = try await MultiTool.Builder()
            .withFiles(root: root, readOnly: false)
            .withShell(storeDirectory: root.appendingPathComponent(Self.shellStoreDirectoryName, isDirectory: true))
            .withMCP(servers: connectedServers)
            .buildRegistry()
        return MountedSurface(registry: registry, servers: scriptedServers)
    }

    /// Runs one `searchTools` call over `registry` through a selection tier
    /// whose model answers each slice from the ids of that slice.
    ///
    /// - Parameters:
    ///   - registry: the catalog to search.
    ///   - recorder: records the ids of each slice the tier prompted.
    ///   - limit: the maximum number of matches to ask for. Defaults to
    ///     `nil`, which asks for every entry of the surface, so nothing the
    ///     tier answered is cut.
    ///   - answer: the ids one slice's model answers, given that slice's ids.
    /// - Returns: the text the call answered.
    /// - Throws: what the search throws.
    private static func search(
        over registry: MultiTool.Registry,
        recorder: SliceRecorder,
        limit: Int? = nil,
        answering answer: @escaping @Sendable ([String]) -> [String]
    ) async throws -> String {
        let entries = registry.surface.entries
        let searcher = MetadataSearcher(
            items: entries,
            mode: .auto,
            selection: SelectionConfig(model: { instructions in
                let ids = candidateIDs(in: instructions)
                recorder.record(slice: ids)
                return ScriptedAgentSession([selectionReply(ids: answer(ids))])
            })
        )
        let tool = SearchToolsTool(searcher: searcher, limit: limit ?? entries.count)
        return try await tool.call(arguments: SearchToolsArguments(task: searchTask))
    }

    /// The candidate ids of one assembled prefix, in the order the prefix
    /// renders them — the slice one prompt was given.
    ///
    /// - Parameter instructions: the prefix the tier seeded a session with.
    /// - Returns: the ids under the prefix's candidate headings.
    private static func candidateIDs(in instructions: String) -> [String] {
        instructions
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.hasPrefix(candidateHeadingPrefix) }
            .map { String($0.dropFirst(candidateHeadingPrefix.count)) }
    }

    /// The guided-generation answer of one scripted selection call.
    ///
    /// - Parameter ids: the ids the model answers, in its own order.
    /// - Returns: the raw `Selection` JSON text.
    private static func selectionReply(ids: [String]) -> String {
        let quoted = ids.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"ids\":[\(quoted)]}"
    }

    /// The catalog paths a `searchTools` result handed the model, in the
    /// order the result lists them — one for each spliced block's banner
    /// line.
    ///
    /// - Parameter feedback: the text `SearchToolsTool.call(arguments:)`
    ///   answered.
    /// - Returns: the `tools.*` paths of the matched entries, without the
    ///   `tools.` prefix.
    private static func catalogPaths(in feedback: String) -> [String] {
        feedback
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.hasPrefix(catalogBannerPrefix) }
            .map { String($0.dropFirst(catalogBannerPrefix.count)) }
    }
}

/// Records the ids of each slice an over-budget selection prompted, in
/// prompt order.
///
/// The tier makes one session per slice and seeds it with that slice's
/// prefix, so the factory closure sees each slice as it is prompted. The
/// closure runs inside the tier's actor and the test reads the record after
/// the call returns, so the state stands behind a lock — the pattern
/// `ScriptedAgentSession` uses for the same reason.
final class SliceRecorder: Sendable {
    /// The ids of each prompted slice, in prompt order.
    private let slicesBox = OSAllocatedUnfairLock<[[String]]>(initialState: [])

    /// Creates a recorder with no slices recorded.
    init() {}

    /// The ids of each prompted slice, in prompt order.
    var slices: [[String]] { slicesBox.withLock { $0 } }

    /// Records one prompted slice.
    ///
    /// - Parameter ids: the candidate ids that slice's prefix carried.
    func record(slice ids: [String]) {
        slicesBox.withLock { $0.append(ids) }
    }
}
