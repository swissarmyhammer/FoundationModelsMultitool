import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsMultitool

/// Coverage for `FindAPIsTool` (task 4aveepp's extraction: `findAPIs` as a
/// standalone `FoundationModels.Tool` conformer, decoupled from the retired
/// `MultiToolAgent` loop and its turn machinery) — the splice-through and
/// empty-result behaviors `FindAPIToolTests` previously covered against the
/// retired `FindAPITool(searcher:limit:).dispatch(task:)` shape, now driven
/// against `FindAPIsTool.call(arguments:)`'s native `Tool` shape, plus new
/// coverage for `.auto` mode's retrieval-only fallback when no selection
/// tier is configured.
@Suite("FindAPIsTool")
struct FindAPIsToolTests {
    @Test("a scripted selection's matched standalone entry splices FindAPIsTool's output verbatim, via a fork() of the prefix-rooted session")
    func standaloneSelectionSplicesVerbatimBlockAndExample() async throws {
        let surface = try MultiTool.Builder().addTool(TripCitiesTool()).build()
        let entry = try #require(surface.entries.first)
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [#"{"ids":["tripCities"]}"#])
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .auto,
            selection: SelectionConfig(model: { _ in root }, capacityCharacterLimit: .max)
        )
        let findAPIsTool = FindAPIsTool(searcher: searcher, limit: surface.entries.count)

        let feedback = try await findAPIsTool.call(arguments: FindAPIsArguments(task: "list the trip cities"))

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
            mode: .auto,
            selection: SelectionConfig(model: { _ in root }, capacityCharacterLimit: .max)
        )
        let findAPIsTool = FindAPIsTool(searcher: searcher, limit: surface.entries.count)

        let feedback = try await findAPIsTool.call(arguments: FindAPIsArguments(task: "file a github issue"))

        // The qualified `// tools.github.createIssue` banner — never the bare
        // `declare function createIssue(...)` alone — proves the namespace
        // survives the splice.
        #expect(feedback.contains("// tools.github.createIssue"))
        #expect(feedback.contains(entry.block))
        // The rendered example call itself — both the embedded JSDoc
        // `@example` line inside `block` and the separate `Example: ...`
        // trailer — must show the fully-qualified `tools.github.createIssue(`
        // call a model could actually invoke, never the bare, wrong
        // `tools.createIssue(` call a model can't guess to qualify on its
        // own.
        #expect(feedback.contains("tools.github.createIssue("))
        #expect(!feedback.contains("tools.createIssue("))
    }

    @Test("an empty selection formats as a clear \"no matching functions\" message, not an empty string")
    func emptySelectionFormatsAsNoMatchMessage() async throws {
        let surface = try MultiTool.Builder().addTool(TripCitiesTool()).build()
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [#"{"ids":[]}"#])
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .auto,
            selection: SelectionConfig(model: { _ in root }, capacityCharacterLimit: .max)
        )
        let findAPIsTool = FindAPIsTool(searcher: searcher, limit: surface.entries.count)

        let feedback = try await findAPIsTool.call(arguments: FindAPIsArguments(task: "something no tool does"))

        #expect(feedback == "findAPIs(\"something no tool does\") found no matching functions.")
    }

    @Test(".auto mode without a configured selection tier still returns retrieval-only results, with no session involved")
    func autoModeWithNoSelectionTierFallsBackToRetrieval() async throws {
        let surface = try MultiTool.Builder().addTool(TripCitiesTool()).build()
        let entry = try #require(surface.entries.first)
        // No `selection:` configured at all — `.auto` degrades to `.retrieval`
        // (plan.md §7), so this searcher never needs a session/grammar.
        let searcher = MetadataSearcher(items: surface.entries, mode: .auto)
        let findAPIsTool = FindAPIsTool(searcher: searcher, limit: surface.entries.count)

        let feedback = try await findAPIsTool.call(arguments: FindAPIsArguments(task: "trip cities"))

        #expect(feedback.contains("findAPIs(\"trip cities\") found:"))
        #expect(feedback.contains(entry.block))
    }

    @Test("the production registry+librarian initializer wires .auto mode over the registry's own surface entries")
    func registryInitializerBuildsAutoModeSearcherWithNoLibrarian() async throws {
        let registry = try MultiTool.Builder().addTool(TripCitiesTool()).buildRegistry()

        // `librarian: nil` — no selection tier configured, so `.auto` must
        // still answer via retrieval alone, proving this initializer never
        // requires a Router model to be independently constructible.
        let findAPIsTool = try FindAPIsTool(registry: registry, librarian: nil)

        let feedback = try await findAPIsTool.call(arguments: FindAPIsArguments(task: "trip cities"))

        #expect(feedback.contains("findAPIs(\"trip cities\") found:"))
        #expect(findAPIsTool.name == "findAPIs")
    }
}
