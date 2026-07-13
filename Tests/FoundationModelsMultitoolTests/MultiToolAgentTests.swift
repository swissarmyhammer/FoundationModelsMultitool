import FoundationModels
import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsMultitool

/// M4b coverage for `MultiToolAgent`: the search-then-code loop itself,
/// driven entirely against the internal `AgentSession` seam via
/// `ScriptedAgentSession` (`Fixtures/MultiToolAgentFixtures.swift`) — zero
/// GPU, no Router dependency — under the default `.tolerantParse()` turn
/// format. No model is needed for any of this; a scripted session stands in
/// for what a real `RoutedSession` would produce.
@Suite("MultiToolAgent")
struct MultiToolAgentTests {
    // MARK: - findAPIs → runCode → final, dispatched correctly

    @Test("a scripted findAPIs → runCode → final turn sequence dispatches each step and returns the final text")
    func dispatchesFindApisThenRunCodeThenFinal() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let mainSession = ScriptedAgentSession([
            "ACTION: findAPIs\nTASK: list the trip cities",
            "ACTION: runCode\nCODE:\n```js\nreturn tools.cities().cities.length;\n```",
            "ACTION: final\nANSWER: There are 3 cities.",
        ])
        let librarianRoot = RootSessionRespondCalledDirectlySession(forkResponses: [cannedCitiesSelectionJson])
        let searcher = makeScriptedSelectionSearcher(registry: registry, root: librarianRoot)
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            findAPISearcher: searcher,
            instructions: "You are a travel assistant."
        )

        let reply = try await agent.respond(to: "How many cities are on my trip?")

        #expect(reply == "There are 3 cities.")
        #expect(mainSession.callCount == 3)
        // findAPIs went through the searcher's real dispatch pipeline: a
        // fork() of the prefix-rooted session, never the root's own respond(to:).
        #expect(librarianRoot.forkCount == 1)
        // findAPIs's result — formatted by FindAPIsTool, not raw text — was
        // spliced back in as the next turn's context.
        #expect(mainSession.receivedPrompts[1].contains("declare function cities(args: { unused?: string }): { cities: string[] };"))
        #expect(mainSession.receivedPrompts[1].contains("Example: tools.cities({});"))
        // The runCode result (3, the cities count) was fed back before the final turn.
        #expect(mainSession.receivedPrompts[2].contains("3"))
    }

    // MARK: - findAPIs actually drives a Librarian: prefix-caching/fork() is real, not superficial

    @Test(
        "two findAPIs calls in one respond(to:) share one cached Librarian root session, each dispatched through its own fork()"
    )
    func findApisCallsShareOneCachedLibrarianRootAcrossForks() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let mainSession = ScriptedAgentSession([
            "ACTION: findAPIs\nTASK: list the trip cities",
            "ACTION: findAPIs\nTASK: list the trip cities again",
            "ACTION: final\nANSWER: done",
        ])
        let librarianRoot = RootSessionRespondCalledDirectlySession(forkResponses: [
            cannedCitiesSelectionJson,
            cannedCitiesSelectionJson,
        ])
        let rootFactoryCallCount = CallCounter()
        let searcher = MetadataSearcher(
            items: registry.surface.entries,
            mode: .selection,
            selection: SelectionConfig(
                model: { _ in
                    rootFactoryCallCount.increment()
                    return librarianRoot
                },
                capacityCharacterLimit: .max
            )
        )
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            findAPISearcher: searcher,
            instructions: "You are a travel assistant."
        )

        let reply = try await agent.respond(to: "How many cities are on my trip?")

        #expect(reply == "done")
        // The root session was created exactly once (cached across both
        // findAPIs calls in this respond(to:)), and each call reached it
        // through its own fork() — the KV-cache-reuse contract the
        // searcher's selection tier exists for, not a coincidental
        // similarity to it.
        #expect(rootFactoryCallCount.count == 1)
        #expect(librarianRoot.forkCount == 2)
        #expect(mainSession.receivedPrompts[1].contains("declare function cities(args: { unused?: string }): { cities: string[] };"))
        #expect(mainSession.receivedPrompts[2].contains("declare function cities(args: { unused?: string }): { cities: string[] };"))
    }

    // MARK: - Malformed turns → bounded repair turns → failure

    @Test("a single malformed turn triggers one repair turn (the default budget) and then succeeds")
    func malformedTurnWithinBudgetRecovers() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let mainSession = ScriptedAgentSession([
            "I'm not sure what to do.",
            "ACTION: final\nANSWER: Recovered.",
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant."
        )

        let reply = try await agent.respond(to: "hello")

        #expect(reply == "Recovered.")
        // The repair instruction was fed back as the next turn's prompt.
        #expect(mainSession.receivedPrompts[1].contains("could not be parsed"))
    }

    @Test("malformed turns beyond the repair budget (default 1) fail the loop with a typed error")
    func malformedTurnsBeyondBudgetFailTheLoop() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let mainSession = ScriptedAgentSession([
            "still no action line",
            "still no action line either",
            "ACTION: final\nANSWER: too late",
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant."
        )

        await #expect(throws: MultiToolAgentError.self) {
            try await agent.respond(to: "hello")
        }
    }

    @Test(
        "the repair-turn budget is per-consecutive-failure: a malformed turn separated from another by a successful turn does not exhaust a budget of 1"
    )
    func repairBudgetResetsAfterASuccessfulTurn() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let mainSession = ScriptedAgentSession([
            "not a valid action",
            "ACTION: runCode\nCODE:\n```js\nreturn 1;\n```",
            "still not a valid action",
            "ACTION: final\nANSWER: done",
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant."
        )

        let reply = try await agent.respond(to: "hello")

        #expect(reply == "done")
        #expect(mainSession.callCount == 4)
    }

    @Test("a configured repair-turn budget of 0 fails the loop on the first malformed turn")
    func zeroRepairBudgetFailsImmediately() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let mainSession = ScriptedAgentSession(["not a valid action"])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant.",
            turnFormat: .tolerantParse(maxRepairTurns: 0)
        )

        await #expect(throws: MultiToolAgentError.self) {
            try await agent.respond(to: "hello")
        }
    }

    // MARK: - runCode error is fed back; a corrected snippet succeeds

    @Test("a runCode error is fed back to the model, and a corrected second snippet succeeds")
    func runCodeErrorIsFedBackAndCorrectedSnippetSucceeds() async throws {
        let registry = try MultiTool.Builder().addTool(TempTool()).buildRegistry()
        let mainSession = ScriptedAgentSession([
            "ACTION: runCode\nCODE:\n```js\nreturn tools.temp({}).tempC;\n```",
            "ACTION: runCode\nCODE:\n```js\nreturn tools.temp({ city: 'AAA' }).tempC;\n```",
            "ACTION: final\nANSWER: 11 degrees.",
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant."
        )

        let reply = try await agent.respond(to: "What's the temperature?")

        #expect(reply == "11 degrees.")
        // The first (broken) call's repairable error was fed back verbatim.
        #expect(mainSession.receivedPrompts[1].contains("Fix the snippet and call runCode again."))
        // The second (corrected) call's result was fed back before the final turn.
        #expect(mainSession.receivedPrompts[2].contains("11"))
    }

    // MARK: - max-turns termination

    @Test("the loop terminates at max-turns with a typed error, never spinning past it")
    func loopTerminatesAtMaxTurns() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        // Always a well-formed runCode turn, never a `final` — an unbounded
        // real model could spin forever on this; the agent must not.
        let neverEndingResponse = "ACTION: runCode\nCODE:\n```js\nreturn 1;\n```"
        let mainSession = ScriptedAgentSession(Array(repeating: neverEndingResponse, count: 10))
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant.",
            maxTurns: 3
        )

        await #expect(
            throws: MultiToolAgentError.maxTurnsExceeded(turns: 3)
        ) {
            try await agent.respond(to: "hello")
        }
        #expect(mainSession.callCount == 3)
    }

    // MARK: - directMode: findAPIs is rejected, not dispatched

    @Test("directMode rejects a findAPIs step from the model with an instructive message, without crashing")
    func directModeRejectsFindApisInstructively() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry().directMode()
        let mainSession = ScriptedAgentSession([
            "ACTION: findAPIs\nTASK: find city tools",
            "ACTION: final\nANSWER: done without findAPIs",
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant."
        )

        let reply = try await agent.respond(to: "hello")

        #expect(reply == "done without findAPIs")
        #expect(mainSession.receivedPrompts[1].contains("findAPIs is not available"))
        #expect(mainSession.receivedPrompts[1].contains("direct mode"))
    }

    @Test("a non-direct-mode registry with no librarian configured also rejects findAPIs instructively")
    func noLibrarianRejectsFindApisInstructively() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let mainSession = ScriptedAgentSession([
            "ACTION: findAPIs\nTASK: find city tools",
            "ACTION: final\nANSWER: done without a librarian",
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant."
        )

        let reply = try await agent.respond(to: "hello")

        #expect(reply == "done without a librarian")
        #expect(mainSession.receivedPrompts[1].contains("findAPIs is not available"))
        #expect(mainSession.receivedPrompts[1].contains("no librarian is configured"))
    }

    // MARK: - The turn-strategy seam: a second conformer, no loop changes

    @Test("a second TurnFormat conformer (AlwaysFinalTurnFormat) drives the same loop with no changes to it")
    func secondTurnFormatConformerDrivesTheLoop() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let mainSession = ScriptedAgentSession(["anything at all is treated as final"])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant.",
            turnFormat: AlwaysFinalTurnFormat()
        )

        let reply = try await agent.respond(to: "hello")

        #expect(reply == "anything at all is treated as final")
    }
}
