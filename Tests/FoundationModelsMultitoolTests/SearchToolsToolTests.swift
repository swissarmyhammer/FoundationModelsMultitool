import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsRouter
import Synchronization
import Testing

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
    /// The error a host's selection factory throws in
    /// ``throwingSelectionFactoryStopsTheBuild()``.
    struct SelectionFactoryFailure: Error {}

    @Test("a scripted selection's matched standalone entry splices SearchToolsTool's output verbatim, via one new session with the catalog prefix as its instructions")
    func standaloneSelectionSplicesVerbatimBlockAndExample() async throws {
        let surface = try MultiTool.Builder().addTool(TripCitiesTool()).build()
        let entry = try #require(surface.entries.first)
        let model = ScriptedLanguageModel([#"{"ids":["getTrip"]}"#])
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .auto,
            selection: SelectionConfig(model: model, capacityCharacterLimit: .max)
        )
        let searchToolsTool = SearchToolsTool(searcher: searcher, limit: surface.entries.count)

        let feedback = try await searchToolsTool.call(arguments: SearchToolsArguments(task: "list the trip cities"))

        let call = try #require(model.calls.first)
        #expect(model.calls.count == 1)
        // A new session: the prefix is its instructions, and the search is its
        // only prompt.
        #expect(call.instructions?.contains("getTrip") == true)
        #expect(call.prompts.count == 1)
        #expect(call.prompt?.contains("list the trip cities") == true)
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
        let model = ScriptedLanguageModel([#"{"ids":["github.createIssue"]}"#])
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .auto,
            selection: SelectionConfig(model: model, capacityCharacterLimit: .max)
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
        let model = ScriptedLanguageModel([#"{"ids":[]}"#])
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .auto,
            selection: SelectionConfig(model: model, capacityCharacterLimit: .max)
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
        // (plan.md §7), so this searcher never needs a model.
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
        let description = try SearchToolsTool(registry: registry, selection: nil)
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

    @Test("the production registry initializer wires .auto mode over the registry's own surface entries with no selection tier")
    func registryInitializerBuildsAutoModeSearcherWithNoSelection() async throws {
        let registry = try MultiTool.Builder().addTool(TripCitiesTool()).buildRegistry()

        // `selection: nil` — no selection tier configured, so `.auto` must
        // still answer via retrieval alone, proving this initializer never
        // requires a Router model to be independently constructible.
        let searchToolsTool = try SearchToolsTool(registry: registry, selection: nil)

        let feedback = try await searchToolsTool.call(arguments: SearchToolsArguments(task: "trip cities"))

        #expect(feedback.contains("searchTools(\"trip cities\") found:"))
        #expect(searchToolsTool.name == "searchTools")
    }

    // MARK: - The registry seams drive selection with no Router (^kzaefgz)

    @Test("a host's SelectionConfig over a scripted model drives selection end to end, with the catalog ids handed to its factory")
    func hostSelectionConfigDrivesSelectionEndToEnd() async throws {
        let registry = try MultiTool.Builder().addTool(TripCitiesTool()).addTool(TempTool()).buildRegistry()
        let entry = try #require(registry.surface.entries.first { $0.path == "getTrip" })
        let model = ScriptedLanguageModel([#"{"ids":["getTrip"]}"#])
        let receivedIds = Mutex<[[String]]>([])

        let searchToolsTool = try SearchToolsTool(
            registry: registry,
            selection: { ids in
                receivedIds.withLock { $0.append(ids) }
                return SelectionConfig(model: model, capacityCharacterLimit: .max)
            })
        let feedback = try await searchToolsTool.call(arguments: SearchToolsArguments(task: "list the trip cities"))

        // The factory ran one time, for the ids of the whole catalog.
        #expect(receivedIds.withLock { $0 } == [registry.surface.entries.map(\.path)])
        // The selection prompt reached the model of the host.
        #expect(model.calls.count == 1)
        #expect(feedback.contains(entry.block))
        #expect(!feedback.contains("tools.getTemperature"))
    }

    @Test("a host's SelectionConfig drives selection through the mounted searchTools")
    func hostSelectionConfigDrivesTheMountedSearchTools() async throws {
        let registry = try MultiTool.Builder().addTool(TripCitiesTool()).addTool(TempTool()).buildRegistry()
        let entry = try #require(registry.surface.entries.first { $0.path == "getTrip" })
        let model = ScriptedLanguageModel([#"{"ids":["getTrip"]}"#])

        let mounted = try registry.makeSessionTools(selection: { _ in
            SelectionConfig(model: model, capacityCharacterLimit: .max)
        })
        let searchToolsTool = try #require(mounted.first as? SearchToolsTool)
        let feedback = try await searchToolsTool.call(arguments: SearchToolsArguments(task: "list the trip cities"))

        #expect(model.calls.count == 1)
        #expect(feedback.contains(entry.block))
        #expect(!feedback.contains("tools.getTemperature"))
    }

    @Test("a host's selection factory that throws stops the build of the session tools")
    func throwingSelectionFactoryStopsTheBuild() throws {
        let registry = try MultiTool.Builder().addTool(TripCitiesTool()).buildRegistry()

        #expect(throws: SelectionFactoryFailure.self) {
            try registry.makeSessionTools(selection: { _ in throw SelectionFactoryFailure() })
        }
    }

    @Test("a host's sample model backs the sample the registry initializer generates")
    func hostSampleModelBacksTheSample() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).addTool(TempTool()).buildRegistry()
        let model = ScriptedLanguageModel([Self.sampleReply])

        let tool = try SearchToolsTool(registry: registry, selection: nil, sampleModel: model)
        let feedback = try await tool.call(arguments: SearchToolsArguments(task: "how warm is the trip"))

        #expect(model.calls.count == 1)
        #expect(feedback.contains("const trip = await tools.getCities({});"))
        #expect(!feedback.contains(SearchToolsTool.writeSnippetInstruction))
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
    ///   `nil` to configure no generator at all.
    /// - Returns: the catalog and the tool over it.
    static func toolWithScriptedGenerator(
        replies: [String]?
    ) throws -> (surface: APISurface, tool: SearchToolsTool) {
        let surface = try MultiTool.Builder().addTool(CitiesTool()).addTool(TempTool()).build()
        let searcher = MetadataSearcher(items: surface.entries, mode: .auto)
        let sample = replies.map { replies in
            SampleSnippetConfig(model: ScriptedLanguageModel(replies), interpreter: JSCInterpreter())
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
        let selectionModel = ScriptedLanguageModel([#"{"ids":[]}"#])
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .auto,
            selection: SelectionConfig(model: selectionModel, capacityCharacterLimit: .max)
        )
        let sampleModel = ScriptedLanguageModel([Self.sampleReply])
        let tool = SearchToolsTool(
            searcher: searcher,
            limit: surface.entries.count,
            sample: SampleSnippetConfig(model: sampleModel, interpreter: JSCInterpreter())
        )

        let feedback = try await tool.call(arguments: SearchToolsArguments(task: "something no tool does"))

        #expect(feedback == "searchTools(\"something no tool does\") found no matching functions.")
        #expect(sampleModel.calls.isEmpty)
    }

    @Test("the production initializer leaves sample generation unconfigured unless a generator is supplied")
    func productionInitializerLeavesSampleGenerationOff() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()

        let tool = try SearchToolsTool(registry: registry, selection: nil, sampleModel: nil)
        let feedback = try await tool.call(arguments: SearchToolsArguments(task: "trip cities"))

        #expect(feedback.contains(SearchToolsTool.writeSnippetInstruction))
    }

    // MARK: - A session error is visible (^zhmqvxb)

    /// The refusal Router gives when a synchronous tool body waits for a
    /// session on the model of its own open submission.
    static let sameModelRefusal = GenerationQueueError.waitInsideOpenSubmission(model: "stub/standard")

    @Test("a librarian that Router refuses on the model of the calling session gives that refusal as the tool error")
    func refusedLibrarianGivesTheRefusalAsTheToolError() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let tool = try SearchToolsTool(registry: registry, selection: { _ in
            SelectionConfig(
                model: ScriptedLanguageModel(answers: [.failure(Self.sameModelRefusal)]),
                capacityCharacterLimit: .max)
        })

        // Not an empty selection, and not the signatures alone: the call
        // fails, and the model reads the error of the librarian.
        await #expect(throws: Self.sameModelRefusal) {
            try await tool.call(arguments: SearchToolsArguments(task: "list the cities"))
        }
    }

    @Test("a sample session that throws gives a visible note with its error, and the signatures")
    func throwingSampleSessionGivesAVisibleNote() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).addTool(TempTool()).buildRegistry()
        let entry = try #require(registry.surface.entries.first { $0.path == "getCities" })
        let failing = ScriptedLanguageModel(answers: [.failure(Self.sameModelRefusal)])
        let tool = try SearchToolsTool(registry: registry, selection: nil, sampleModel: failing)
        let withoutGenerator = try SearchToolsTool(registry: registry, selection: nil)
        let arguments = SearchToolsArguments(task: "how warm is the trip")

        let feedback = try await tool.call(arguments: arguments)
        let today = try await withoutGenerator.call(arguments: arguments)

        let refusalText = try #require(Self.sameModelRefusal.errorDescription)
        #expect(feedback != today)
        #expect(feedback.contains(SearchToolsTool.sampleFailureLead))
        #expect(feedback.contains(refusalText))
        #expect(feedback.contains(entry.block))
        #expect(feedback.contains(SearchToolsTool.writeSnippetInstruction))
    }

    // MARK: - Discovery blocks until it is done (^bffrdpr)

    @Test("a slow discovery call returns its catalog inline, even mounted by a site that backgrounds")
    func discoveryNeverReturnsAPendingEnvelope() async throws {
        let surface = try MultiTool.Builder().addTool(CitiesTool()).build()
        // Slow, not broken: the model answers a genuine selection in the end.
        // The delay is what gives a background mount its chance to background
        // the call, which is exactly what `searchTools` must not allow.
        let slow = ScriptedLanguageModel(answers: [.delayed(#"{"ids":["getCities"]}"#, by: .milliseconds(300))])
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .auto,
            selection: SelectionConfig(model: slow, capacityCharacterLimit: .max)
        )
        let tool = SearchToolsTool(searcher: searcher, limit: surface.entries.count)

        // The harshest site mount there is: background, no clock. The tool
        // declares `synchronous` itself, and a declaration wins over
        // the site, so discovery still blocks. Asserted against a mount rather
        // than by timing a real search: "however long it takes" is a property
        // of the mount, not of a stopwatch.
        let context = try await makeOuterRunContext()
        let mounted = try #require(
            context.mount(tool, as: ToolMount(mode: .background, timeout: nil))
                as? any Tool<SearchToolsArguments, String>
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
                model: ScriptedLanguageModel(answers: [.failure(SelectionSearchFailure())]),
                capacityCharacterLimit: .max
            )
        )
        let tool = SearchToolsTool(searcher: searcher, limit: surface.entries.count)
        let context = try await makeOuterRunContext()
        let mounted = try #require(
            context.mount(tool, as: ToolMount(mode: .background, timeout: nil))
                as? any Tool<SearchToolsArguments, String>
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

/// A real searcher failure, the one thing that should reach the model from a
/// discovery call.
struct SelectionSearchFailure: Error, Equatable {}
