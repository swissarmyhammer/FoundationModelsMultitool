import FoundationModelsMetadataRegistry
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Coverage for `SampleSnippet` — the generation-and-repair loop `searchTools`
/// runs to come back with code rather than only signatures.
///
/// Every case drives a `ScriptedLanguageModel`, so the loop is exercised with
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

    /// Builds a config over `model`.
    ///
    /// - Parameter model: the scripted model every turn goes to.
    /// - Returns: the config to hand `SampleSnippet.generate`.
    static func config(over model: ScriptedLanguageModel) -> SampleSnippetConfig {
        SampleSnippetConfig(model: model, interpreter: JSCInterpreter())
    }

    /// `reply` once for each attempt the loop makes by default, so a reply the
    /// gate rejects is answered again on each retry and the script does not
    /// run out.
    ///
    /// - Parameter reply: the canned generator reply.
    /// - Returns: `reply`, ``SampleSnippetConfig/defaultAttemptLimit`` times.
    static func everyAttempt(_ reply: String) -> [String] {
        Array(repeating: reply, count: SampleSnippetConfig.defaultAttemptLimit)
    }

    /// Runs the loop over a model scripted with `replies`.
    ///
    /// - Parameter replies: one canned generator reply per expected turn.
    /// - Returns: the accepted snippet (or `nil`) and the calls the model
    ///   received, in turn order.
    static func generate(replies: [String]) async throws -> (sample: String?, calls: [ScriptedModelCall]) {
        let model = ScriptedLanguageModel(replies)
        let sample = try await SampleSnippet.generate(
            forTask: "the current temperature where the trip goes",
            over: try entries(),
            using: config(over: model)
        )
        return (sample, model.calls)
    }

    // MARK: - The accepting path

    @Test("a snippet that clears every gate is returned as written, on the first turn")
    func validatedSampleIsReturnedOnTheFirstTurn() async throws {
        let (sample, calls) = try await Self.generate(replies: [Self.goodSnippet])

        #expect(calls.count == 1)
        #expect(sample?.contains("await tools.getCities({})") == true)
        #expect(sample?.contains("```") == false)
        #expect(calls[0].prompt?.contains("the current temperature where the trip goes") == true)
    }

    @Test("the generation session is opened with the matched signature blocks and the one-fenced-block envelope")
    func instructionsCarryTheMatchedBlocksAndTheEnvelope() async throws {
        let entries = try Self.entries()
        let model = ScriptedLanguageModel([Self.goodSnippet])

        _ = try await SampleSnippet.generate(forTask: "a temperature", over: entries, using: Self.config(over: model))

        let opened = try #require(model.calls.first?.instructions)
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

    @Test("a reply with no fenced code block feeds back a fence demand and retries in the same session")
    func missingFenceFeedsBackAndRetries() async throws {
        let (sample, calls) = try await Self.generate(
            replies: ["Sure! I will call getCities and then getTemperature.", Self.goodSnippet]
        )

        #expect(calls.count == 2)
        #expect(calls[1].prompt?.contains("no fenced code block") == true)
        // The repair turn goes to the same session: its transcript holds the
        // opening prompt before the feedback.
        #expect(calls[1].prompts.count == 2)
        #expect(calls[1].prompts.first == calls[0].prompt)
        #expect(sample?.contains("await tools.getTemperature") == true)
    }

    @Test("a snippet that does not parse feeds back the engine's own message and retries")
    func syntaxErrorFeedsBackTheEngineMessage() async throws {
        let (sample, calls) = try await Self.generate(
            replies: ["```js\nconst x = await tools.getCities({});\nreturn x +;\n```", Self.goodSnippet]
        )

        #expect(calls.count == 2)
        let feedback = try #require(calls[1].prompt)
        #expect(feedback.contains("does not parse"))
        // The engine's message, not a paraphrase of it.
        #expect(feedback.contains("Unexpected token"))
        #expect(sample?.contains("await tools.getTemperature") == true)
    }

    @Test("a snippet naming an invented path feeds back the paths that do exist and retries")
    func unknownPathFeedsBackTheRealPaths() async throws {
        let (sample, calls) = try await Self.generate(
            replies: ["```js\nreturn await tools.getItinerary({});\n```", Self.goodSnippet]
        )

        #expect(calls.count == 2)
        let feedback = try #require(calls[1].prompt)
        #expect(feedback.contains("tools.getItinerary"))
        #expect(feedback.contains(UnknownToolHint.missingPathPhrase))
        #expect(feedback.contains("tools.getCities"))
        #expect(feedback.contains("tools.getTemperature"))
        #expect(sample != nil)
    }

    @Test("a snippet naming a real catalog path outside the matched set is rejected too")
    func pathOutsideTheMatchedSetIsRejected() async throws {
        // `getTemperature` exists in the catalog but is not one of the matched
        // entries handed to the gate, so the sample may not name it.
        let matched = try #require(try Self.entries().first { $0.path == "getCities" })
        // One rejected reply for each attempt: an exhausted script throws, and
        // a session error now propagates instead of yielding `nil`.
        let model = ScriptedLanguageModel(Self.everyAttempt(
            "```js\nreturn await tools.getTemperature({ city: \"PDX\" });\n```"))

        let sample = try await SampleSnippet.generate(
            forTask: "a temperature", over: [matched], using: Self.config(over: model))

        #expect(sample == nil)
        let feedback = try #require(model.calls.last?.prompt)
        #expect(feedback.contains("tools.getTemperature"))
        #expect(feedback.contains("tools.getCities"))
    }

    @Test("a snippet that throws against the typed mocks feeds back the thrown message and retries")
    func dryRunFailureFeedsBackTheThrownMessage() async throws {
        let (sample, calls) = try await Self.generate(
            replies: ["```js\nconst trip = await tools.getCities({});\nreturn trip.itinerary;\n```", Self.goodSnippet]
        )

        #expect(calls.count == 2)
        let feedback = try #require(calls[1].prompt)
        #expect(feedback.contains("declared signatures"))
        #expect(feedback.contains("itinerary"))
        #expect(feedback.contains("{ cities: string[] }"))
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
            let (_, calls) = try await Self.generate(replies: Self.everyAttempt(reply))
            let feedback = try #require(calls.last?.prompt)
            leads.insert(String(feedback.prefix(while: { $0 != "." })))
        }
        #expect(leads.count == 4)
    }

    // MARK: - Never blocking discovery

    @Test("an always-failing generator gives up at the attempt limit instead of looping")
    func alwaysFailingGeneratorGivesUpAtTheAttemptLimit() async throws {
        let noFence = "I cannot write that."
        let (sample, calls) = try await Self.generate(replies: [noFence, noFence, noFence, noFence, noFence])

        #expect(sample == nil)
        #expect(calls.count == 3)
    }

    @Test("a generator that throws propagates its error, so the caller can show it")
    func throwingGeneratorPropagatesItsError() async throws {
        // An empty script throws on the very first turn.
        await #expect(throws: ScriptedLanguageModelError.unscripted(answerCount: 0)) {
            try await Self.generate(replies: [])
        }
    }

    @Test("a generator that Router refuses on the model of the calling session propagates that refusal")
    func refusedGeneratorPropagatesTheRefusal() async throws {
        let refusal = GenerationQueueError.waitInsideOpenSubmission(model: "stub/standard")
        let model = ScriptedLanguageModel(answers: [.failure(refusal)])

        await #expect(throws: refusal) {
            try await SampleSnippet.generate(
                forTask: "a temperature", over: try Self.entries(), using: Self.config(over: model))
        }
    }

    @Test("no matched entries means no sample, and the model gets no call at all")
    func noMatchedEntriesPromptsNoModel() async throws {
        let model = ScriptedLanguageModel([Self.goodSnippet])

        let sample = try await SampleSnippet.generate(forTask: "anything", over: [], using: Self.config(over: model))

        #expect(sample == nil)
        #expect(model.calls.isEmpty)
    }
}
