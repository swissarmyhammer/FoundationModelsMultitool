import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsMultitool

/// Coverage for `FindAPITool` (task 2rtcrhc's rewire onto `MetadataSearcher`
/// `.selection` mode): the splice-through and empty-result behaviors
/// `LibrarianTests` previously covered against `FindAPITool(librarian:)`,
/// now driven against a real `.selection`-mode `MetadataSearcher` scripted
/// through the internal `AgentSession` seam
/// (`Fixtures/LibrarianFixtures.swift`'s `RootSessionRespondCalledDirectlySession`,
/// reusing `MultiToolAgentTests`' zero-GPU pattern) — the searcher's
/// selection tier does the real cached-root/`fork()`-per-call work, and
/// `FindAPITool` splices its resolved `Match`es' verbatim `block`s, never a
/// bare unqualified `declaration`/`doc`.
@Suite("FindAPITool")
struct FindAPIToolTests {
    @Test("a scripted selection's matched standalone entry splices FindAPITool's output verbatim, via a fork() of the prefix-rooted session")
    func standaloneSelectionSplicesVerbatimBlockAndExample() async throws {
        let surface = try MultiTool.Builder().addTool(TripCitiesTool()).build()
        let entry = try #require(surface.entries.first)
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [#"{"ids":["tripCities"]}"#])
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .selection,
            selection: SelectionConfig(model: { _ in root }, capacityCharacterLimit: .max)
        )
        let findAPITool = FindAPITool(searcher: searcher, limit: surface.entries.count)

        let feedback = try await findAPITool.dispatch(task: "list the trip cities")

        #expect(root.forkCount == 1)
        #expect(feedback.contains("findAPIs(\"list the trip cities\") found:"))
        // The verbatim block — banner plus doc/declaration — and its example
        // both land unmodified, never re-derived.
        #expect(feedback.contains(entry.block))
        #expect(feedback.contains("Example: \(entry.descriptor.example)"))
    }

    @Test("a grouped tool's selected match splices its qualified tools.<group>.<name> banner verbatim")
    func groupedSelectionSplicesQualifiedPath() async throws {
        let surface = try MultiTool.Builder()
            .addGroup(named: "github", [GithubCreateIssueTool()])
            .build()
        let entry = try #require(surface.entries.first)
        #expect(entry.path == "github.createIssue")
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [#"{"ids":["github.createIssue"]}"#])
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .selection,
            selection: SelectionConfig(model: { _ in root }, capacityCharacterLimit: .max)
        )
        let findAPITool = FindAPITool(searcher: searcher, limit: surface.entries.count)

        let feedback = try await findAPITool.dispatch(task: "file a github issue")

        // The qualified `// tools.github.createIssue` banner — never the bare
        // `declare function createIssue(...)` alone — proves the namespace
        // survives the splice.
        #expect(feedback.contains("// tools.github.createIssue"))
        #expect(feedback.contains(entry.block))
    }

    @Test("an empty selection formats as a clear \"no matching functions\" message, not an empty string")
    func emptySelectionFormatsAsNoMatchMessage() async throws {
        let surface = try MultiTool.Builder().addTool(TripCitiesTool()).build()
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [#"{"ids":[]}"#])
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .selection,
            selection: SelectionConfig(model: { _ in root }, capacityCharacterLimit: .max)
        )
        let findAPITool = FindAPITool(searcher: searcher, limit: surface.entries.count)

        let feedback = try await findAPITool.dispatch(task: "something no tool does")

        #expect(feedback == "findAPIs(\"something no tool does\") found no matching functions.")
    }
}
