import FoundationModelsMetadataRegistry
import Testing
import os

@testable import FoundationModelsMultitool

/// Coverage for `SampleSnippet` — the generation-and-repair loop `findAPIs`
/// runs to come back with code rather than only signatures.
///
/// Every case drives a `ScriptedAgentSession`, so the loop is exercised with
/// zero GPU: the fixture decides exactly what the generator "writes", and the
/// assertions are about which failure the gate detected, what it fed back, and
/// when it gave up.
@Suite("SampleSnippet")
struct SampleSnippetTests {
    /// A snippet that passes every gate against the shared catalog below.
    static let goodSnippet = """
        ```js
        const trip = await tools.getCities({});
        const temp = await tools.getTemperature({ city: trip.cities[0] });
        return temp.tempC;
        ```
        """

    /// The catalog the gate checks a candidate against.
    static func entries() throws -> [APISurface.Entry] {
        try MultiTool.Builder()
            .addTool(CitiesTool())
            .addTool(TempTool())
            .build()
            .entries
    }

    /// Builds a config over `session`, recording every instruction string the
    /// loop opened a session with.
    ///
    /// - Parameters:
    ///   - session: the scripted session every call is routed to.
    ///   - instructions: receives the instructions the loop passed.
    /// - Returns: the config to hand `SampleSnippet.generate`.
    static func config(
        over session: any AgentSession,
        recordingInstructionsTo instructions: OSAllocatedUnfairLock<[String]>
    ) -> SampleSnippetConfig {
        SampleSnippetConfig(
            makeSession: { opened in
                instructions.withLock { $0.append(opened) }
                return session
            },
            interpreter: JSCInterpreter(timeLimit: 5.0)
        )
    }

    /// Runs the loop over a session scripted with `replies`.
    ///
    /// - Parameter replies: one canned generator reply per expected turn.
    /// - Returns: the accepted snippet (or `nil`) and the prompts the session
    ///   received, in turn order.
    static func generate(replies: [String]) async throws -> (sample: String?, prompts: [String]) {
        let session = ScriptedAgentSession(replies)
        let instructions = OSAllocatedUnfairLock<[String]>(initialState: [])
        let sample = await SampleSnippet.generate(
            forTask: "the current temperature where the trip goes",
            over: try entries(),
            using: config(over: session, recordingInstructionsTo: instructions)
        )
        return (sample, session.receivedPrompts)
    }

    // MARK: - The accepting path

    @Test("a snippet that clears every gate is returned as written, on the first turn")
    func validatedSampleIsReturnedOnTheFirstTurn() async throws {
        let (sample, prompts) = try await Self.generate(replies: [Self.goodSnippet])

        #expect(prompts.count == 1)
        #expect(sample?.contains("await tools.getCities({})") == true)
        #expect(sample?.contains("```") == false)
        #expect(prompts[0].contains("the current temperature where the trip goes"))
    }

    @Test("the generation session is opened with the matched signature blocks and the one-fenced-block envelope")
    func instructionsCarryTheMatchedBlocksAndTheEnvelope() async throws {
        let entries = try Self.entries()
        let session = ScriptedAgentSession([Self.goodSnippet])
        let instructions = OSAllocatedUnfairLock<[String]>(initialState: [])

        _ = await SampleSnippet.generate(
            forTask: "a temperature",
            over: entries,
            using: Self.config(over: session, recordingInstructionsTo: instructions)
        )

        let opened = try #require(instructions.withLock { $0.first })
        for entry in entries {
            #expect(opened.contains(entry.block))
        }
        #expect(opened.contains("one fenced code block"))
        #expect(opened.contains("tools.*"))
        // The JavaScript licence is explicit: the functions fetch data, the code
        // around them does the work. An earlier draft said "Call only the tools.*
        // paths listed above", which reads as restricting the snippet to tool calls
        // rather than restricting which paths are callable.
        #expect(opened.contains("Write whatever JavaScript the task needs"))
        #expect(opened.contains("The functions fetch data"))
        #expect(!opened.contains("Call only the tools.* paths listed above"))
        // Each rule carries its mechanical consequence, which is what the dry run
        // actually enforces.
        #expect(opened.contains("comes back as an error, not as data"))
        #expect(opened.contains("without it you hold a promise, not a value"))
        #expect(opened.contains("reading any other field is an error")
            || opened.contains("reading any other field \\\n        is an error"))
    }

    // MARK: - The four failure kinds, each fed back into the same session

    @Test("a reply with no fenced code block feeds back a fence demand and retries")
    func missingFenceFeedsBackAndRetries() async throws {
        let (sample, prompts) = try await Self.generate(
            replies: ["Sure! I will call getCities and then getTemperature.", Self.goodSnippet]
        )

        #expect(prompts.count == 2)
        #expect(prompts[1].contains("no fenced code block"))
        #expect(sample?.contains("await tools.getTemperature") == true)
    }

    @Test("a snippet that does not parse feeds back the engine's own message and retries")
    func syntaxErrorFeedsBackTheEngineMessage() async throws {
        let (sample, prompts) = try await Self.generate(
            replies: ["```js\nconst x = await tools.getCities({});\nreturn x +;\n```", Self.goodSnippet]
        )

        #expect(prompts.count == 2)
        #expect(prompts[1].contains("does not parse"))
        // The engine's message, not a paraphrase of it.
        #expect(prompts[1].contains("Unexpected token"))
        #expect(sample?.contains("await tools.getTemperature") == true)
    }

    @Test("a snippet naming an invented path feeds back the paths that do exist and retries")
    func unknownPathFeedsBackTheRealPaths() async throws {
        let (sample, prompts) = try await Self.generate(
            replies: ["```js\nreturn await tools.getItinerary({});\n```", Self.goodSnippet]
        )

        #expect(prompts.count == 2)
        #expect(prompts[1].contains("tools.getItinerary"))
        #expect(prompts[1].contains("does not exist"))
        #expect(prompts[1].contains("tools.getCities"))
        #expect(prompts[1].contains("tools.getTemperature"))
        #expect(sample != nil)
    }

    @Test("a snippet naming a real catalog path outside the matched set is rejected too")
    func pathOutsideTheMatchedSetIsRejected() async throws {
        // `getTemperature` exists in the catalog but is not one of the matched
        // entries handed to the gate, so the sample may not name it.
        let matched = try #require(try Self.entries().first { $0.path == "getCities" })
        let session = ScriptedAgentSession(["```js\nreturn await tools.getTemperature({ city: \"PDX\" });\n```"])
        let instructions = OSAllocatedUnfairLock<[String]>(initialState: [])

        let sample = await SampleSnippet.generate(
            forTask: "a temperature",
            over: [matched],
            using: Self.config(over: session, recordingInstructionsTo: instructions)
        )

        #expect(sample == nil)
        let feedback = try #require(session.receivedPrompts.last)
        #expect(feedback.contains("tools.getTemperature"))
        #expect(feedback.contains("tools.getCities"))
    }

    @Test("a snippet that throws against the typed mocks feeds back the thrown message and retries")
    func dryRunFailureFeedsBackTheThrownMessage() async throws {
        let (sample, prompts) = try await Self.generate(
            replies: ["```js\nconst trip = await tools.getCities({});\nreturn trip.itinerary;\n```", Self.goodSnippet]
        )

        #expect(prompts.count == 2)
        #expect(prompts[1].contains("declared signatures"))
        #expect(prompts[1].contains("itinerary"))
        #expect(prompts[1].contains("{ cities: string[] }"))
        #expect(sample?.contains("await tools.getTemperature") == true)
    }

    @Test("the four feedback messages are distinct, so each failure kind is legible on its own")
    func theFourFeedbackMessagesAreDistinct() async throws {
        let failing = [
            "no fence at all",
            "```js\nreturn x +;\n```",
            "```js\nreturn await tools.getItinerary({});\n```",
            "```js\nconst trip = await tools.getCities({});\nreturn trip.itinerary;\n```",
        ]
        var leads: Set<String> = []
        for reply in failing {
            let (_, prompts) = try await Self.generate(replies: [reply])
            let feedback = try #require(prompts.last)
            leads.insert(String(feedback.prefix(while: { $0 != "." })))
        }
        #expect(leads.count == 4)
    }

    // MARK: - Never blocking discovery

    @Test("an always-failing generator gives up at the attempt limit instead of looping")
    func alwaysFailingGeneratorGivesUpAtTheAttemptLimit() async throws {
        let noFence = "I cannot write that."
        let (sample, prompts) = try await Self.generate(replies: [noFence, noFence, noFence, noFence, noFence])

        #expect(sample == nil)
        #expect(prompts.count == 3)
    }

    @Test("a generator that throws yields no sample rather than propagating")
    func throwingGeneratorYieldsNoSample() async throws {
        // An empty script throws on the very first `respond(to:)`.
        let (sample, prompts) = try await Self.generate(replies: [])

        #expect(sample == nil)
        #expect(prompts.count == 1)
    }

    @Test("no matched entries means no sample, and no session is opened at all")
    func noMatchedEntriesOpensNoSession() async throws {
        let session = ScriptedAgentSession([Self.goodSnippet])
        let instructions = OSAllocatedUnfairLock<[String]>(initialState: [])

        let sample = await SampleSnippet.generate(
            forTask: "anything",
            over: [],
            using: Self.config(over: session, recordingInstructionsTo: instructions)
        )

        #expect(sample == nil)
        #expect(instructions.withLock { $0.isEmpty })
        #expect(session.callCount == 0)
    }
}
