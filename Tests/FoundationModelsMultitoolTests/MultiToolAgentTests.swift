import FoundationModels
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
    func dispatchesFindAPIsThenRunCodeThenFinal() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let mainSession = ScriptedAgentSession([
            "ACTION: findAPIs\nTASK: list the trip cities",
            "ACTION: runCode\nCODE:\n```js\nreturn tools.cities().cities.length;\n```",
            "ACTION: final\nANSWER: There are 3 cities.",
        ])
        let librarianSession = ScriptedAgentSession([
            "declare function cities(): { cities: string[] };"
        ])
        let agent = MultiToolAgent(
            registry,
            session: mainSession,
            librarianSession: librarianSession,
            instructions: "You are a travel assistant."
        )

        let reply = try await agent.respond(to: "How many cities are on my trip?")

        #expect(reply == "There are 3 cities.")
        #expect(mainSession.callCount == 3)
        // The librarian saw the plain-language task, not a re-rendered surface
        // (the surface is already baked into its own session instructions).
        #expect(librarianSession.receivedPrompts == ["list the trip cities"])
        // findAPIs's result was spliced back in as the next turn's context.
        #expect(mainSession.receivedPrompts[1].contains("declare function cities()"))
        // The runCode result (3, the cities count) was fed back before the final turn.
        #expect(mainSession.receivedPrompts[2].contains("3"))
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
            registry,
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
            registry,
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
            registry,
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
            registry,
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
            registry,
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
            registry,
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
    func directModeRejectsFindAPIsInstructively() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry().directMode()
        let mainSession = ScriptedAgentSession([
            "ACTION: findAPIs\nTASK: find city tools",
            "ACTION: final\nANSWER: done without findAPIs",
        ])
        let agent = MultiToolAgent(
            registry,
            session: mainSession,
            instructions: "You are a travel assistant."
        )

        let reply = try await agent.respond(to: "hello")

        #expect(reply == "done without findAPIs")
        #expect(mainSession.receivedPrompts[1].contains("findAPIs is not available"))
        #expect(mainSession.receivedPrompts[1].contains("direct mode"))
    }

    @Test("a non-direct-mode registry with no librarian configured also rejects findAPIs instructively")
    func noLibrarianRejectsFindAPIsInstructively() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let mainSession = ScriptedAgentSession([
            "ACTION: findAPIs\nTASK: find city tools",
            "ACTION: final\nANSWER: done without a librarian",
        ])
        let agent = MultiToolAgent(
            registry,
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
            registry,
            session: mainSession,
            instructions: "You are a travel assistant.",
            turnFormat: AlwaysFinalTurnFormat()
        )

        let reply = try await agent.respond(to: "hello")

        #expect(reply == "anything at all is treated as final")
    }
}
