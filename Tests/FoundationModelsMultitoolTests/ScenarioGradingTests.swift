import Testing

// `@testable`: `SubmissionID` (Router) has an internal initializer only, and
// a scripted submission chain needs it.
@testable import FoundationModelsExtras
@testable import FoundationModelsMultitool
@testable import FoundationModelsRouter
import ScenarioGrading

/// Ungated coverage for the verdicts a gated scenario is graded on —
/// `scenarioChecks(for:answerContainsOneOf:answerMustNotContain:readingContainsOneOf:groundedIn:)`
/// `mailCollectionChecks(for:answerContainsOneOf:groundedIn:)` and
/// `nestedGenerationChecks(for:)` in `Support/ScenarioRunner.swift` — and for
/// `SubmissionLog.fold(outputs:)`, which gives those runners each answer of a
/// session from its output, by the mail id of the answer.
///
/// The grounding condition used to hold whenever *any* fixture call returned,
/// which is a weaker question than the one a scenario asks. Recorded on task
/// `0981ar3`, run 2 of the session-rule arm: the discovery scenario passed on a
/// run that fetched the itinerary, never fetched a temperature, and then named
/// the warmest city — an answer no run without a reading can know. The city
/// names alone satisfied "something returned".
///
/// So each scenario now declares what its answer depends on
/// (`IntegrationScenarioGrounding`), and this suite is where that declaration
/// is shown to discriminate: the recorded run is rebuilt from the fixtures and
/// must now fail, and a run that genuinely read the readings must still pass.
/// Both runs drive the real `MultiTool` a host mounts, so the log they are
/// graded on is written by the same `call(arguments:)` path a gated run takes.
///
/// Model-free on purpose, and for the same reason `ScenarioFixtureTests` is:
/// the grade itself only ever runs against a real model on capable hardware, so
/// a grading rule nobody can check without weights and a GPU is a rule that
/// rots — and this one rotted unnoticed while the arms recorded on task
/// `tkrdwb8` were measured against it. This suite rebuilds those runs from the
/// fixtures, so it answers on any box that runs
/// `swift test --package-path IntegrationTests`.
@Suite("Gated-scenario grading")
struct ScenarioGradingTests {
    // MARK: - The recorded false pass

    @Test("a run that fetched only the itinerary is not grounded, whichever city it names")
    func aTripOnlyRunThatNamesTheWarmestCityIsNotGrounded() async throws {
        let log = ScenarioCallLog()
        // The recorded shape: one snippet, one call, the city list and nothing
        // else. Written from the trip fixture's own path, so it cannot drift
        // into naming a function the mounted surface does not define.
        _ = try await Self.runComposeSnippet("return (await tools.\(IntegrationTripTool.path)()).cities;", log: log)
        #expect(await log.returnedPaths == [IntegrationTripTool.path])

        let checks = await Self.warmestCityChecks(
            reply: Self.replyNamingTheWarmestCity, typedPaths: [IntegrationTripTool.path], log: log)

        // The reply names the fixture's warmest city, so the answer's *form* is
        // valid — which is exactly why this run used to pass outright.
        let validAnswer = try Self.check(validAnswerCheckName, in: checks)
        #expect(validAnswer.held)
        // And it is not grounded: the reading the question turns on was never
        // fetched, so naming the right city was luck.
        let grounded = try Self.check(groundedCheckName, in: checks)
        #expect(!grounded.held)
    }

    // MARK: - The still-passes control

    @Test("a run that read the trip's readings is grounded")
    func aRunThatReadsEveryTripReadingIsGrounded() async throws {
        let log = ScenarioCallLog()
        try await Self.readEveryTripReading(into: log)
        #expect(await log.returnedPaths == IntegrationScenarioGrounding.warmestCity)

        let checks = await Self.warmestCityChecks(
            reply: Self.replyNamingTheWarmestCityAndItsReading,
            typedPaths: [IntegrationTripTool.path, IntegrationWeatherTool.path],
            log: log
        )

        let grounded = try Self.check(groundedCheckName, in: checks)
        #expect(grounded.held)
        // Nothing else broke either: the corrected rule is stricter about one
        // thing, not about everything.
        let failed = checks.filter { !$0.held }.map(\.name)
        #expect(failed.isEmpty)
    }

    // MARK: - The reading the reply states

    @Test("a grounded reply that names the warmest city without its reading fails readingReported alone")
    func aReplyWithoutTheReadingFailsReadingReportedAlone() async throws {
        // The discovery scenario also asks how warm the warmest city is, which
        // is the check the single-call weather scenario made before card
        // `^3vtvrzg` merged it: the reply states the reading `getWeather`
        // returned. A grounded run whose reply names only the city fails on
        // that condition and on nothing else.
        let log = ScenarioCallLog()
        try await Self.readEveryTripReading(into: log)

        let checks = await Self.warmestCityChecks(
            reply: Self.replyNamingTheWarmestCity,
            typedPaths: [IntegrationTripTool.path, IntegrationWeatherTool.path],
            log: log
        )

        let failed = checks.filter { !$0.held }.map(\.name)
        #expect(failed == [readingReportedCheckName])
    }

    @Test("a scenario that names no reading gets no readingReported check")
    func noReadingAddsNoReadingCheck() {
        // An empty list adds no check rather than a check that cannot fail, the
        // same rule `answerMustNotContain` follows.
        let checks = scenarioChecks(
            for: ScenarioEvidence(
                answer: Self.replyNamingTheWarmestCity,
                typedPaths: [],
                invokedPaths: [],
                returnedPaths: IntegrationScenarioGrounding.warmestCity
            ),
            answerContainsOneOf: IntegrationScenarioAnswers.warmestCity,
            answerMustNotContain: [],
            readingContainsOneOf: [],
            groundedIn: IntegrationScenarioGrounding.warmestCity
        )

        #expect(!checks.contains { $0.name == readingReportedCheckName })
    }

    // MARK: - Every scenario declares something

    @Test("every gated scenario declares a non-empty dependency for its answer")
    func everyScenarioDeclaresWhatItsAnswerDependsOn() {
        // An empty declaration would grade every run as grounded, including one
        // that called nothing at all — the vacuous pass `scenarioChecks`
        // refuses, but only once a gated run reaches it.
        #expect(!IntegrationScenarioGrounding.warmestCity.isEmpty)
        #expect(!IntegrationScenarioGrounding.booking.isEmpty)
        #expect(!IntegrationScenarioGrounding.delayedEcho.isEmpty)
    }

    // MARK: - The mail collection canary's verdict

    @Test("a run whose settled result came back as mail and started the answer passes every canary condition")
    func aMailAnswerPassesEveryCanaryCondition() {
        // The shape the contract asks for: a runCode call handed back a
        // pending envelope, the model ended its answer with the echo still
        // going, the settled run came back as mail, and the answer mail started
        // carried the value, with no background run left when that answer
        // ended.
        let nonce = integrationDelayedEchoNonce()
        let checks = Self.canaryChecks(
            for: MailCollectionEvidence(
                answer: Self.replyReportingTheEcho(of: nonce),
                returnedPaths: IntegrationScenarioGrounding.delayedEcho,
                pendingEnvelopes: 1,
                mailAnswers: 1,
                backgroundRunsAtLastAnswer: []
            ),
            nonce: nonce
        )

        let failed = checks.filter { !$0.held }.map(\.name)
        #expect(failed.isEmpty)
    }

    @Test("a run where no runCode call handed back a pending envelope fails the canary on pendingEnvelope alone")
    func noPendingEnvelopeFailsTheCanary() {
        // The check the background-in-code-mode scenario made before card
        // `^3vtvrzg` merged it into the canary: some tool output of the answer
        // was the rendered pending envelope. A run that got its value some
        // other way fails on that condition and on nothing else.
        let nonce = integrationDelayedEchoNonce()
        let checks = Self.canaryChecks(
            for: MailCollectionEvidence(
                answer: Self.replyReportingTheEcho(of: nonce),
                returnedPaths: IntegrationScenarioGrounding.delayedEcho,
                pendingEnvelopes: 0,
                mailAnswers: 1,
                backgroundRunsAtLastAnswer: []
            ),
            nonce: nonce
        )

        let failed = checks.filter { !$0.held }.map(\.name)
        #expect(failed == [pendingEnvelopeCheckName])
    }

    @Test("a run where no answer started from mail fails the canary on mailCollection alone")
    func noMailAnswerFailsTheCanary() throws {
        // The model held its answer open until the run settled, or the run
        // settled inside the inline settle grace. Either way no mail came, and
        // the canary has to say so, here where it can be checked without live
        // inference.
        let nonce = integrationDelayedEchoNonce()
        let checks = Self.canaryChecks(
            for: MailCollectionEvidence(
                answer: Self.replyReportingTheEcho(of: nonce),
                returnedPaths: IntegrationScenarioGrounding.delayedEcho,
                pendingEnvelopes: 1,
                mailAnswers: 0,
                backgroundRunsAtLastAnswer: []
            ),
            nonce: nonce
        )

        let mailCollection = try Self.check(mailCollectionCheckName, in: checks)
        #expect(!mailCollection.held)
        // And it fails on that condition alone: the reply is a valid, grounded
        // answer with no run left, so a reader of the failure knows the
        // delivery — not the model's answer — is what changed.
        let failed = checks.filter { !$0.held }.map(\.name)
        #expect(failed == [mailCollectionCheckName])
    }

    @Test("a run with a background run still going at the last answer fails noBackgroundRunsAtLastAnswer")
    func aRunStillRunningAtTheLastAnswerFailsTheCanary() throws {
        let nonce = integrationDelayedEchoNonce()
        let checks = Self.canaryChecks(
            for: MailCollectionEvidence(
                answer: Self.replyReportingTheEcho(of: nonce),
                returnedPaths: IntegrationScenarioGrounding.delayedEcho,
                pendingEnvelopes: 1,
                mailAnswers: 1,
                backgroundRunsAtLastAnswer: [IntegrationDelayedEchoTool.path]
            ),
            nonce: nonce
        )

        let failed = checks.filter { !$0.held }.map(\.name)
        #expect(failed == [noBackgroundRunsAtLastAnswerCheckName])
    }

    // MARK: - The nested-generation probe's verdict

    @Test("a nested call on the outer answer's own model that came back with a reply passes")
    func aNestedGenerationThatReturnedPassesTheProbe() {
        // The healthy reading since Router `505a03f3`: the lock is held over
        // the model call only, never over a tool call, so the tool body's
        // nested `respond` on the same model runs after the outer `respond`
        // returns, and completes.
        let checks = nestedGenerationChecks(
            for: NestedGenerationEvidence(
                answer: Self.replyReportingTheReadinessToken,
                enteredPaths: [integrationNestedGenerationPath],
                outcome: .returned
            )
        )

        let failed = checks.filter { !$0.held }.map(\.name)
        #expect(failed.isEmpty)
    }

    @Test("a run whose only tool was never called fails the probe rather than passing vacuously")
    func aRunThatCalledNothingFailsTheProbe() {
        // The shape that must never read as a verdict: the model answered
        // without calling the one tool mounted, so no nested call was made. A
        // probe that passed here would report a nested call for a run that
        // never tried.
        let checks = nestedGenerationChecks(
            for: NestedGenerationEvidence(
                answer: Self.replyReportingTheReadinessToken,
                enteredPaths: [],
                outcome: nil
            )
        )

        let failed = checks.filter { !$0.held }.map(\.name)
        #expect(failed == [nestedCallEnteredCheckName, nestedGenerationReturnedCheckName])
    }

    /// Each error is a nested call that did not complete: the old same-model
    /// refusal, the refusal Router still gives a wait for the tool's own
    /// session, and a cancellation.
    @Test(
        "a nested generation that threw fails the probe on the return",
        arguments: [
            "waitInsideOpenSubmission(model: \"stub/standard\")",
            "inBandWaitForOwnSession(sessionID: 01M5PVHJ217B1MXZWJ6GWKQEBH)",
            "CancellationError()",
        ]
    )
    func aNestedGenerationThatThrewFailsTheProbe(description: String) {
        let checks = nestedGenerationChecks(
            for: NestedGenerationEvidence(
                answer: "",
                enteredPaths: [integrationNestedGenerationPath],
                outcome: .threw(description: description)
            )
        )

        let failed = checks.filter { !$0.held }.map(\.name)
        #expect(failed == [nestedGenerationReturnedCheckName])
        let message = checks.first { $0.name == nestedGenerationReturnedCheckName }?.failureMessage
        #expect(message?.contains(description) == true)
    }

    // MARK: - The fold of the session events

    @Test("two submissions and one answered event fold to one answer with both submission ids")
    func twoSubmissionsFoldToOneAnswer() throws {
        let message = MailID()
        let first = SubmissionID(Self.firstSubmissionNumber)
        let continuation = SubmissionID(Self.secondSubmissionNumber)
        let firstUsage = TokenUsage(tokensIn: Self.firstTokensIn, tokensOut: Self.firstTokensOut, contextFill: 0)
        let answer = Self.answer(reply: Self.foldedReply, to: message)

        let records = SubmissionLog.fold(outputs: Self.outputs(of: message, [
            .submissionStarted(SubmissionStart(submissionId: first, mailIds: [message], cause: .message)),
            .textDelta(Self.foldedReply),
            .submissionEnded(SubmissionEnd(submissionId: first, usage: firstUsage, finishReason: .maxTokens)),
            .submissionStarted(
                SubmissionStart(submissionId: continuation, mailIds: [message], cause: .continuation)),
            .submissionEnded(SubmissionEnd(submissionId: continuation, usage: nil, finishReason: .completed)),
            .answered(answer),
        ]))

        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.origin == [message])
        #expect(record.answers(message))
        #expect(record.submissionIds == [first, continuation])
        #expect(record.submissions.map { $0.start?.cause } == [.message, .continuation])
        #expect(record.submissions.map { $0.start?.mailIds } == [[message], [message]])
        #expect(record.submissions.map { $0.end?.finishReason } == [.maxTokens, .completed])
        #expect(record.submissions.first?.end?.usage == firstUsage)
        #expect(record.cause == .message)
        #expect(record.outcome == .answered(answer))
        #expect(record.reply == Self.foldedReply)
    }

    @Test("an answerFailed event folds to a failed answer with no reply")
    func answerFailedFoldsToAFailedAnswer() throws {
        let message = MailID()
        let submission = SubmissionID(Self.firstSubmissionNumber)
        let failure = AnswerFailure(mailIds: [message], reason: .cancelled)

        let records = SubmissionLog.fold(outputs: Self.outputs(of: message, [
            .submissionStarted(SubmissionStart(submissionId: submission, mailIds: [message], cause: .message)),
            .submissionEnded(SubmissionEnd(submissionId: submission, usage: nil, finishReason: .completed)),
            .answerFailed(failure),
        ]))

        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.outcome == .failed(failure))
        #expect(record.reply == nil)
        #expect(record.submissionIds == [submission])
    }

    @Test("a repetitionStopped event is recorded on the answer it stopped")
    func repetitionStoppedIsRecorded() throws {
        let message = MailID()
        let submission = SubmissionID(Self.firstSubmissionNumber)
        let stop = RepetitionStop(
            generatedTokens: Self.stoppedGeneratedTokens,
            countedLines: Self.stoppedCountedLines,
            newLines: Self.stoppedNewLines,
            tokensWithoutNewLine: Self.stoppedTokensWithoutNewLine,
            detection: RepetitionDetection(),
            recovery: nil
        )

        let records = SubmissionLog.fold(outputs: Self.outputs(of: message, [
            .submissionStarted(SubmissionStart(submissionId: submission, mailIds: [message], cause: .mail)),
            .repetitionStopped(stop),
            .submissionEnded(SubmissionEnd(submissionId: submission, usage: nil, finishReason: .repeatedLines)),
            .answered(Self.answer(reply: Self.foldedReply, to: message)),
        ]))

        let record = try #require(records.first)
        #expect(record.repetitionStops == [stop])
        #expect(record.cause == .mail)
        #expect(record.submissions.first?.end?.finishReason == .repeatedLines)
    }

    @Test("a chain with no answered or answerFailed event is still open and folds to no answer")
    func anOpenChainFoldsToNoAnswer() {
        let message = MailID()
        let submission = SubmissionID(Self.firstSubmissionNumber)

        let records = SubmissionLog.fold(outputs: Self.outputs(of: message, [
            .submissionStarted(SubmissionStart(submissionId: submission, mailIds: [message], cause: .message))
        ]))

        #expect(records.isEmpty)
    }

    /// Two answers whose events mix in the output: the fold finds the chain of
    /// each event by its origin, so neither answer takes the submissions of
    /// the other, and an event that no mail started is in no answer.
    @Test("two answers whose events mix fold to two answers, each with its own submissions")
    func mixedAnswersFoldByOrigin() throws {
        let message = MailID()
        let runMail = MailID()
        let first = SubmissionID(Self.firstSubmissionNumber)
        let second = SubmissionID(Self.secondSubmissionNumber)
        let messageAnswer = Self.answer(reply: Self.foldedReply, to: message)
        let runMailAnswer = Self.answer(reply: Self.otherReply, to: runMail)

        let outputs = [
            SessionOutput(
                origin: .mail([message]),
                event: .submissionStarted(SubmissionStart(submissionId: first, mailIds: [message], cause: .message))),
            SessionOutput(
                origin: .mail([runMail]),
                event: .submissionStarted(SubmissionStart(submissionId: second, mailIds: [runMail], cause: .mail))),
            SessionOutput(
                origin: .system,
                event: .submissionEnded(SubmissionEnd(submissionId: first, usage: nil, finishReason: .completed))),
            SessionOutput(
                origin: .mail([runMail]),
                event: .submissionEnded(SubmissionEnd(submissionId: second, usage: nil, finishReason: .completed))),
            SessionOutput(origin: .mail([runMail]), event: .answered(runMailAnswer)),
            SessionOutput(
                origin: .mail([message]),
                event: .submissionEnded(SubmissionEnd(submissionId: first, usage: nil, finishReason: .maxTokens))),
            SessionOutput(origin: .mail([message]), event: .answered(messageAnswer)),
        ]

        #expect(SubmissionLog.fold(outputs: outputs).count == 2)
        let forRunMail = try #require(SubmissionLog.answer(to: runMail, in: outputs))
        let forMessage = try #require(SubmissionLog.answer(to: message, in: outputs))
        #expect(forRunMail.submissionIds == [second])
        #expect(forRunMail.cause == .mail)
        #expect(forRunMail.reply == Self.otherReply)
        #expect(forMessage.submissionIds == [first])
        #expect(forMessage.submissions.first?.end?.finishReason == .maxTokens)
        #expect(forMessage.reply == Self.foldedReply)
    }

    @Test("only answered and answerFailed of the chain of the mail end its answer")
    func onlyTheTwoFinalEventsEndAChain() {
        let message = MailID()
        let other = MailID()
        let submission = SubmissionID(Self.firstSubmissionNumber)
        let ofMessage = { (event: SessionEvent) in SessionOutput(origin: .mail([message]), event: event) }

        #expect(
            SubmissionLog.endsAnswer(ofMessage(.answered(Self.answer(reply: Self.foldedReply, to: message))), of: message))
        #expect(
            SubmissionLog.endsAnswer(
                ofMessage(.answerFailed(AnswerFailure(mailIds: [message], reason: .cancelled))), of: message))
        #expect(
            !SubmissionLog.endsAnswer(
                ofMessage(.submissionEnded(SubmissionEnd(submissionId: submission, usage: nil, finishReason: .completed))),
                of: message))
        #expect(!SubmissionLog.endsAnswer(ofMessage(.textDelta(Self.foldedReply)), of: message))
        #expect(
            !SubmissionLog.endsAnswer(
                SessionOutput(origin: .mail([other]), event: .answered(Self.answer(reply: Self.otherReply, to: other))),
                of: message))
    }

    // MARK: - Building the graded evidence

    /// Grades one canary record against the gated scenario's own answers and
    /// declared grounding.
    ///
    /// The accepted answer is the nonce of the run and the grounding comes from
    /// the fixtures, exactly as the gated canary grades its own run, so this
    /// grades the same contract the gated suite does rather than a copy of it.
    ///
    /// - Parameters:
    ///   - evidence: the record to grade.
    ///   - nonce: the value the scripted run gave the delayed echo.
    /// - Returns: every graded condition, in reporting order.
    private static func canaryChecks(for evidence: MailCollectionEvidence, nonce: String) -> [ScenarioCheck] {
        mailCollectionChecks(
            for: evidence,
            answerContainsOneOf: [nonce],
            groundedIn: IntegrationScenarioGrounding.delayedEcho
        )
    }

    /// The reply each canary record is graded on: a mail answer reporting the
    /// value the delayed echo returned, in the recorded shape of CI run
    /// `36951032341`.
    ///
    /// - Parameter nonce: the value the scripted run gave the delayed echo.
    /// - Returns: the reply.
    private static func replyReportingTheEcho(of nonce: String) -> String {
        "The call settled. `\(IntegrationDelayedEchoTool.path)` returned exactly: \(nonce)"
    }

    /// The reply the nested-generation probe's records are graded on: an answer
    /// reporting the readiness token.
    ///
    /// Rebuilt from the fixture rather than quoted, for
    /// ``replyNamingTheWarmestCity``'s reason. The probe's verdict never reads
    /// the reply — it grades the call log and the nested outcome — so this is
    /// here to keep each record a whole run rather than to be asserted on.
    private static var replyReportingTheReadinessToken: String {
        "Your model is responsive. Readiness token: \(integrationNestedGenerationToken)"
    }

    /// Runs one snippet against the compose scenario's own two fixture tools.
    ///
    /// - Parameters:
    ///   - code: the snippet to run.
    ///   - log: the run's call log, which both fixtures record into.
    /// - Returns: the rendered `runCode` output.
    /// - Throws: whatever building the registry or calling `MultiTool` throws.
    private static func runComposeSnippet(_ code: String, log: ScenarioCallLog) async throws -> String {
        let registry = try MultiTool.Builder()
            .addTools([IntegrationTripTool(log: log), IntegrationWeatherTool(log: log)])
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    /// Runs the walk the discovery question needs: the itinerary, then a
    /// reading for each city it lists.
    ///
    /// - Parameter log: the run's call log, which both fixtures record into.
    /// - Throws: whatever building the registry or calling `MultiTool` throws.
    private static func readEveryTripReading(into log: ScenarioCallLog) async throws {
        _ = try await runComposeSnippet(
            """
            const trip = await tools.\(IntegrationTripTool.path)();
            const readings = await Promise.all(
                trip.cities.map((city) => tools.\(IntegrationWeatherTool.path)({ city: city }))
            );
            return readings.map((reading) => reading.tempC).join(",");
            """,
            log: log
        )
    }

    /// Grades the discovery scenario's question against what `log` recorded.
    ///
    /// The accepted answers, the reading and the declared grounding all come
    /// from the fixtures, so this grades the same contract
    /// `SearchThenCallTests.discoveryUnderDistractors` does rather than a copy
    /// of it.
    ///
    /// - Parameters:
    ///   - reply: the model's final reply to grade.
    ///   - typedPaths: the `tools.*` paths the run's snippet wrote — the paths
    ///     the snippet above calls, which the grounding condition reports and
    ///     never grades on.
    ///   - log: the run's call log.
    /// - Returns: every graded condition, in reporting order.
    private static func warmestCityChecks(
        reply: String, typedPaths: Set<String>, log: ScenarioCallLog
    ) async -> [ScenarioCheck] {
        scenarioChecks(
            for: ScenarioEvidence(
                answer: reply,
                typedPaths: typedPaths,
                invokedPaths: await log.invokedPaths,
                returnedPaths: await log.returnedPaths
            ),
            answerContainsOneOf: IntegrationScenarioAnswers.warmestCity,
            // Empty, exactly as the discovery scenario leaves it.
            answerMustNotContain: [],
            readingContainsOneOf: IntegrationScenarioAnswers.warmestCityReading,
            groundedIn: IntegrationScenarioGrounding.warmestCity
        )
    }

    /// A reply that names the warmest trip city and no reading, in the recorded shape.
    ///
    /// Rebuilt from the fixtures rather than quoted, so it names whichever city
    /// the readings make warmest instead of pinning the one the recorded run
    /// happened to name. The recorded reply opened by listing the trip's cities
    /// and then named one of them as the warmest, which is the whole difficulty:
    /// its *form* is a correct answer, and only what the run fetched separates
    /// it from one.
    private static var replyNamingTheWarmestCity: String {
        let itinerary = integrationCityWeather.map { "\($0.name) (\($0.code))" }.joined(separator: ", ")
        return "I can see your trip includes \(itinerary). \(integrationWarmestCity.name) is the warmest right now."
    }

    /// A reply that names the warmest trip city and states its reading, the
    /// answer the discovery scenario asks for.
    ///
    /// The reading is the fixture row's own temperature, written as a whole
    /// number of degrees, so the reply follows the fixture when a reading
    /// changes.
    private static var replyNamingTheWarmestCityAndItsReading: String {
        "\(replyNamingTheWarmestCity) It is \(Int(integrationWarmestCity.tempC)) °C there."
    }

    /// The number of the first submission of a scripted chain.
    private static let firstSubmissionNumber: UInt64 = 1

    /// The number of the continuation submission of a scripted chain.
    private static let secondSubmissionNumber: UInt64 = 2

    /// The input tokens of the first scripted submission.
    private static let firstTokensIn = 120

    /// The output tokens of the first scripted submission.
    private static let firstTokensOut = 40

    /// The tokens the scripted repetition stop reports as generated.
    private static let stoppedGeneratedTokens = 3_000

    /// The lines the scripted repetition stop reports as counted.
    private static let stoppedCountedLines = 40

    /// The lines the scripted repetition stop reports as new.
    private static let stoppedNewLines = 6

    /// The tokens the scripted repetition stop reports since the last new line.
    private static let stoppedTokensWithoutNewLine = 2_100

    /// The reply of each scripted answer the fold tests make.
    private static let foldedReply = "NYC is warmest"

    /// The reply of the second answer of the test with two answers.
    private static let otherReply = "the run settled"

    /// A scripted final answer to one mail.
    ///
    /// - Parameters:
    ///   - reply: the final reply of the answer.
    ///   - message: the mail the answer answers.
    /// - Returns: the answer, with no usage, compaction or tool call.
    private static func answer(reply: String, to message: MailID) -> SessionAnswer {
        SessionAnswer(
            reply: reply, mailIds: [message], usage: nil, compactions: [], toolCalls: [], toolInvocations: [])
    }

    /// The session output of a scripted chain of one answer: each event has
    /// the origin of the answer to `message`.
    ///
    /// - Parameters:
    ///   - message: the mail whose answer sent the events.
    ///   - events: the events of the chain, in order.
    /// - Returns: the output.
    private static func outputs(of message: MailID, _ events: [SessionEvent]) -> [SessionOutput] {
        events.map { SessionOutput(origin: .mail([message]), event: $0) }
    }

    /// Picks one graded condition out of a run's verdict by name.
    ///
    /// - Parameters:
    ///   - name: the condition's label on the `SCENARIO` line.
    ///   - checks: every condition the run was graded on.
    /// - Returns: that condition.
    /// - Throws: an expectation failure when the verdict carries no condition of that name.
    private static func check(_ name: String, in checks: [ScenarioCheck]) throws -> ScenarioCheck {
        try #require(checks.first { $0.name == name })
    }
}
