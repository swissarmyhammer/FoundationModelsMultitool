import FoundationModelsMetadataRegistry
import Testing
import os

@testable import FoundationModelsMultitool

/// Coverage for `SearchToolsTool` (task 4aveepp's extraction: `searchTools` as a
/// standalone `FoundationModels.Tool` conformer, decoupled from the retired
/// `MultiToolAgent` loop and its turn machinery) — the splice-through and
/// empty-result behaviors `FindAPIToolTests` previously covered against the
/// retired `FindAPITool(searcher:limit:).dispatch(task:)` shape, now driven
/// against `SearchToolsTool.call(arguments:)`'s native `Tool` shape, plus new
/// coverage for `.auto` mode's retrieval-only fallback when no selection
/// tier is configured.
@Suite("SearchToolsTool")
struct SearchToolsToolTests {
    @Test("a scripted selection's matched standalone entry splices SearchToolsTool's output verbatim, via a fork() of the prefix-rooted session")
    func standaloneSelectionSplicesVerbatimBlockAndExample() async throws {
        let surface = try MultiTool.Builder().addTool(TripCitiesTool()).build()
        let entry = try #require(surface.entries.first)
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [#"{"ids":["getTrip"]}"#])
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .auto,
            selection: SelectionConfig(model: { _, _ in root }, capacityCharacterLimit: .max)
        )
        let searchToolsTool = SearchToolsTool(searcher: searcher, limit: surface.entries.count)

        let feedback = try await searchToolsTool.call(arguments: SearchToolsArguments(task: "list the trip cities"))

        #expect(root.forkCount == 1)
        #expect(feedback.contains("searchTools(\"list the trip cities\") found:"))
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
            selection: SelectionConfig(model: { _, _ in root }, capacityCharacterLimit: .max)
        )
        let searchToolsTool = SearchToolsTool(searcher: searcher, limit: surface.entries.count)

        let feedback = try await searchToolsTool.call(arguments: SearchToolsArguments(task: "file a github issue"))

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
            selection: SelectionConfig(model: { _, _ in root }, capacityCharacterLimit: .max)
        )
        let searchToolsTool = SearchToolsTool(searcher: searcher, limit: surface.entries.count)

        let feedback = try await searchToolsTool.call(arguments: SearchToolsArguments(task: "something no tool does"))

        #expect(feedback == "searchTools(\"something no tool does\") found no matching functions.")
    }

    @Test(".auto mode without a configured selection tier still returns retrieval-only results, with no session involved")
    func autoModeWithNoSelectionTierFallsBackToRetrieval() async throws {
        let surface = try MultiTool.Builder().addTool(TripCitiesTool()).build()
        let entry = try #require(surface.entries.first)
        // No `selection:` configured at all — `.auto` degrades to `.retrieval`
        // (plan.md §7), so this searcher never needs a session/grammar.
        let searcher = MetadataSearcher(items: surface.entries, mode: .auto)
        let searchToolsTool = SearchToolsTool(searcher: searcher, limit: surface.entries.count)

        let feedback = try await searchToolsTool.call(arguments: SearchToolsArguments(task: "trip cities"))

        #expect(feedback.contains("searchTools(\"trip cities\") found:"))
        #expect(feedback.contains(entry.block))
    }

    @Test("a non-empty result ends with the imperative call-runCode-now footer, after the match blocks")
    func nonEmptyResultEndsWithImperativeFooter() async throws {
        let surface = try MultiTool.Builder().addTool(TripCitiesTool()).build()
        let entry = try #require(surface.entries.first)
        let searcher = MetadataSearcher(items: surface.entries, mode: .auto)
        let searchToolsTool = SearchToolsTool(searcher: searcher, limit: surface.entries.count)

        let feedback = try await searchToolsTool.call(arguments: SearchToolsArguments(task: "trip cities"))

        #expect(feedback.contains(SearchToolsTool.writeSnippetInstruction))
        #expect(feedback.contains("exact tools.* paths"))
        // The footer follows the match blocks — it is a next-step
        // instruction, not a header.
        let blockRange = try #require(feedback.range(of: entry.block))
        let footerRange = try #require(feedback.range(of: SearchToolsTool.writeSnippetInstruction))
        #expect(blockRange.upperBound <= footerRange.lowerBound)
    }

    @Test("searchTools's description alone carries the whole contract — the mounted tools are the entire integration, with no session instructions")
    func descriptionCarriesTheNoSystemPromptScaffolding() throws {
        let registry = try MultiTool.Builder().addTool(TripCitiesTool()).buildRegistry()
        // Collapse the multiline literal's hard line-wraps to single spaces
        // so an assertion probes the guidance, not incidental wrapping.
        let description = try SearchToolsTool(registry: registry, librarian: nil)
            .description
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        // The full essence of the retired system prompt, verified clause by
        // clause so a future paraphrase can't silently drop a load-bearing
        // line. `sessionInstructions` is gone (task tkrdwb8): a `Tool`
        // description is serialized into the prompt on every turn, while a
        // session instruction is optional and a host may never pass one, so
        // every guarantee that instruction carried is asserted here instead.
        #expect(description.contains("loaded dynamically")) // the set is not knowable in advance
        // Provenance is stated positively. The negative form inverted once in
        // review ("State no fact ... that a tools.* call returned"), which forbids
        // exactly what it means to require.
        // Provenance: the answer comes from the snippet's return, not from priors.
        // The stronger per-fact wording lives on runCode's description, which is
        // where a snippet is actually written.
        #expect(description.contains("answer from what that snippet returns"))
        #expect(description.localizedCaseInsensitiveContains("call searchTools first")) // searchTools-first stance
        #expect(description.contains("instead of asking the user")) // search, don't ask
        #expect(description.contains("once per kind of data")) // one search per kind
        // Operational, not persona: no "helpful assistant" ritual — just
        // clear information on how to call the tools.
        #expect(!description.localizedCaseInsensitiveContains("helpful assistant"))
        // Access is stated as a plain fact, with no never-refuse clause for
        // the search rule to hang off — that subordination is the defect this
        // wording replaces (task tkrdwb8).
        #expect(description.contains("searchTools is what tells you the current set"))
        #expect(!description.localizedCaseInsensitiveContains("refus"))
        #expect(description.contains("name the capability that is missing"))
        #expect(description.contains("runCode")) // the runCode handoff
        // Honest miss: when nothing matches, say so rather than invent.
        #expect(description.localizedCaseInsensitiveContains("say so"))
        // The numbered procedure comes before any rule, and it is
        // unconditional: nothing asks the model to judge whether it already
        // has a tool before step 1. The retired "Never refuse ... instead,
        // always call searchTools" phrasing scoped searching to the
        // about-to-refuse reader and never reached the confident guesser,
        // which is the failing population (task tkrdwb8).
        // The prior is stated, not left as a classification the model performs
        // before acting: "does this need the user's data?" is the same shape of
        // pre-action judgment the retired "Never refuse ... instead, always call
        // searchTools" phrasing let a confident model answer wrongly (task tkrdwb8).
        #expect(description.contains("Call searchTools first"))
        // Search precedes the snippet, in the text as well as in the workflow.
        let searchRange = try #require(description.range(of: "searchTools first"))
        let snippetRange = try #require(description.range(of: "Then write one runCode snippet"))
        #expect(searchRange.upperBound <= snippetRange.lowerBound)
        // A stated prior, not a classification the model performs before acting:
        // "does this need the user's data?" is the same shape of pre-action judgment
        // that the retired "instead" clause let a confident model answer wrongly.
        #expect(description.contains("Almost all of them do"))
        // The session rule is checkable conversational state — "have I called
        // searchTools in this session yet?" — not the model's confidence. An
        // "if you are unsure" trigger is one a confident model always passes,
        // which is the defect this line of work has been chasing. It aims at the
        // dominant recorded failure: a turn that ends with toolCalls=0, where
        // three of the sample arm's seven failures sat (task 9zk44z6).
        #expect(description.contains("Call searchTools at least once in every session"))
        #expect(description.contains("passing the user's own request"))
        #expect(description.contains("as the query"))
        // Narrow follow-up searches supplement the first one; they do not replace
        // it. The generator is handed whatever query searchTools received, so a model
        // that only ever searches a sub-question hands it the wrong task.
        #expect(description.contains("come after that one, not"))
        #expect(description.contains("you do not know what this session mounts"))
        // searchTools is not one-shot. A request needing two kinds of data cannot be
        // served by a single search, and a model that searched once, came up short,
        // and narrated what it still needed is the recorded announce-then-stop.
        #expect(description.contains("again whenever"))
        #expect(description.contains("still needs a function you do not hold yet"))
        // The anti-guessing trigger is checkable conversational state, never
        // the model's own confidence — a confident model always passes an
        // "if you are unsure" test, which is the failure being closed.
        #expect(description.contains("instead of naming a function yourself"))
        #expect(!description.localizedCaseInsensitiveContains("if you are unsure"))
        #expect(!description.localizedCaseInsensitiveContains("real-time"))
        // Only a pure calculation needs no API at all.
        #expect(description.contains("pure arithmetic or string work needs no functions"))
        // A shown sequence, not only a stated rule — and the worked example
        // shows the *second* search, so the iteration licence is demonstrated
        // and not merely asserted.
        #expect(description.contains("Worked example"))
        // The worked example demonstrates the second search rather than only
        // stating that iteration is allowed.
        #expect(description.contains("no function for that came back"))
        #expect(description.contains("who last edited a document"))
    }

    @Test("the production registry+librarian initializer wires .auto mode over the registry's own surface entries")
    func registryInitializerBuildsAutoModeSearcherWithNoLibrarian() async throws {
        let registry = try MultiTool.Builder().addTool(TripCitiesTool()).buildRegistry()

        // `librarian: nil` — no selection tier configured, so `.auto` must
        // still answer via retrieval alone, proving this initializer never
        // requires a Router model to be independently constructible.
        let searchToolsTool = try SearchToolsTool(registry: registry, librarian: nil)

        let feedback = try await searchToolsTool.call(arguments: SearchToolsArguments(task: "trip cities"))

        #expect(feedback.contains("searchTools(\"trip cities\") found:"))
        #expect(searchToolsTool.name == "searchTools")
    }

    // MARK: - The generated sample leads the output

    /// A candidate snippet that clears every gate against a
    /// `CitiesTool` + `TempTool` catalog.
    static let sampleReply = """
        ```js
        const trip = await tools.getCities({});
        const temp = await tools.getTemperature({ city: trip.cities[0] });
        return temp.tempC;
        ```
        """

    /// Builds a `searchTools` over a `CitiesTool` + `TempTool` catalog, with a
    /// scripted sample generator whose turns are `replies`.
    ///
    /// - Parameter replies: one canned generator reply per expected turn, or
    ///   an empty array to configure no generator at all.
    /// - Returns: the catalog and the tool over it.
    static func toolWithScriptedGenerator(
        replies: [String]?
    ) throws -> (surface: APISurface, tool: SearchToolsTool) {
        let surface = try MultiTool.Builder().addTool(CitiesTool()).addTool(TempTool()).build()
        let searcher = MetadataSearcher(items: surface.entries, mode: .auto)
        let sample = replies.map { replies in
            let session = ScriptedAgentSession(replies)
            return SampleSnippetConfig(
                makeSession: { _ in session },
                interpreter: JSCInterpreter(timeLimit: 5.0)
            )
        }
        return (surface, SearchToolsTool(searcher: searcher, limit: surface.entries.count, sample: sample))
    }

    @Test("a validated sample leads the result, ahead of the signature blocks, and replaces the write-a-snippet footer")
    func validatedSampleLeadsTheResult() async throws {
        let (surface, tool) = try Self.toolWithScriptedGenerator(replies: [Self.sampleReply])
        let entry = try #require(surface.entries.first { $0.path == "getCities" })

        let feedback = try await tool.call(arguments: SearchToolsArguments(task: "how warm is the trip"))

        // The snippet itself, unfenced, is what the model reads first.
        #expect(feedback.contains("const trip = await tools.getCities({});"))
        #expect(!feedback.contains("```"))
        // The footer directs the model at *this* snippet; the old "go write
        // one" instruction would tell it to discard the snippet and write
        // another.
        #expect(feedback.contains("Call runCode now"))
        #expect(!feedback.contains(SearchToolsTool.writeSnippetInstruction))
        // Signatures are supporting material behind the code, not ahead of it.
        let snippetRange = try #require(feedback.range(of: "return temp.tempC;"))
        let blockRange = try #require(feedback.range(of: entry.block))
        #expect(snippetRange.upperBound <= blockRange.lowerBound)
    }

    @Test("an always-failing generator returns exactly the result no generator at all would return")
    func failingGeneratorFallsBackToTheSignaturesOnlyResult() async throws {
        let unusable = "I will not write that."
        let (_, withGenerator) = try Self.toolWithScriptedGenerator(replies: [unusable, unusable, unusable])
        let (_, withoutGenerator) = try Self.toolWithScriptedGenerator(replies: nil)
        let arguments = SearchToolsArguments(task: "how warm is the trip")

        let fallback = try await withGenerator.call(arguments: arguments)
        let today = try await withoutGenerator.call(arguments: arguments)

        #expect(fallback == today)
        #expect(fallback.contains(SearchToolsTool.writeSnippetInstruction))
    }

    @Test("a generator is never asked for a sample when nothing matched")
    func noMatchesNeverAsksTheGenerator() async throws {
        let surface = try MultiTool.Builder().addTool(CitiesTool()).build()
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [#"{"ids":[]}"#])
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .auto,
            selection: SelectionConfig(model: { _, _ in root }, capacityCharacterLimit: .max)
        )
        let session = ScriptedAgentSession([Self.sampleReply])
        let tool = SearchToolsTool(
            searcher: searcher,
            limit: surface.entries.count,
            sample: SampleSnippetConfig(makeSession: { _ in session }, interpreter: JSCInterpreter(timeLimit: 5.0))
        )

        let feedback = try await tool.call(arguments: SearchToolsArguments(task: "something no tool does"))

        #expect(feedback == "searchTools(\"something no tool does\") found no matching functions.")
        #expect(session.callCount == 0)
    }

    @Test("the production initializer leaves sample generation unconfigured unless a generator is supplied")
    func productionInitializerLeavesSampleGenerationOff() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()

        let tool = try SearchToolsTool(registry: registry, librarian: nil, sampleGenerator: nil)
        let feedback = try await tool.call(arguments: SearchToolsArguments(task: "trip cities"))

        #expect(feedback.contains(SearchToolsTool.writeSnippetInstruction))
    }
}
