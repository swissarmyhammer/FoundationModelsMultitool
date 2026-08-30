import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsRouter
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
            selection: SelectionConfig(model: { _ in root }, capacityCharacterLimit: .max)
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
            selection: SelectionConfig(model: { _ in root }, capacityCharacterLimit: .max)
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
            selection: SelectionConfig(model: { _ in root }, capacityCharacterLimit: .max)
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
        // The set is not knowable in advance, and searchTools is the only way in.
        #expect(description.contains("mounted dynamically"))
        #expect(description.contains("the only"))
        #expect(description.contains("way to see them"))
        // The session mandate lives here, once. It is unconditional and keyed to
        // the user's own request, not to the model's confidence: an "if you are
        // unsure" trigger is one a confident model always passes, which is the
        // failure this line exists to close. It aims at the dominant recorded
        // failure, a turn ending with toolCalls=0 (task 9zk44z6).
        #expect(description.contains("Call searchTools before you answer any request"))
        #expect(description.contains("passing the"))
        #expect(description.contains("user's own request as the query"))
        #expect(!description.localizedCaseInsensitiveContains("if you are unsure"))
        // What comes back is the teacher: typed signatures and a runnable example.
        #expect(description.contains("typed signature"))
        #expect(description.contains("runnable example"))
        // searchTools is not one-shot. A request needing two kinds of data cannot
        // be served by one search, and a model that searched once, came up short,
        // and narrated what it still needed is the recorded announce-then-stop.
        #expect(description.contains("Search again for every further capability"))
        // Honest miss: when nothing matches, say so and name it rather than invent.
        #expect(description.localizedCaseInsensitiveContains("say so"))
        #expect(description.contains("name the capability"))
        // Never guess a name, never push the work back to the user.
        #expect(description.contains("Never name a function yourself"))
        #expect(description.contains("never ask the user for data a function can fetch"))
        // Operational, not persona, and refusal is never named — naming it would
        // put it back in the option set. An honest failure report replaces it.
        #expect(!description.localizedCaseInsensitiveContains("helpful assistant"))
        #expect(!description.localizedCaseInsensitiveContains("refus"))
        #expect(!description.localizedCaseInsensitiveContains("real-time"))
        // No exemption clause: task 5qadve5 deleted the arithmetic carve-out, so
        // nothing in the surface gives a reason to skip the search.
        #expect(!description.localizedCaseInsensitiveContains("needs no functions"))
        // The runCode handoff — one snippet over the exact returned paths — is
        // asserted once, on runCode's own description, which is in the prompt
        // alongside this one. Task 5qadve5 removed the restatement here.
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
            selection: SelectionConfig(model: { _ in root }, capacityCharacterLimit: .max)
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

    // MARK: - Discovery blocks until it is done (^bffrdpr)

    @Test("a slow discovery call returns its catalog inline, even mounted by a site that backgrounds")
    func discoveryNeverReturnsAPendingEnvelope() async throws {
        let surface = try MultiTool.Builder().addTool(CitiesTool()).build()
        let root = SlowSelectionRootSession(
            delay: .milliseconds(300), response: #"{"ids":["getCities"]}"#
        )
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .auto,
            selection: SelectionConfig(model: { _ in root }, capacityCharacterLimit: .max)
        )
        let tool = SearchToolsTool(searcher: searcher, limit: surface.entries.count)

        // The harshest site mount there is: background, no clock. The tool
        // declares `synchronousUnbounded` itself, and a declaration wins over
        // the site, so discovery still blocks. Asserted against a mount rather
        // than by timing a real search: "however long it takes" is a property
        // of the mount, not of a stopwatch.
        let mounted = try #require(
            ToolMounting.makeWrapped(
                tool: tool,
                sessionID: ULID(),
                mailbox: SessionMailbox(),
                sink: RecordingEventSink(),
                configuration: ToolMount(mode: .background, timeout: nil)
            ) as? any Tool<SearchToolsArguments, String>
        )

        let feedback = try await mounted.call(arguments: SearchToolsArguments(task: "list the cities"))

        #expect(!PendingRunEnvelope.isRendered(text: feedback))
        #expect(feedback.contains("getCities"))
    }

    @Test("a searcher that fails surfaces its own error, never a timeout and never a token")
    func aFailingSearcherSurfacesAsAnError() async throws {
        let surface = try MultiTool.Builder().addTool(CitiesTool()).build()
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .auto,
            selection: SelectionConfig(
                model: { _, _ in FailingSelectionRootSession() }, capacityCharacterLimit: .max
            )
        )
        let tool = SearchToolsTool(searcher: searcher, limit: surface.entries.count)
        let mounted = try #require(
            ToolMounting.makeWrapped(
                tool: tool,
                sessionID: ULID(),
                mailbox: SessionMailbox(),
                sink: RecordingEventSink(),
                configuration: ToolMount(mode: .background, timeout: nil)
            ) as? any Tool<SearchToolsArguments, String>
        )

        // Slow is not broken, and broken is not slow: a real failure reaches the
        // model as a failure. What must never happen is the other two shapes —
        // a `ToolMountError.timedOut` blaming the clock, or a completion
        // token for a search that already failed.
        await #expect(throws: SelectionSearchFailure.self) {
            try await mounted.call(arguments: SearchToolsArguments(task: "list the cities"))
        }
    }
}

// MARK: - Selection roots that are slow, and that fail

/// Thrown by ``FailingSelectionRootSession`` — a real searcher failure, the one
/// thing that should reach the model from a discovery call.
struct SelectionSearchFailure: Error, Equatable {}

/// A selection root whose `fork()` takes its time before answering.
///
/// Slow, not broken: it returns a genuine selection in the end. The delay is
/// what gives a background mount its chance to background the call, which is exactly
/// what `searchTools` must not allow.
final class SlowSelectionRootSession: AgentSession, Sendable {
    /// How long `fork()` takes before it answers.
    private let delay: Duration

    /// The selection JSON the forked session returns.
    private let response: String

    /// Creates a slow selection root.
    ///
    /// - Parameters:
    ///   - delay: how long `fork()` takes.
    ///   - response: the selection JSON to answer with.
    init(delay: Duration, response: String) {
        self.delay = delay
        self.response = response
    }

    func respond(to prompt: String) async throws -> String {
        throw RootSessionRespondCalledDirectlyError()
    }

    func fork() async throws -> any AgentSession {
        try await Task.sleep(for: delay)
        return ScriptedAgentSession([response])
    }
}

/// A selection root that fails outright.
final class FailingSelectionRootSession: AgentSession, Sendable {
    func respond(to prompt: String) async throws -> String {
        throw SelectionSearchFailure()
    }

    func fork() async throws -> any AgentSession {
        throw SelectionSearchFailure()
    }
}
