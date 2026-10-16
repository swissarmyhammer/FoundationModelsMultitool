import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The seconds argument a snippet gives the removed `wait()`. The call throws
/// before it reads the argument, thus the value has no effect.
private let removedWaitSecondsArgument = 1

/// A snippet that calls the removed `wait()` inside `try`, and returns the
/// message of the error it catches, or `"no-throw"`.
private let removedWaitCatchingSnippet = """
    try {
        await wait("no-such-token", \(removedWaitSecondsArgument));
        return "no-throw";
    } catch (error) {
        return String(error.message);
    }
    """

/// Phase-1 coverage for the five ambient sandbox globals — eventplan.md § "The
/// sandbox globals" and § "Async JavaScript"'s one-rule contract ("each call
/// that goes into Swift effects returns a promise… these calls are
/// synchronous: `help()` and `docs()`… and `notify()` / `progress()`").
///
/// Every background-run assertion drives a real `RunPlane` — a real
/// background run, a real settlement, a real elicitation reply — under an ambient
/// `ToolContext` the test owns, so what is exercised is the actual Router
/// surface rather than a stand-in for it.
@Suite("Sandbox globals")
struct SandboxGlobalsTests {
    // MARK: - Reachability and the promise-vs-sync contract

    @Test("each global that the globals page declares is a function in a fresh run")
    func eachDocumentedGlobalIsReachable() async throws {
        let names = documentedGlobalNames()
        try #require(!names.isEmpty)

        let output = try await runSnippet(
            """
            return \(jsArrayLiteral(of: names))
                .map(name => typeof name.split(".").reduce((owner, key) => owner[key], globalThis));
            """
        )

        let kinds = try RunOutput.decoded([String].self, from: output)
        #expect(kinds == Array(repeating: "function", count: names.count))
    }

    @Test("the globals are not discoverable entries — help() and the searchTools surface list none of them")
    func globalsAreNotDiscoverableEntries() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return help();"))

        let helpPaths = try RunOutput.decoded([String].self, from: output)
        #expect(helpPaths == ["getCities"])
        let surfacePaths = Set(registry.surface.entries.map(\.path))
        #expect(surfacePaths.isDisjoint(with: documentedGlobalNames()))
    }

    @Test("the run verbs return promises; notify, progress, help, and docs return plain values")
    func promiseVersusSynchronousContractHolds() async throws {
        try await withStubRun { stub in
            let context = stub.context

            let output = try await runSnippet(
                """
                return [
                    "status:" + typeof status().then,
                    "cancel:" + typeof cancel("no-such-token").then,
                    "notify:" + String(notify("a notice")),
                    "progress:" + String(progress("half way")),
                    "help:" + typeof help().then,
                    "docs:" + typeof docs("nothing").then,
                ];
                """,
                under: context
            )

            #expect(
                try RunOutput.decoded([String].self, from: output) == [
                    "status:function",
                    "cancel:function",
                    "notify:undefined",
                    "progress:undefined",
                    "help:undefined",
                    "docs:undefined",
                ]
            )
        }
    }

    // MARK: - Discovery: docs() carries the contract the description points at

    @Test("docs(\"globals\") reaches the snippet whole — runCode's return cap never truncates the contract")
    func theGlobalsPageReachesTheSnippetWhole() async throws {
        let output = try await runSnippet("return docs(\"\(MultiTool.sandboxGlobalsDocsTopic)\");")

        #expect(try RunOutput.decoded(String.self, from: output) == MultiTool.sandboxGlobalsPage(asksUser: true))
    }

    @Test("docs(name) resolves each ambient global on its own, returning that one's block alone")
    func docsResolvesEachAmbientGlobalByName() async throws {
        for name in documentedGlobalNames() {
            let output = try await runSnippet("return docs(\"\(name)\");")

            let block = try RunOutput.decoded(String.self, from: output)
            #expect(declaredFunctionNames(in: block) == [name])
        }
    }

    @Test("the globals page states which calls are awaited by declaring their return types")
    func theGlobalsPageStatesWhichCallsAreAwaited() {
        let page = MultiTool.sandboxGlobalsPage(asksUser: true)

        for name in documentedGlobalNames() where !MultiTool.voidGlobalNames.contains(name) {
            #expect(declaredReturnType(of: name, in: page)?.hasPrefix("Promise<") == true)
        }
        for name in MultiTool.voidGlobalNames {
            #expect(declaredReturnType(of: name, in: page) == "void")
        }
    }

    @Test("the globals page declares the exact fields a running background run really reports")
    func theGlobalsPageMatchesTheBackgroundRunItDocuments() async throws {
        let clock = ManualRunClock()
        try await withStubRun(runClock: clock) { stub in
            let context = stub.context
            // The run must still be going while the snippet reads it. Its gate
            // opens after the last check, before the session closes.
            try await withScriptedRun(on: context, clock: clock, progress: "step one") { _ in
                let output = try await runSnippet(
                    "return Object.keys((await status())[0]).sort();",
                    under: context
                )

                let observed = try RunOutput.decoded([String].self, from: output)
                let documented = try #require(declaredFields(of: "BackgroundRun", in: MultiTool.sandboxGlobalsPage(asksUser: true)))
                #expect(documented == observed)
            }
        }
    }

    @Test("the globals page declares the exact fields an elicitation answer really carries")
    func theGlobalsPageMatchesTheElicitationAnswerItDocuments() async throws {
        // The sink answers the elicitation of the snippet.
        let observed = try await runElicitationSnippet(
            "return Object.keys(await elicit(\"Which repository?\")).sort();",
            answering: .accept(content: [elicitHelperAnswerField: .string("sah")]),
            decoding: [String].self
        )

        let documented = try #require(
            declaredFields(of: "ElicitationAnswer", in: MultiTool.sandboxGlobalsPage(asksUser: true)))
        #expect(documented == observed)
    }

    // MARK: - User presence: elicit() only when a user can answer

    @Test("a headless session has no elicit global, and docs() does not declare one")
    func userPresenceHeadlessHasNoElicit() async throws {
        let output = try await runSnippet(elicitPresenceProbe, under: makeContext(userPresence: .headless))

        let probe = try RunOutput.decoded(ElicitPresenceProbe.self, from: output)
        #expect(probe.type == "undefined")
        #expect(!probe.listed)
        #expect(probe.entry.hasPrefix("Unknown tool \"elicit\""), "the entry was: \(probe.entry)")
    }

    @Test("an interactive session has the elicit global, and docs() declares it")
    func userPresenceInteractiveHasElicit() async throws {
        let output = try await runSnippet(elicitPresenceProbe, under: makeContext(userPresence: .interactive))

        let probe = try RunOutput.decoded(ElicitPresenceProbe.self, from: output)
        #expect(probe.type == "function")
        #expect(probe.listed)
        #expect(probe.entry.hasPrefix("// elicit\n"), "the entry was: \(probe.entry)")
        #expect(probe.entry.contains("declare function elicit("))
    }

    /// For one user presence, the globals that the sandbox really installs
    /// and the globals that `docs("globals")` declares are the same set. The
    /// installed side is read at run time, and no list in this suite names
    /// it: each own function of `globalThis` that a new `JSContext` does not
    /// have, without `help`, `docs` and the removed `wait`, and each own
    /// function member of such a global as `name.member`. Each name has a
    /// `docs(name)` block that starts with `// <name>`. The preface tells a
    /// snippet to await each promise global, and it declares
    /// `ElicitationAnswer` only when `elicit` is installed.
    @Test(
        "for each user presence, the installed globals and the globals that docs declares are the same set",
        arguments: [UserPresence.headless, .interactive]
    )
    func installedGlobalsMatchTheDocumentedGlobals(presence: UserPresence) async throws {
        let page = MultiTool.sandboxGlobalsPage(asksUser: presence != .headless)
        let observed = try await installedGlobalsProbe(expecting: page, under: makeContext(userPresence: presence))
        let installed = Set(observed.installed)
        try #require(!installed.isEmpty)

        #expect(observed.pageIsServed)
        #expect(installed == Set(declaredFunctionNames(in: page)))
        #expect(observed.misnamedBlocks.isEmpty, "these docs(name) blocks do not start with their name")
        #expect(Set(awaitedNames(in: page)) == installed.subtracting(MultiTool.voidGlobalNames))
        #expect((declaredFields(of: "ElicitationAnswer", in: page) != nil) == installed.contains(MultiTool.elicitGlobalName))
    }

    @Test("a headless snippet that calls elicit() fails with a ReferenceError that holds the no-user hint")
    func userPresenceHeadlessElicitFailsWithTheHint() async throws {
        let output = try await runSnippet(
            "return await elicit(\"q\");", under: makeContext(userPresence: .headless))

        // JavaScriptCore words a `ReferenceError` for an undeclared name as
        // "Can't find variable: <name>", and the rendered failure keeps that text.
        #expect(output.contains("Can't find variable: elicit"), "the output was: \(output)")
        #expect(output.contains(noUserPresentHintText), "the output was: \(output)")
    }

    // MARK: - The two discriminators

    @Test("state and result never appear on one object — state is the run, result is the call")
    func stateAndResultNeverAppearOnOneObject() async throws {
        let clock = ManualRunClock()
        try await withStubRun(runClock: clock) { stub in
            let context = stub.context
            // The gate of `running` opens after the last check, before the
            // session closes.
            try await withScriptedRun(on: context, clock: clock, tool: "slow") { running in
                let finished = try await startScriptedRun(on: context, clock: clock, tool: "quick")
                await settle(finished, on: context)

                let output = try await runSnippet(
                    """
                    const shapes = [
                        await status("\(running.completionToken)"),
                        await status("\(finished.completionToken)"),
                        await status("no-such-token"),
                        await cancel("\(finished.completionToken)"),
                        await cancel("no-such-token"),
                        await cancel("\(running.completionToken)"),
                    ];
                    return shapes.map(shape => ["state" in shape, "result" in shape]);
                    """,
                    under: context
                )

                #expect(
                    try RunOutput.decoded([[Bool]].self, from: output) == [
                        [true, false],   // status() on a run that is going
                        [true, false],   // status() on a run that finished
                        [false, true],   // status() on a handle naming no run
                        [true, false],   // cancel() that arrived too late
                        [false, true],   // cancel() on a handle naming no run
                        [false, true],   // cancel() the canceler answered
                    ]
                )
            }
        }
    }

    // MARK: - status()

    @Test("status() with no argument lists each running run's token, op, and latest progress")
    func statusWithNoArgumentListsEveryRunningRun() async throws {
        let clock = ManualRunClock()
        try await withStubRun(runClock: clock) { stub in
            let context = stub.context
            try await withScriptedRun(on: context, clock: clock, progress: "downloading") { run in
                let output = try await runSnippet(
                    "return (await status()).map(row => [row.completionToken, row.op, row.latestProgress]);",
                    under: context
                )

                #expect(
                    try RunOutput.decoded([[String?]].self, from: output)
                        == [[run.completionToken, run.op, "downloading"]])
            }
        }
    }

    @Test("status(completionToken) reports a running run as running")
    func statusWithATokenReportsARunningRun() async throws {
        let clock = ManualRunClock()
        try await withStubRun(runClock: clock) { stub in
            let context = stub.context
            try await withScriptedRun(on: context, clock: clock, progress: "step one") { run in
                let output = try await runSnippet(
                    """
                    const row = await status("\(run.completionToken)");
                    return [row.state, row.completionToken, row.op, row.kind, row.latestProgress];
                    """,
                    under: context
                )

                #expect(
                    try RunOutput.decoded([String?].self, from: output) == [
                        "running", run.completionToken, run.op, "swiftTask", "step one",
                    ]
                )
            }
        }
    }

    @Test("status(completionToken) reports a finished run as complete, with its terminal outcome")
    func statusWithATokenReportsAFinishedRun() async throws {
        let clock = ManualRunClock()
        try await withStubRun(runClock: clock) { stub in
            let context = stub.context
            let run = try await startScriptedRun(on: context, clock: clock)
            await settle(run, on: context)

            let output = try await runSnippet(
                """
                const row = await status("\(run.completionToken)");
                return [row.state, row.completionToken, row.detail, row.outcome];
                """,
                under: context
            )

            #expect(
                try RunOutput.decoded([String?].self, from: output) == [
                    "complete", run.completionToken, "scripted-terminal-detail", "succeeded",
                ]
            )
        }
    }

    @Test("status(completionToken) reports a run that failed as error, and outcome says why")
    func statusWithATokenReportsAFailedRun() async throws {
        let clock = ManualRunClock()
        try await withStubRun(runClock: clock) { stub in
            let context = stub.context
            let run = try await startScriptedRun(on: context, clock: clock, failing: true)
            await settle(run, on: context)

            let output = try await runSnippet(
                """
                const row = await status("\(run.completionToken)");
                return [row.state, row.completionToken, row.outcome];
                """,
                under: context
            )

            #expect(
                try RunOutput.decoded([String?].self, from: output) == [
                    "error", run.completionToken, OperationOutcome.failed.rawValue,
                ]
            )
        }
    }

    @Test("status(completionToken) reports an unknown token as a safe no-op, never a throw")
    func statusWithAnUnknownTokenIsASafeNoOp() async throws {
        try await withStubRun { stub in
            let context = stub.context

            let output = try await runSnippet(
                """
                const row = await status("no-such-token");
                return [row.result, row.completionToken];
                """,
                under: context
            )

            #expect(try RunOutput.decoded([String].self, from: output) == ["unknown", "no-such-token"])
        }
    }

    // MARK: - The removed wait()

    @Test("a snippet that calls wait() in a session gets the repair text: return the token, and the shared pending text")
    func waitInASessionGivesTheRepairText() async throws {
        let clock = ManualRunClock()
        try await withStubRun(runClock: clock) { stub in
            let context = stub.context
            try await withScriptedRun(on: context, clock: clock) { run in
                let output = try await runSnippet(removedWaitCatchingSnippet, under: context)

                let message = try RunOutput.decoded(String.self, from: output)
                #expect(message == "\(MultiTool.removedWaitGlobalName): \(SandboxGlobalError.waitRemoved.description)")
                #expect(message.contains(PendingRunEnvelope.pendingWorkInstruction))
                // The call holds nothing: the run it names is still going.
                #expect(await context.backgroundRuns().map(\.completionToken) == [run.completionToken])
            }
        }
    }

    @Test("a snippet that calls wait() with no session gets the same repair text, not the no-session text")
    func waitWithoutASessionGivesTheSameRepairText() async throws {
        let output = try await runSnippet(removedWaitCatchingSnippet)

        let message = try RunOutput.decoded(String.self, from: output)
        #expect(message == "\(MultiTool.removedWaitGlobalName): \(SandboxGlobalError.waitRemoved.description)")
        #expect(!message.contains(SandboxGlobalError.noSession.description))
    }

    @Test("an uncaught wait(\"t\", 1) fails the snippet with the repair text, not a ReferenceError")
    func uncaughtWaitFailsWithTheRepairText() async throws {
        let output = try await runSnippet("return await wait(\"t\", \(removedWaitSecondsArgument));")

        #expect(output.contains(SandboxGlobalError.waitRemoved.description))
        #expect(output.contains(RepairDirective.repairSnippet.closingLine))
        #expect(!output.contains("ReferenceError"))
    }

    @Test("the globals page and docs(\"wait\") declare no wait global")
    func theGlobalsPageDeclaresNoWait() {
        for asksUser in [false, true] {
            #expect(!MultiTool.sandboxGlobalsPage(asksUser: asksUser).contains("\(MultiTool.removedWaitGlobalName)("))
            #expect(MultiTool.sandboxGlobalsDocumentation(for: MultiTool.removedWaitGlobalName, asksUser: asksUser) == nil)
        }
    }

    // MARK: - cancel()

    @Test("cancel() returns the canceler's honest outcome, verbatim")
    func cancelReturnsTheHonestOutcome() async throws {
        let clock = ManualRunClock()
        try await withStubRun(runClock: clock) { stub in
            let context = stub.context
            // The cancel does not end the body on the gate. The gate opens
            // after the last check, before the session closes.
            try await withScriptedRun(on: context, clock: clock) { run in
                let output = try await runSnippet(
                    """
                    const outcome = await cancel("\(run.completionToken)");
                    return [outcome.result, outcome.completionToken, outcome.outcome];
                    """,
                    under: context
                )

                #expect(
                    try RunOutput.decoded([String].self, from: output) == [
                        "cancelled", run.completionToken, scriptedRunCancelOutcome.rawValue,
                    ]
                )
            }
        }
    }

    @Test("cancel() on a run that already finished reports the retained terminal event, not an unknown token")
    func cancelOnAFinishedRunReportsItsTerminalEvent() async throws {
        let clock = ManualRunClock()
        try await withStubRun(runClock: clock) { stub in
            let context = stub.context
            let run = try await startScriptedRun(on: context, clock: clock)
            await settle(run, on: context)

            let output = try await runSnippet(
                """
                const outcome = await cancel("\(run.completionToken)");
                return [outcome.state, outcome.completionToken, outcome.detail, outcome.outcome];
                """,
                under: context
            )

            #expect(
                try RunOutput.decoded([String?].self, from: output) == [
                    "complete", run.completionToken, "scripted-terminal-detail", "succeeded",
                ]
            )
        }
    }

    @Test("cancel() reports an unknown token as a safe no-op, never a throw")
    func cancelWithAnUnknownTokenIsASafeNoOp() async throws {
        try await withStubRun { stub in
            let context = stub.context

            let output = try await runSnippet(
                """
                const outcome = await cancel("no-such-token");
                return [outcome.result, outcome.completionToken];
                """,
                under: context
            )

            #expect(try RunOutput.decoded([String].self, from: output) == ["unknown", "no-such-token"])
        }
    }

    // MARK: - elicit()

    /// The watch task of a ``ScriptedElicitationSink`` is not a task of the
    /// session, thus the close of the session does not end it. The scoped
    /// form must end it before it returns, so that nothing of one test waits
    /// on after that test. The order is fixed: the scope returns, the session
    /// closes, and then the test reads the end flag of the watch one time.
    @Test("the watch of a scripted elicitation sink ends when its scope ends")
    func theWatchOfAScriptedElicitationSinkEndsWithItsScope() async throws {
        let sink = try await withStubRun { stub in
            try await withScriptedElicitationSink(run: stub, answering: .decline) { $0 }
        }

        #expect(await sink.watchEnded, "the watch task still waits after its scope and the close")
    }

    /// The call to `respond` resumes the snippet before the watch records the
    /// delivery. This test holds the record step at a gate. The order is
    /// fixed: the snippet returns, the test reads the deliveries, the read
    /// starts to wait and opens the gate, and then the watch records. A read
    /// that returns before the record sees no delivery and a closed gate.
    @Test("a read of the elicitation deliveries waits until the sink recorded them")
    func theDeliveriesReadWaitsForTheRecord() async throws {
        let record = TestGate()
        try await withStubRun { stub in
            let context = stub.context
            try await withScriptedElicitationSink(
                run: stub,
                answering: .accept(content: [elicitHelperAnswerField: .string("sah")]),
                holdingRecordAt: record
            ) { sink in
                let output = try await runSnippet(
                    "return (await elicit(\"Which repository?\")).action;",
                    under: context
                )
                #expect(try RunOutput.decoded(String.self, from: output) == "accept")

                let deliveries = await sink.deliveries(count: 1)
                let recordWasOpen = record.isOpen
                // Let the watch go on, so that the scope can end it.
                record.open()

                #expect(recordWasOpen, "the read of the deliveries returned before the record step")
                #expect(deliveries == [.delivered])
            }
        }
    }

    /// The text short form sends a form with one required string field,
    /// `answer`, and an accept gives the plain string as `content`.
    @Test("elicit(\"question\") suspends the snippet, sends one required text field, and resumes with the plain text")
    func elicitStringShorthandRoundTripsAnAcceptedAnswer() async throws {
        try await withStubRun { stub in
            let context = stub.context
            try await withScriptedElicitationSink(
                run: stub,
                answering: .accept(content: [elicitHelperAnswerField: .string("swissarmyhammer")])
            ) { sink in
                let output = try await runSnippet(
                    """
                    const pending = elicit("Which repository should I target?");
                    const isThenable = typeof pending.then === "function";
                    const answer = await pending;
                    return [String(isThenable), answer.action, typeof answer.content, answer.content];
                    """,
                    under: context
                )

                #expect(
                    try RunOutput.decoded([String].self, from: output) == ["true", "accept", "string", "swissarmyhammer"])
                let request = try #require(await sink.observedRequest)
                #expect(request.mode == .form)
                #expect(request.message == "Which repository should I target?")
                #expect(request.requestedSchema == elicitShortFormSchema)
                // The snippet can return before the sink records the delivery.
                #expect(await sink.deliveries(count: 1) == [.delivered])
            }
        }
    }

    /// The form of the text short form requires `answer`. Thus an accept that
    /// does not hold it is not a valid answer, and the snippet gets a decline
    /// with the invalid-answer reason in place of the accept.
    @Test("an accept of elicit(\"question\") with no answer field gives a decline with the invalid-answer reason")
    func elicitStringShorthandTurnsAnAcceptWithNoAnswerIntoADecline() async throws {
        let answer = try await elicitationAnswerProbe(answering: .accept(content: ["repo": .string("sah")]))

        #expect(answer.action == "decline")
        #expect(answer.content == nil)
        #expect(
            answer.reason?.hasPrefix(ElicitationRequestedSchema.invalidAnswerReasonPrefix) == true,
            "the reason was: \(String(describing: answer.reason))")
    }

    @Test("a declined elicitation surfaces as a decline, distinct from a cancel")
    func elicitSurfacesADeclineDistinctly() async throws {
        // The sink answers the elicitation of the snippet.
        let observed = try await runElicitationSnippet(
            elicitationActionAndContentSnippet, answering: .decline, decoding: [String].self)

        #expect(observed == ["decline", "null"])
    }

    @Test("a cancelled elicitation surfaces as a cancel, distinct from a decline")
    func elicitSurfacesACancelDistinctly() async throws {
        // The sink answers the elicitation of the snippet.
        let observed = try await runElicitationSnippet(
            elicitationActionAndContentSnippet, answering: .cancel, decoding: [String].self)

        #expect(observed == ["cancel", "null"])
    }

    /// The sink answers with a decline or a cancel that has a reason. The
    /// snippet must get that reason, and `content` must be `null`. Each
    /// argument runs one snippet in a fixed order: the snippet asks, the sink
    /// answers, and the snippet returns what it got.
    @Test(
        "a decline or a cancel with a reason gives that reason to the snippet",
        arguments: [
            ElicitationResponse.decline(reason: "not now"),
            ElicitationResponse.cancel(reason: "run cancelled"),
        ]
    )
    func elicitGivesTheReasonOfADeclineOrACancel(response: FoundationModelsExtras.ElicitationResponse) async throws {
        let answer = try await elicitationAnswerProbe(answering: response)

        let expected = ElicitationAnswerProbe(
            keys: elicitationAnswerKeys,
            action: response.action.rawValue,
            content: nil,
            reason: response.reason
        )
        #expect(answer == expected)
    }

    @Test("an accepted elicitation gives a null reason to the snippet")
    func elicitGivesANullReasonOnAnAccept() async throws {
        let answer = try await elicitationAnswerProbe(answering: .accept(content: [elicitHelperAnswerField: .string("sah")]))

        let expected = ElicitationAnswerProbe(
            keys: elicitationAnswerKeys,
            action: "accept",
            content: "sah",
            reason: nil
        )
        #expect(answer == expected)
    }

    @Test("elicit({ message, requestedSchema }) carries the restricted form schema through unchanged")
    func elicitCarriesAFormSchemaThrough() async throws {
        try await withStubRun { stub in
            let context = stub.context
            try await withScriptedElicitationSink(
                run: stub,
                answering: .accept(content: ["repo": .string("multitool")])
            ) { sink in
                let output = try await runSnippet(
                    """
                    const answer = await elicit({
                        message: "Pick a repository",
                        requestedSchema: {
                            type: "object",
                            properties: { repo: { type: "string", title: "Repository" } },
                            required: ["repo"],
                        },
                    });
                    return [answer.action, answer.content.repo];
                    """,
                    under: context
                )

                #expect(try RunOutput.decoded([String].self, from: output) == ["accept", "multitool"])
                let request = try #require(await sink.observedRequest)
                #expect(request.mode == .form)
                #expect(request.requestedSchema?.required == ["repo"])
                guard case .string(let repoSchema)? = request.requestedSchema?.properties["repo"] else {
                    Issue.record("the repo property did not decode as a string schema")
                    return
                }
                #expect(repoSchema.title == "Repository")
            }
        }
    }

    @Test("elicit({ message, url }) resolves only once the out-of-band flow completes")
    func elicitUrlModeResolvesAfterCompletion() async throws {
        try await withStubRun { stub in
            let context = stub.context
            try await withScriptedElicitationSink(run: stub, answering: .accept(content: nil)) { sink in
                let output = try await runSnippet(
                    """
                    const answer = await elicit({ message: "Sign in", url: "https://example.com/auth" });
                    return answer.action;
                    """,
                    under: context
                )

                #expect(try RunOutput.decoded(String.self, from: output) == "accept")
                let request = try #require(await sink.observedRequest)
                #expect(request.mode == .url)
                #expect(request.url == URL(string: "https://example.com/auth"))
                #expect(await sink.deliveries(count: 1) == [.acceptedAwaitingCompletion])
                // The snippet can return before the sink records the completion.
                #expect(await sink.completions(count: 1) == [.completed])
            }
        }
    }

    @Test("elicit() with neither a question nor a message rejects with a repairable error naming the shape")
    func elicitWithoutAMessageRejectsRepairably() async throws {
        try await withStubRun { stub in
            let context = stub.context

            let output = try await runSnippet(
                """
                try {
                    await elicit(42);
                    return "no-throw";
                } catch (error) {
                    return String(error.message);
                }
                """,
                under: context
            )

            let message = try RunOutput.decoded(String.self, from: output)
            #expect(message.hasPrefix("elicit: "))
            #expect(message.contains("elicit(\"question\")"))
        }
    }

    // MARK: - The elicit helpers: elicit.confirm, choose, chooseMany, askText, askNumber

    /// Each helper sends a form with one required field `answer`, and the
    /// snippet reads the plain value of that field as `content`. Each case
    /// runs in a fixed order: the snippet asks, the sink answers, and the
    /// snippet returns what it got.
    @Test("each elicit helper sends its one-field form, and an accept gives the plain answer", arguments: elicitHelperRoundTrips)
    func elicitHelperSendsItsFormAndGivesThePlainAnswer(roundTrip: ElicitHelperRoundTrip) async throws {
        try await withStubRun { stub in
            let context = stub.context
            try await withScriptedElicitationSink(
                run: stub, answering: .accept(content: [elicitHelperAnswerField: roundTrip.answer])
            ) { sink in
                let output = try await runSnippet(
                    """
                    const answer = await \(roundTrip.call);
                    return { action: answer.action, content: JSON.stringify(answer.content), reason: answer.reason };
                    """,
                    under: context
                )

                let observed = try RunOutput.decoded(ElicitHelperAnswer.self, from: output)
                #expect(observed == ElicitHelperAnswer(action: "accept", content: roundTrip.content, reason: nil))
                let request = try #require(await sink.observedRequest)
                #expect(request.mode == .form)
                #expect(request.message == elicitHelperMessage)
                #expect(request.requestedSchema == roundTrip.schema)
            }
        }
    }

    /// The sink declines or cancels each helper with a reason. Each helper
    /// must give that reason, with `null` content. The snippet asks with each
    /// helper in turn, and the sink answers each request in that order.
    @Test(
        "each elicit helper gives the reason of a decline or a cancel, and null content",
        arguments: [
            ElicitationResponse.decline(reason: "not now"),
            ElicitationResponse.cancel(reason: "run cancelled"),
        ]
    )
    func elicitHelperGivesTheReasonOfADeclineOrACancel(response: FoundationModelsExtras.ElicitationResponse) async throws {
        let answers = try await elicitHelperAnswers(answering: response)

        let expected = ElicitHelperAnswer(action: response.action.rawValue, content: "null", reason: response.reason)
        #expect(answers == Array(repeating: expected, count: elicitHelperCalls.count))
    }

    /// The sink accepts each helper with a string that no helper takes:
    /// `confirm`, `chooseMany` and `askNumber` take no string, the string is
    /// not an option of `choose`, and it does not match the pattern of
    /// `askText`. Each helper must give a decline with the invalid-answer
    /// reason in place of the accept.
    @Test("an accept that is not a valid answer to an elicit helper gives a decline with the invalid-answer reason")
    func elicitHelperTurnsAnInvalidAcceptIntoADecline() async throws {
        let answers = try await elicitHelperAnswers(
            answering: .accept(content: [elicitHelperAnswerField: .string(elicitHelperInvalidAnswer)]))

        #expect(answers.count == elicitHelperCalls.count)
        for answer in answers {
            #expect(answer.action == "decline")
            #expect(answer.content == "null")
            #expect(answer.reason?.hasPrefix(ElicitationRequestedSchema.invalidAnswerReasonPrefix) == true, "the reason was: \(String(describing: answer.reason))")
        }
    }

    /// A call with bad arguments throws at the call, before a request goes to
    /// the user. The order is fixed: the bad call throws, then the snippet
    /// asks one valid question, and the sink answers it. Thus the valid
    /// question is the only request that the sink observed.
    @Test("an elicit helper with bad arguments throws its usage text, and sends no request", arguments: elicitHelperArgumentErrors)
    func elicitHelperArgumentErrorSendsNoRequest(argumentError: ElicitHelperArgumentError) async throws {
        let usage = try #require(MultiTool.elicitationGlobals.first { $0.name == argumentError.helper }?.usage)
        #expect(usage.hasPrefix("\(argumentError.helper)("))
        try await withStubRun { stub in
            let context = stub.context
            try await withScriptedElicitationSink(run: stub, answering: .decline) { sink in
                let output = try await runSnippet(
                    """
                    let message = "no-throw";
                    try {
                        await \(argumentError.call);
                    } catch (error) {
                        message = String(error.message);
                    }
                    await elicit.confirm(\(try jsStringLiteral(elicitHelperFollowUpMessage)));
                    return message;
                    """,
                    under: context
                )

                let message = try RunOutput.decoded(String.self, from: output)
                #expect(message.hasPrefix("\(argumentError.helper): "), "the message was: \(message)")
                #expect(message.contains(usage), "the message was: \(message)")
                #expect(await sink.deliveries(count: 1) == [.delivered])
                #expect(await sink.requests.map(\.message) == [elicitHelperFollowUpMessage])
            }
        }
    }

    /// A snippet cannot replace or remove a helper: an assignment and a
    /// `delete` leave the installed function in place. The names come from
    /// the globals page.
    @Test("a snippet cannot replace or delete an elicit helper")
    func elicitHelpersCannotBeReplaced() async throws {
        let helpers = documentedElicitHelperMembers()
        try #require(!helpers.isEmpty)

        let output = try await runSnippet(
            """
            return \(jsArrayLiteral(of: helpers)).map(name => {
                const installed = elicit[name];
                try { elicit[name] = function () { return "replaced"; }; } catch (error) {}
                try { delete elicit[name]; } catch (error) {}
                return typeof installed === "function" && elicit[name] === installed;
            });
            """
        )

        #expect(try RunOutput.decoded([Bool].self, from: output) == Array(repeating: true, count: helpers.count))
    }

    /// The globals page gives each helper one line, its declaration in the
    /// `elicit` namespace. The full text of a helper is in its own
    /// `docs(name)` block only.
    @Test("the globals page gives each elicit helper one declaration line, and no more")
    func theGlobalsPageGivesOneLineToEachElicitHelper() throws {
        let page = MultiTool.sandboxGlobalsPage(asksUser: true)
        let helpers = MultiTool.elicitationGlobals.filter { $0.name != MultiTool.elicitGlobalName }
        try #require(!helpers.isEmpty)

        for helper in helpers {
            let member = String(helper.name.dropFirst("\(MultiTool.elicitGlobalName).".count))
            let declarations = page.split(separator: "\n").filter {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("function \(member)(")
            }
            #expect(declarations.count == 1, "the declarations of \(helper.name) were: \(declarations)")
            #expect(!page.contains(helper.usage))
        }
    }

    /// The return cap of `runCode` has no room for the whole block of
    /// `elicit` next to the helper lines. Thus the page gives `elicit` one
    /// declaration line too, and `docs("elicit")` keeps the whole block.
    @Test("the globals page gives elicit one declaration line, and docs(\"elicit\") keeps the whole block")
    func theGlobalsPageGivesOneLineToElicit() throws {
        let page = MultiTool.sandboxGlobalsPage(asksUser: true)
        let declarations = page.split(separator: "\n").filter {
            $0.hasPrefix("declare function \(MultiTool.elicitGlobalName)(")
        }
        let block = try #require(MultiTool.sandboxGlobalsDocumentation(for: MultiTool.elicitGlobalName, asksUser: true))

        #expect(declarations.count == 1, "the declarations of elicit were: \(declarations)")
        #expect(!page.contains(MultiTool.elicitUsage))
        #expect(block.contains(MultiTool.elicitUsage))
    }

    /// An accept of `elicit("question")` gives the text, and an accept of a
    /// request object gives the object of the fields. Thus the declaration
    /// of `elicit` names both content types.
    @Test("the globals page declares string or object content for elicit")
    func theGlobalsPageDeclaresTheContentTypesOfElicit() {
        let page = MultiTool.sandboxGlobalsPage(asksUser: true)

        #expect(
            declaredReturnType(of: MultiTool.elicitGlobalName, in: page)
                == "Promise<\(ElicitationGlobal.answerTypeName)<string | object>>")
    }

    /// `docs("elicit.<m>")` gives the full block of the helper: its banner,
    /// its JSDoc comment with the usage text, the return type and an example,
    /// and its declaration in the `elicit` namespace.
    @Test("docs(\"elicit.<m>\") gives the full block of each elicit helper")
    func docsGivesTheFullBlockOfEachElicitHelper() async throws {
        let helpers = MultiTool.elicitationGlobals.filter { $0.name != MultiTool.elicitGlobalName }
        try #require(!helpers.isEmpty)

        // One run for each block: the blocks together are longer than the
        // return cap of `runCode`.
        for helper in helpers {
            let output = try await runSnippet("return docs(\(try jsStringLiteral(helper.name)));")

            let block = try RunOutput.decoded(String.self, from: output)
            #expect(block.hasPrefix("// \(helper.name)\n/**\n"), "the block was: \(block)")
            #expect(block.contains(helper.usage))
            #expect(block.contains(" * @returns Promise<\(ElicitationGlobal.answerTypeName)<"))
            #expect(block.contains(" * @example "))
            #expect(block.contains("declare namespace \(MultiTool.elicitGlobalName) {"))
        }
    }

    /// In a headless session, no helper is installed or documented, and a call
    /// to one gets the same no-user hint as a call to `elicit()`.
    @Test("a headless snippet that calls an elicit helper gets the no-user hint, and docs() does not declare the helper")
    func userPresenceHeadlessElicitHelperFailsWithTheHint() async throws {
        let helpers = documentedElicitHelperMembers()
        try #require(!helpers.isEmpty)

        for member in helpers {
            let name = "\(MultiTool.elicitGlobalName).\(member)"
            let call = try await runSnippet(
                "return await \(name)(\"q\");", under: makeContext(userPresence: .headless))
            let entry = try await runSnippet(
                "return docs(\(try jsStringLiteral(name)));", under: makeContext(userPresence: .headless))

            #expect(call.contains("Can't find variable: elicit"), "the output was: \(call)")
            #expect(call.contains(noUserPresentHintText), "the output was: \(call)")
            #expect(try RunOutput.decoded(String.self, from: entry).hasPrefix("Unknown tool \"\(name)\""))
        }
    }

    /// The page reaches the snippet as a JSON string. The JSON escapes make
    /// the text longer than the page, thus the test measures the page as the
    /// renderer of `runCode` serializes it, not the page. The renderer cuts a
    /// longer value at the cap, thus the test does not measure the output
    /// of a run: that output never shows how far the page is over the cap.
    @Test("the serialized docs(\"globals\") page stays under the return cap of runCode", arguments: [true, false])
    func theGlobalsPageStaysUnderTheReturnCap(asksUser: Bool) {
        let serialized = ResultRenderer.serialize(.string(MultiTool.sandboxGlobalsPage(asksUser: asksUser)))

        #expect(
            serialized.count < ResultRendererLimits.defaultReturnValueCharacterLimit,
            "the serialized page has \(serialized.count) characters"
        )
    }

    // MARK: - notify() / progress()

    @Test("notify() and progress() reach the session's sink on the run's own correlation")
    func noticesReachTheSinkOnTheRunsCorrelation() async throws {
        try await withStubRun { stub in
            let context = stub.context

            let output = try await runSnippet(
                """
                notify("starting the sweep");
                progress("half way");
                return "done";
                """,
                under: context
            )

            #expect(try RunOutput.decoded(String.self, from: output) == "done")
            // Router writes the second progress event in a merged row that only
            // `close()` writes, so the read settles the session first.
            let events = await settledOperationEvents(of: stub)
            #expect(events.filter { $0.kind == .progress }.map(\.detail) == ["starting the sweep", "half way"])
            #expect(events.allSatisfy { $0.correlationID == context.completionToken })
        }
    }

    @Test("a long snippet loop's notices reach the sink in the order the snippet enqueued them")
    func noticesArriveInSnippetOrder() async throws {
        try await withStubRun { stub in
            let context = stub.context

            _ = try await runSnippet(
                """
                for (let step = 1; step <= 4; step += 1) {
                    progress("step " + step);
                }
                notify("finished");
                return null;
                """,
                under: context
            )

            #expect(
                await settledOperationEvents(of: stub, ofKind: .progress).map(\.detail) == ["step 1", "step 2", "step 3", "step 4", "finished"]
            )
        }
    }

    // MARK: - No ambient context: there is no session, which is not a fault

    @Test("each run global rejects with a named, repairable error when the run has no session context")
    func runGlobalsRejectWithoutASessionContext() async throws {
        let output = try await runSnippet(
            """
            const calls = [
                ["status", () => status()],
                ["cancel", () => cancel("no-such-token")],
                ["elicit", () => elicit("Which repository?")],
            ];
            const results = [];
            for (const [name, call] of calls) {
                try {
                    await call();
                    results.push(name + ": no-throw");
                } catch (error) {
                    results.push(String(error.message));
                }
            }
            return results;
            """
        )

        let messages = try RunOutput.decoded([String].self, from: output)
        let promiseGlobalNames = ["status", "cancel", "elicit"]
        #expect(messages.count == promiseGlobalNames.count)
        for (name, message) in zip(promiseGlobalNames, messages) {
            #expect(message.hasPrefix("\(name): "))
            #expect(message.contains(SandboxGlobalError.noSession.description))
        }
    }

    @Test("notify() and progress() are silent no-ops when the run has no session context")
    func noticesAreSilentNoOpsWithoutASessionContext() async throws {
        let output = try await runSnippet(
            """
            notify("nobody is listening");
            progress("still nobody");
            return "done";
            """
        )

        #expect(try RunOutput.decoded(String.self, from: output) == "done")
    }
}

// MARK: - Suite helpers

/// Runs one snippet through a `runCode` tool over an empty registry, under
/// `context` when one is given.
///
/// An empty registry keeps every assertion about the globals themselves: the
/// registry does not change which globals are installed, so no wrapped tool
/// has to exist for them to be reachable. Passing `nil` for `context` is the no-ambient-context mode
/// every other unit suite in this package runs in — a `MultiTool` constructed
/// and called directly, outside any session.
///
/// - Parameters:
///   - code: the snippet to run.
///   - context: the ambient session context to bind around the call, or `nil`
///     to run with no session at all.
/// - Returns: the rendered `runCode` result.
/// - Throws: whatever `MultiTool.call(arguments:)` itself throws.
private func runSnippet(_ code: String, under context: ToolContext? = nil) async throws -> String {
    let multiTool = MultiTool(registry: MultiTool.Registry(surface: APISurface(entries: []), tools: [:]))
    let arguments = RunCodeArguments(code: code)
    guard let context else {
        return try await multiTool.call(arguments: arguments)
    }
    return try await ToolContext.$current.withValue(context) {
        try await multiTool.call(arguments: arguments)
    }
}

/// Renders `names` as a JavaScript array literal of string literals, so a
/// snippet can iterate exactly the set Swift pinned.
///
/// - Parameter names: the identifiers to render.
/// - Returns: the JavaScript array literal.
private func jsArrayLiteral(of names: [String]) -> String {
    "[\(names.map { "\"\($0)\"" }.joined(separator: ", "))]"
}

/// The return type the globals page declares for the function named `name`.
///
/// Read out of the rendered page rather than off the constant that built it,
/// so an assertion about which calls a snippet awaits is checked against the
/// text a model actually reads.
///
/// - Parameters:
///   - name: the global's name.
///   - page: the rendered globals page.
/// - Returns: the declared return type, or `nil` when the page declares no
///   such function.
private func declaredReturnType(of name: String, in page: String) -> String? {
    DeclaredFunction.all(in: page).first { $0.name == name }?.returnType
}

/// One function that a globals page or a `docs(name)` block declares.
private struct DeclaredFunction: Equatable {
    /// The name a snippet calls the function by: `name` for a
    /// `declare function name(...)` line, and `space.name` for a
    /// `function name(...)` line in a `declare namespace space { ... }` block.
    let name: String

    /// The declared return type, for example `Promise<NoResult>` or `void`.
    let returnType: String

    /// The text that opens a top-level declaration.
    private static let topLevelPrefix = "declare function "

    /// The text that opens a declaration in a namespace block.
    private static let memberPrefix = "function "

    /// The text between the parameter list and the return type.
    private static let returnSeparator = "): "

    /// Each function that `text` declares, in text order.
    ///
    /// - Parameter text: a globals page or one `docs(name)` block.
    /// - Returns: the declared functions.
    static func all(in text: String) -> [DeclaredFunction] {
        var namespace: String?
        var functions: [DeclaredFunction] = []
        for line in text.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let opened = line.wholeMatch(of: /declare namespace ([A-Za-z_$][A-Za-z0-9_$]*) \{/) {
                namespace = String(opened.1)
            } else if line == "}" {
                namespace = nil
            } else if let function = parse(line, in: namespace) {
                functions.append(function)
            }
        }
        return functions
    }

    /// Reads one declaration line.
    ///
    /// - Parameters:
    ///   - line: one trimmed line of the text.
    ///   - namespace: the namespace block that holds the line, or `nil`.
    /// - Returns: the declared function, or `nil` when the line declares none.
    private static func parse(_ line: String, in namespace: String?) -> DeclaredFunction? {
        let prefix = namespace == nil ? topLevelPrefix : memberPrefix
        guard
            line.hasPrefix(prefix),
            let open = line.firstIndex(of: "("),
            let returns = line.range(of: returnSeparator, options: .backwards)
        else {
            return nil
        }
        let name = String(line[line.index(line.startIndex, offsetBy: prefix.count)..<open])
        return DeclaredFunction(
            name: namespace.map { "\($0).\(name)" } ?? name,
            returnType: String(line[returns.upperBound...].dropLast()))
    }
}

/// The name of each global that the interactive globals page declares, in
/// page order — the names this suite iterates. They are read from the page,
/// and no list in this suite names them.
///
/// - Returns: the declared names.
private func documentedGlobalNames() -> [String] {
    declaredFunctionNames(in: MultiTool.sandboxGlobalsPage(asksUser: true))
}

/// Renders `text` as a JavaScript string literal.
///
/// A JSON string is a JavaScript string literal, thus the JSON encoder gives
/// the escapes.
///
/// - Parameter text: the text to render.
/// - Returns: the literal.
/// - Throws: when the encoder fails.
private func jsStringLiteral(_ text: String) throws -> String {
    String(decoding: try JSONEncoder().encode(text), as: UTF8.self)
}

/// Runs the enumeration snippet of
/// ``SandboxGlobalsTests/installedGlobalsMatchTheDocumentedGlobals(presence:)``
/// under `context`.
///
/// The snippet returns only names and flags, never the page itself: the page
/// fills most of the return cap of `runCode` by itself.
///
/// - Parameters:
///   - page: the globals page that `docs("globals")` must give.
///   - context: the session context of the run.
/// - Returns: what the snippet found.
/// - Throws: when the run fails, or when its output does not decode.
private func installedGlobalsProbe(expecting page: String, under context: ToolContext) async throws -> InstalledGlobalsProbe {
    let skipped = try JSContextBaseline.globalNames().sorted()
        + [MultiTool.helpGlobalName, MultiTool.docsGlobalName, MultiTool.removedWaitGlobalName]
    let output = try await runSnippet(
        """
        const skipped = new Set(\(jsArrayLiteral(of: skipped)));
        const plainMembers = new Set(Object.getOwnPropertyNames(function () {}));
        const installed = [];
        for (const name of Object.getOwnPropertyNames(globalThis)) {
            if (skipped.has(name) || typeof globalThis[name] !== "function") {
                continue;
            }
            installed.push(name);
            for (const member of Object.getOwnPropertyNames(globalThis[name])) {
                if (!plainMembers.has(member) && typeof globalThis[name][member] === "function") {
                    installed.push(name + "." + member);
                }
            }
        }
        return {
            installed,
            misnamedBlocks: installed.filter(name => !docs(name).startsWith("// " + name + "\\n")),
            pageIsServed: docs("\(MultiTool.sandboxGlobalsDocsTopic)") === \(try jsStringLiteral(page)),
        };
        """,
        under: context
    )
    return try RunOutput.decoded(InstalledGlobalsProbe.self, from: output)
}

/// The hint that a headless snippet gets when it calls `elicit()`. The text
/// is written here, and not read from the source, so that the test holds the
/// text that the owner accepted.
private let noUserPresentHintText = "elicit is not available: no user is present in this session"

/// A snippet that reports if `elicit` is a global, if `docs("globals")` names
/// it, and what `docs("elicit")` gives.
private let elicitPresenceProbe = """
    return {
        type: typeof elicit,
        listed: docs("globals").includes("elicit"),
        entry: docs("elicit"),
    };
    """

/// What ``elicitPresenceProbe`` returns.
private struct ElicitPresenceProbe: Decodable {
    /// The `typeof` of the `elicit` global.
    let type: String

    /// Tells if the globals page holds the text `elicit`.
    let listed: Bool

    /// What `docs("elicit")` gives.
    let entry: String
}

/// The keys that each elicitation answer must have, sorted. The keys are
/// written here, and not read from the source, so that the test holds the
/// shape that the plan sets.
private let elicitationAnswerKeys = ["action", "content", "reason"]

/// A snippet that asks one question and returns the `action` of the answer
/// and `String(content)`.
private let elicitationActionAndContentSnippet = """
    const answer = await elicit("Proceed?");
    return [answer.action, String(answer.content)];
    """

/// A snippet that asks one question and returns the sorted keys and the three
/// fields of the answer it gets.
private let elicitationAnswerSnippet = """
    const answer = await elicit("Proceed?");
    return {
        keys: Object.keys(answer).sort(),
        action: answer.action,
        content: answer.content,
        reason: answer.reason,
    };
    """

/// What ``elicitationAnswerSnippet`` returns.
private struct ElicitationAnswerProbe: Decodable, Equatable {
    /// The sorted keys of the answer.
    let keys: [String]

    /// The `action` of the answer.
    let action: String

    /// The `content` of the answer: the text of an accept of the text short
    /// form, or `nil` when it is `null`.
    let content: String?

    /// The `reason` of the answer, or `nil` when it is `null`.
    let reason: String?
}

/// Runs `snippet` under a stub run whose scripted sink gives `response` to
/// each elicitation, and decodes what the snippet returns.
///
/// - Parameters:
///   - snippet: the code to run.
///   - response: the answer the sink gives to each elicitation.
///   - type: the type that the output of the snippet decodes to.
/// - Returns: what the snippet returned.
/// - Throws: when the run fails, or when its output does not decode.
private func runElicitationSnippet<T: Decodable>(
    _ snippet: String, answering response: ElicitationResponse, decoding type: T.Type
) async throws -> T {
    try await withStubRun { stub in
        let context = stub.context
        return try await withScriptedElicitationSink(run: stub, answering: response) { _ in
            let output = try await runSnippet(snippet, under: context)
            return try RunOutput.decoded(type, from: output)
        }
    }
}

/// Runs ``elicitationAnswerSnippet`` under a stub run whose scripted sink
/// answers with `response`, and decodes what the snippet returns.
///
/// - Parameter response: the answer the sink gives.
/// - Returns: what the snippet got.
/// - Throws: when the run fails, or when its output does not decode.
private func elicitationAnswerProbe(answering response: ElicitationResponse) async throws -> ElicitationAnswerProbe {
    try await runElicitationSnippet(elicitationAnswerSnippet, answering: response, decoding: ElicitationAnswerProbe.self)
}

/// What the enumeration snippet of ``installedGlobalsProbe(expecting:under:)``
/// returns.
private struct InstalledGlobalsProbe: Decodable {
    /// The name of each installed global, and `name.member` for each own
    /// function member of one.
    let installed: [String]

    /// The names in ``installed`` whose `docs(name)` block does not start
    /// with the line `// <name>`.
    let misnamedBlocks: [String]

    /// Tells if `docs("globals")` gave the expected page.
    let pageIsServed: Bool
}

/// Makes a session context whose run plane has the user presence
/// `userPresence`.
///
/// The context has a run plane of its own and a sink that records, and no
/// Router session: the user presence is the only fact that these tests read.
///
/// - Parameter userPresence: tells if a user can answer questions.
/// - Returns: the context.
private func makeContext(userPresence: UserPresence) -> ToolContext {
    ToolContext(
        sessionID: ULID(),
        runPlane: RunPlane(userPresence: userPresence),
        sink: RecordingEventSink(),
        tool: "runCode",
        op: "runCode",
        completionToken: ToolContext.makeCompletionToken(),
        isCancelled: { false }
    )
}

/// The name of each function that a globals page or a `docs(name)` block
/// declares, in text order. A member of a namespace is named `space.member`.
///
/// - Parameter text: the rendered page or block.
/// - Returns: the declared function names.
private func declaredFunctionNames(in text: String) -> [String] {
    DeclaredFunction.all(in: text).map(\.name)
}

/// The names of the globals that the preface of the page tells a snippet to
/// await, in page order.
///
/// - Parameter page: the rendered globals page.
/// - Returns: each `name` of a `` `name()` `` between the await sentence and
///   the sentence on `notify()`; empty when the page has no such sentence.
private func awaitedNames(in page: String) -> [String] {
    guard
        let start = page.range(of: "Await the ones that return a promise:"),
        let end = page.range(of: "`notify()` and", range: start.upperBound..<page.endIndex)
    else {
        return []
    }
    return page[start.upperBound..<end.lowerBound].matches(of: /`([\w.]+)\(\)`/).map { String($0.1) }
}

/// The field names the globals page's `declare type` line for `name` lists,
/// sorted. The type can have type parameters, as `ElicitationAnswer<T>` has.
///
/// - Parameters:
///   - name: the declared type's name, without type parameters.
///   - page: the rendered globals page.
/// - Returns: the declared field names in sorted order, or `nil` when the page
///   declares no such type.
private func declaredFields(of name: String, in page: String) -> [String]? {
    let opening = "declare type \(name)"
    guard
        let line = page.split(separator: "\n").first(where: { line in
            line.hasPrefix(opening) && line.dropFirst(opening.count).wholeMatch(of: /(<[^>]*>)? = \{.*/) != nil
        }),
        let open = line.firstIndex(of: "{"),
        let close = line.lastIndex(of: "}")
    else {
        return nil
    }
    return line[line.index(after: open)..<close]
        .split(separator: ";")
        .compactMap { $0.split(separator: ":").first?.trimmingCharacters(in: .whitespaces) }
        .sorted()
}

// MARK: - The elicit helpers

/// The one field of the form that each elicit helper sends. The name is
/// written here, and not read from the source, so that the test holds the
/// field that the owner accepted.
private let elicitHelperAnswerField = "answer"

/// The form that `elicit("question")` sends: one required string field,
/// ``elicitHelperAnswerField``, with no constraints.
private let elicitShortFormSchema = ElicitationRequestedSchema(
    properties: [elicitHelperAnswerField: .string(ElicitationStringSchema())], required: [elicitHelperAnswerField])

/// The question that each helper call of this suite asks.
private let elicitHelperMessage = "Proceed?"

/// The question that a snippet asks after a bad call, so that the sink
/// observes one request.
private let elicitHelperFollowUpMessage = "Go on?"

/// The JS string literal of ``elicitHelperMessage``. The message holds no
/// character that needs an escape.
private let elicitHelperMessageLiteral = "\"\(elicitHelperMessage)\""

/// The two options of each `choose` and `chooseMany` call of this suite.
private let elicitHelperOptions = ["us", "eu"]

/// The JS array literal of ``elicitHelperOptions``.
private let elicitHelperOptionsLiteral = jsArrayLiteral(of: elicitHelperOptions)

/// A string that no helper call of ``elicitHelperCalls`` takes as an answer.
private let elicitHelperInvalidAnswer = "not an option"

/// The `min` and `max` counts of the `chooseMany` round trip that sets both.
/// The upper count lets the answer pick all of ``elicitHelperOptions``.
private let elicitHelperPickLimits = (minimum: 1, maximum: 2)

/// The `min` and `max` limits of the `askNumber` round trip that sets both.
private let elicitHelperNumberLimits = (minimum: 1, maximum: 10)

/// The answer of the `askNumber` round trip with no limits: a number that is
/// not a whole number.
private let elicitHelperFractionAnswer = 0.5

/// The answer of the `askNumber` round trip with limits: a whole number in
/// ``elicitHelperNumberLimits``.
private let elicitHelperWholeAnswer = 3

/// One call to each helper, in the order that a snippet makes them. The
/// `askText` call has a pattern that ``elicitHelperInvalidAnswer`` does not
/// match.
private let elicitHelperCalls = [
    "elicit.confirm(\(elicitHelperMessageLiteral))",
    "elicit.choose(\(elicitHelperMessageLiteral), \(elicitHelperOptionsLiteral))",
    "elicit.chooseMany(\(elicitHelperMessageLiteral), \(elicitHelperOptionsLiteral))",
    "elicit.askText(\(elicitHelperMessageLiteral), { pattern: \"[0-9]+\" })",
    "elicit.askNumber(\(elicitHelperMessageLiteral))",
]

/// The answer to one helper call, as the snippet reports it.
struct ElicitHelperAnswer: Decodable, Equatable {
    /// The `action` of the answer.
    let action: String

    /// `JSON.stringify` of the `content` of the answer.
    let content: String

    /// The `reason` of the answer, or `nil` when it is `null`.
    let reason: String?
}

/// One helper call, the answer that the sink gives to it, the form that it
/// must send, and the content that the snippet must get.
struct ElicitHelperRoundTrip: Sendable, CustomTestStringConvertible {
    /// The JS expression of the call.
    let call: String

    /// The value of the `answer` field of the accept.
    let answer: ElicitationValue

    /// The form that the call must send.
    let schema: ElicitationRequestedSchema

    /// `JSON.stringify` of the `content` that the snippet must get.
    let content: String

    /// The call, as the name of the test case.
    var testDescription: String { call }

    /// Makes a round trip whose form has the one required field `answer`.
    ///
    /// - Parameters:
    ///   - call: the JS expression of the call.
    ///   - answer: the value of the `answer` field of the accept.
    ///   - field: the schema of the `answer` field.
    ///   - content: `JSON.stringify` of the expected `content`.
    init(call: String, answer: ElicitationValue, field: ElicitationPrimitiveSchema, content: String) {
        self.call = call
        self.answer = answer
        self.schema = ElicitationRequestedSchema(properties: [elicitHelperAnswerField: field], required: [elicitHelperAnswerField])
        self.content = content
    }
}

/// The round trip of each helper, with and without its optional argument.
let elicitHelperRoundTrips: [ElicitHelperRoundTrip] = [
    ElicitHelperRoundTrip(
        call: "elicit.confirm(\(elicitHelperMessageLiteral))",
        answer: .boolean(true), field: .boolean(ElicitationBooleanSchema()), content: "true"),
    ElicitHelperRoundTrip(
        call: "elicit.choose(\(elicitHelperMessageLiteral), \(elicitHelperOptionsLiteral))",
        answer: .string("eu"), field: .singleSelect(ElicitationSingleSelectSchema(values: elicitHelperOptions)),
        content: "\"eu\""),
    ElicitHelperRoundTrip(
        call: "elicit.chooseMany(\(elicitHelperMessageLiteral), \(elicitHelperOptionsLiteral))",
        answer: .stringArray(["us"]), field: .multiSelect(ElicitationMultiSelectSchema(values: elicitHelperOptions)),
        content: "[\"us\"]"),
    ElicitHelperRoundTrip(
        call: """
            elicit.chooseMany(\(elicitHelperMessageLiteral), \(elicitHelperOptionsLiteral), \
            { min: \(elicitHelperPickLimits.minimum), max: \(elicitHelperPickLimits.maximum) })
            """,
        answer: .stringArray(["us", "eu"]),
        field: .multiSelect(
            ElicitationMultiSelectSchema(
                values: elicitHelperOptions,
                minItems: elicitHelperPickLimits.minimum, maxItems: elicitHelperPickLimits.maximum)),
        content: "[\"us\",\"eu\"]"),
    ElicitHelperRoundTrip(
        call: "elicit.askText(\(elicitHelperMessageLiteral))",
        answer: .string("Ada"), field: .string(ElicitationStringSchema()), content: "\"Ada\""),
    ElicitHelperRoundTrip(
        call: "elicit.askText(\(elicitHelperMessageLiteral), { format: \"email\", pattern: \"[a-z]+@example[.]com\" })",
        answer: .string("ada@example.com"),
        field: .string(ElicitationStringSchema(format: .email, pattern: "[a-z]+@example[.]com")),
        content: "\"ada@example.com\""),
    ElicitHelperRoundTrip(
        call: "elicit.askNumber(\(elicitHelperMessageLiteral))",
        answer: .number(elicitHelperFractionAnswer), field: .number(ElicitationNumberSchema(type: .number)),
        content: "\(elicitHelperFractionAnswer)"),
    ElicitHelperRoundTrip(
        call: """
            elicit.askNumber(\(elicitHelperMessageLiteral), \
            { min: \(elicitHelperNumberLimits.minimum), max: \(elicitHelperNumberLimits.maximum), integer: true })
            """,
        answer: .number(Double(elicitHelperWholeAnswer)),
        field: .number(
            ElicitationNumberSchema(
                type: .integer,
                minimum: Double(elicitHelperNumberLimits.minimum), maximum: Double(elicitHelperNumberLimits.maximum))),
        content: "\(elicitHelperWholeAnswer)"),
]

/// One helper call with bad arguments.
struct ElicitHelperArgumentError: Sendable, CustomTestStringConvertible {
    /// The name of the helper, for example `elicit.choose`.
    let helper: String

    /// The JS expression of the bad call.
    let call: String

    /// The call, as the name of the test case.
    var testDescription: String { call }
}

/// The bad calls: a wrong type or a missing value, a value that the form
/// cannot hold, and an option name that the helper does not know.
let elicitHelperArgumentErrors: [ElicitHelperArgumentError] = [
    ElicitHelperArgumentError(helper: "elicit.confirm", call: "elicit.confirm()"),
    ElicitHelperArgumentError(helper: "elicit.confirm", call: "elicit.confirm(42)"),
    ElicitHelperArgumentError(helper: "elicit.choose", call: "elicit.choose(\"Pick\")"),
    ElicitHelperArgumentError(helper: "elicit.choose", call: "elicit.choose(\"Pick\", \"us\")"),
    ElicitHelperArgumentError(helper: "elicit.choose", call: "elicit.choose(\"Pick\", [])"),
    ElicitHelperArgumentError(helper: "elicit.choose", call: "elicit.choose(\"Pick\", [\"us\", 2])"),
    ElicitHelperArgumentError(helper: "elicit.chooseMany", call: "elicit.chooseMany(\"Pick\", [\"us\"], { min: 2, max: 1 })"),
    ElicitHelperArgumentError(helper: "elicit.chooseMany", call: "elicit.chooseMany(\"Pick\", [\"us\"], { min: 1.5 })"),
    ElicitHelperArgumentError(helper: "elicit.chooseMany", call: "elicit.chooseMany(\"Pick\", [\"us\"], { max: -1 })"),
    ElicitHelperArgumentError(helper: "elicit.chooseMany", call: "elicit.chooseMany(\"Pick\", [\"us\"], { most: 1 })"),
    ElicitHelperArgumentError(helper: "elicit.askText", call: "elicit.askText(\"Name?\", { format: \"phone\" })"),
    ElicitHelperArgumentError(helper: "elicit.askText", call: "elicit.askText(\"Name?\", { pattern: \"(\" })"),
    ElicitHelperArgumentError(helper: "elicit.askText", call: "elicit.askText(\"Name?\", \"email\")"),
    ElicitHelperArgumentError(helper: "elicit.askNumber", call: "elicit.askNumber(\"How many?\", { min: \"1\" })"),
    ElicitHelperArgumentError(helper: "elicit.askNumber", call: "elicit.askNumber(\"How many?\", { min: 5, max: 1 })"),
    ElicitHelperArgumentError(helper: "elicit.askNumber", call: "elicit.askNumber(\"How many?\", { integer: \"yes\" })"),
]

/// Runs each call of ``elicitHelperCalls`` in turn under a stub run whose
/// scripted sink gives `response` to each one, and decodes what the snippet
/// got.
///
/// - Parameter response: the answer the sink gives to each call.
/// - Returns: the answer to each call, in call order.
/// - Throws: when the run fails, or when its output does not decode.
private func elicitHelperAnswers(answering response: ElicitationResponse) async throws -> [ElicitHelperAnswer] {
    try await runElicitationSnippet(
        """
        const calls = [\(elicitHelperCalls.map { "() => \($0)" }.joined(separator: ", "))];
        const answers = [];
        for (const call of calls) {
            const answer = await call();
            answers.push({ action: answer.action, content: JSON.stringify(answer.content), reason: answer.reason });
        }
        return answers;
        """,
        answering: response,
        decoding: [ElicitHelperAnswer].self
    )
}

/// The member name of each helper that the interactive globals page
/// declares in the `elicit` namespace, in page order.
///
/// - Returns: the member names, for example `confirm`.
private func documentedElicitHelperMembers() -> [String] {
    let prefix = "\(MultiTool.elicitGlobalName)."
    return documentedGlobalNames().filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
}
