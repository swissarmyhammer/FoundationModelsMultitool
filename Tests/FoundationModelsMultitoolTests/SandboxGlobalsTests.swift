import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Every sandbox global this suite pins, in the order the surface documents
/// them — the run verbs, the elicitation, and the two notice calls.
private let sandboxGlobalNames = ["status", "wait", "cancel", "elicit", "notify", "progress"]

/// A `wait()` deadline long enough that a settled run always resolves inside
/// it — never used to bound a run that is expected to stay parked.
private let generousWaitSeconds = 10

/// A `wait()` deadline already elapsed by the time the call reaches the
/// mailbox, so a still-parked run reports `deadlineElapsed` without the test
/// sleeping.
private let elapsedWaitSeconds = 0

/// Phase-1 coverage for the six ambient sandbox globals — eventplan.md § "The
/// sandbox globals" and § "Async JavaScript"'s one-rule contract ("each call
/// that goes into Swift effects returns a promise… these calls are
/// synchronous: `help()` and `docs()`… and `notify()` / `progress()`").
///
/// Every run-plane assertion drives a real `SessionMailbox` — a real parked
/// run, a real settlement, a real elicitation reply — under an ambient
/// `ToolContext` the test owns, so what is exercised is the actual Router
/// surface rather than a stand-in for it.
@Suite("Sandbox globals")
struct SandboxGlobalsTests {
    // MARK: - Reachability and the promise-vs-sync contract

    @Test("all six globals are reachable in a fresh run")
    func allSixGlobalsAreReachable() async throws {
        let output = try await runSnippet(
            """
            return \(jsArrayLiteral(of: sandboxGlobalNames)).map(name => typeof globalThis[name]);
            """
        )

        let kinds = try decode([String].self, from: output)
        #expect(kinds == Array(repeating: "function", count: sandboxGlobalNames.count))
    }

    @Test("the globals are not discoverable entries — help() and the findAPIs surface list none of them")
    func globalsAreNotDiscoverableEntries() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return help();"))

        let helpPaths = try decode([String].self, from: output)
        #expect(helpPaths == ["getCities"])
        let surfacePaths = Set(registry.surface.entries.map(\.path))
        #expect(surfacePaths.isDisjoint(with: sandboxGlobalNames))
    }

    @Test("the run verbs return promises; notify, progress, help, and docs return plain values")
    func promiseVersusSynchronousContractHolds() async throws {
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        let output = try await runSnippet(
            """
            return [
                "status:" + typeof status().then,
                "wait:" + typeof wait("no-such-token", \(elapsedWaitSeconds)).then,
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
            try decode([String].self, from: output) == [
                "status:function",
                "wait:function",
                "cancel:function",
                "notify:undefined",
                "progress:undefined",
                "help:undefined",
                "docs:undefined",
            ]
        )
    }

    // MARK: - Discovery: docs() carries the contract the description points at

    @Test("docs(\"globals\") declares every ambient global")
    func docsGlobalsDeclaresEveryAmbientGlobal() async throws {
        let output = try await runSnippet("return docs(\"\(MultiTool.sandboxGlobalsDocsTopic)\");")

        let page = try decode(String.self, from: output)
        for name in sandboxGlobalNames {
            #expect(page.contains("declare function \(name)("))
        }
    }

    @Test("docs(\"globals\") reaches the snippet whole — runCode's return cap never truncates the contract")
    func theGlobalsPageReachesTheSnippetWhole() async throws {
        let output = try await runSnippet("return docs(\"\(MultiTool.sandboxGlobalsDocsTopic)\");")

        #expect(try decode(String.self, from: output) == MultiTool.sandboxGlobalsPage)
    }

    @Test("docs(name) resolves each ambient global on its own, returning that one's block alone")
    func docsResolvesEachAmbientGlobalByName() async throws {
        for name in sandboxGlobalNames {
            let output = try await runSnippet("return docs(\"\(name)\");")

            let block = try decode(String.self, from: output)
            #expect(sandboxGlobalNames.filter { block.contains("declare function \($0)(") } == [name])
        }
    }

    @Test("the globals page states which calls are awaited by declaring their return types")
    func theGlobalsPageStatesWhichCallsAreAwaited() {
        let page = MultiTool.sandboxGlobalsPage

        for name in sandboxGlobalNames where !MultiTool.voidGlobalNames.contains(name) {
            #expect(declaredReturnType(of: name, in: page)?.hasPrefix("Promise<") == true)
        }
        for name in MultiTool.voidGlobalNames {
            #expect(declaredReturnType(of: name, in: page) == "void")
        }
    }

    @Test("the globals page declares the exact fields a parked run really reports")
    func theGlobalsPageMatchesTheParkedRunItDocuments() async throws {
        let mailbox = SessionMailbox()
        _ = await parkScriptedRun(in: mailbox, progress: "step one")
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())

        let output = try await runSnippet(
            "return Object.keys((await status())[0]).sort();",
            under: context
        )

        let observed = try decode([String].self, from: output)
        let documented = try #require(declaredFields(of: "ParkedRun", in: MultiTool.sandboxGlobalsPage))
        #expect(documented == observed)
    }

    @Test("the globals page declares the exact fields an elicitation answer really carries")
    func theGlobalsPageMatchesTheElicitationAnswerItDocuments() async throws {
        let mailbox = SessionMailbox()
        let sink = ScriptedElicitationSink(mailbox: mailbox, answering: .accept(content: ["repo": .string("sah")]))
        let context = makeOuterRunContext(mailbox: mailbox, sink: sink)

        let output = try await runSnippet(
            "return Object.keys(await elicit(\"Which repository?\")).sort();",
            under: context
        )

        let observed = try decode([String].self, from: output)
        let documented = try #require(declaredFields(of: "ElicitationAnswer", in: MultiTool.sandboxGlobalsPage))
        #expect(documented == observed)
    }

    // MARK: - status()

    @Test("status() with no argument lists each parked run's token, op, and latest progress")
    func statusWithNoArgumentListsEveryParkedRun() async throws {
        let mailbox = SessionMailbox()
        let run = await parkScriptedRun(in: mailbox, op: "run shell", progress: "downloading")
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())

        let output = try await runSnippet(
            "return (await status()).map(row => [row.completionToken, row.op, row.latestProgress]);",
            under: context
        )

        #expect(try decode([[String?]].self, from: output) == [[run.completionToken, "run shell", "downloading"]])
    }

    @Test("status(completionToken) reports a parked run's lifecycle")
    func statusWithATokenReportsAParkedRun() async throws {
        let mailbox = SessionMailbox()
        let run = await parkScriptedRun(in: mailbox, progress: "step one")
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())

        let output = try await runSnippet(
            """
            const row = await status("\(run.completionToken)");
            return [row.state, row.completionToken, row.op, row.kind, row.latestProgress];
            """,
            under: context
        )

        #expect(
            try decode([String?].self, from: output) == [
                "parked", run.completionToken, "run shell", "swiftTask", "step one",
            ]
        )
    }

    @Test("status(completionToken) reports a settled run's terminal outcome")
    func statusWithATokenReportsASettledRun() async throws {
        let mailbox = SessionMailbox()
        let run = await parkScriptedRun(in: mailbox)
        await settle(run, in: mailbox)
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())

        let output = try await runSnippet(
            """
            const row = await status("\(run.completionToken)");
            return [row.state, row.completionToken, row.detail, row.outcome];
            """,
            under: context
        )

        #expect(
            try decode([String?].self, from: output) == [
                "settled", run.completionToken, "scripted-terminal-detail", "succeeded",
            ]
        )
    }

    @Test("status(completionToken) reports an unknown token as a safe no-op, never a throw")
    func statusWithAnUnknownTokenIsASafeNoOp() async throws {
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        let output = try await runSnippet(
            """
            const row = await status("no-such-token");
            return [row.state, row.completionToken];
            """,
            under: context
        )

        #expect(try decode([String].self, from: output) == ["unknownToken", "no-such-token"])
    }

    // MARK: - wait()

    @Test("wait() returns the terminal event's detail and the run's identifier")
    func waitReturnsTheTerminalEventDetailAndIdentifier() async throws {
        let mailbox = SessionMailbox()
        let run = await parkScriptedRun(in: mailbox)
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())
        await settle(run, in: mailbox)

        let output = try await runSnippet(
            """
            const settled = await wait("\(run.completionToken)", \(generousWaitSeconds));
            return [settled.state, settled.completionToken, settled.detail, settled.outcome];
            """,
            under: context
        )

        #expect(
            try decode([String?].self, from: output) == [
                "settled", run.completionToken, "scripted-terminal-detail", "succeeded",
            ]
        )
    }

    @Test("wait()'s detail is the run plane's bounded output tail, never a capability's full store")
    func waitDetailIsBoundedToTheRunPlaneTail() async throws {
        let overlongDetail = String(repeating: "d", count: SessionMailbox.terminalDetailTailLimit + 500)
        let mailbox = SessionMailbox()
        let run = await parkScriptedRun(in: mailbox, detail: overlongDetail)
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())
        await settle(run, in: mailbox)

        let output = try await runSnippet(
            "return (await wait(\"\(run.completionToken)\", \(generousWaitSeconds))).detail.length;",
            under: context
        )

        #expect(try decode(Int.self, from: output) == SessionMailbox.terminalDetailTailLimit)
    }

    @Test("wait() reports an elapsed deadline while the run stays parked")
    func waitReportsAnElapsedDeadline() async throws {
        let mailbox = SessionMailbox()
        let run = await parkScriptedRun(in: mailbox)
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())

        let output = try await runSnippet(
            """
            const outcome = await wait("\(run.completionToken)", \(elapsedWaitSeconds));
            return [outcome.state, outcome.completionToken];
            """,
            under: context
        )

        #expect(try decode([String].self, from: output) == ["deadlineElapsed", run.completionToken])
        #expect(await mailbox.status().map(\.completionToken) == [run.completionToken])
    }

    @Test("wait() reports an unknown token as a safe no-op, never a throw")
    func waitWithAnUnknownTokenIsASafeNoOp() async throws {
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        let output = try await runSnippet(
            """
            const outcome = await wait("no-such-token", \(elapsedWaitSeconds));
            return [outcome.state, outcome.completionToken];
            """,
            under: context
        )

        #expect(try decode([String].self, from: output) == ["unknownToken", "no-such-token"])
    }

    @Test("wait() called without a seconds deadline rejects with a repairable error naming the shape")
    func waitWithoutADeadlineRejectsRepairably() async throws {
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        let output = try await runSnippet(
            """
            try {
                await wait("no-such-token");
                return "no-throw";
            } catch (error) {
                return String(error.message);
            }
            """,
            under: context
        )

        let message = try decode(String.self, from: output)
        #expect(message.hasPrefix("wait: "))
        #expect(message.contains("wait(completionToken, seconds)"))
    }

    // MARK: - cancel()

    @Test("cancel() returns the canceler's honest outcome, verbatim")
    func cancelReturnsTheHonestOutcome() async throws {
        let mailbox = SessionMailbox()
        let run = await parkScriptedRun(in: mailbox)
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())

        let output = try await runSnippet(
            """
            const outcome = await cancel("\(run.completionToken)");
            return [outcome.state, outcome.completionToken, outcome.outcome];
            """,
            under: context
        )

        #expect(
            try decode([String].self, from: output) == [
                "reported", run.completionToken, scriptedRunCancelOutcome.rawValue,
            ]
        )
    }

    @Test("cancel() on a run that already finished reports the retained terminal event, not an unknown token")
    func cancelOnASettledRunReportsItsTerminalEvent() async throws {
        let mailbox = SessionMailbox()
        let run = await parkScriptedRun(in: mailbox)
        await settle(run, in: mailbox)
        let context = makeOuterRunContext(mailbox: mailbox, sink: RecordingEventSink())

        let output = try await runSnippet(
            """
            const outcome = await cancel("\(run.completionToken)");
            return [outcome.state, outcome.completionToken, outcome.detail, outcome.outcome];
            """,
            under: context
        )

        #expect(
            try decode([String?].self, from: output) == [
                "alreadySettled", run.completionToken, "scripted-terminal-detail", "succeeded",
            ]
        )
    }

    @Test("cancel() reports an unknown token as a safe no-op, never a throw")
    func cancelWithAnUnknownTokenIsASafeNoOp() async throws {
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        let output = try await runSnippet(
            """
            const outcome = await cancel("no-such-token");
            return [outcome.state, outcome.completionToken];
            """,
            under: context
        )

        #expect(try decode([String].self, from: output) == ["unknownToken", "no-such-token"])
    }

    // MARK: - elicit()

    @Test("elicit(\"question\") parks the snippet and resumes with the accepted answer")
    func elicitStringShorthandRoundTripsAnAcceptedAnswer() async throws {
        let mailbox = SessionMailbox()
        let sink = ScriptedElicitationSink(
            mailbox: mailbox,
            answering: .accept(content: ["repo": .string("swissarmyhammer")])
        )
        let context = makeOuterRunContext(mailbox: mailbox, sink: sink)

        let output = try await runSnippet(
            """
            const pending = elicit("Which repository should I target?");
            const isThenable = typeof pending.then === "function";
            const answer = await pending;
            return [String(isThenable), answer.action, answer.content.repo];
            """,
            under: context
        )

        #expect(try decode([String].self, from: output) == ["true", "accept", "swissarmyhammer"])
        let request = try #require(await sink.observedRequest)
        #expect(request.mode == .form)
        #expect(request.message == "Which repository should I target?")
        #expect(request.requestedSchema?.properties.isEmpty == true)
        #expect(await sink.deliveries == [.delivered])
    }

    @Test("a declined elicitation surfaces as a decline, distinct from a cancel")
    func elicitSurfacesADeclineDistinctly() async throws {
        let mailbox = SessionMailbox()
        let sink = ScriptedElicitationSink(mailbox: mailbox, answering: .decline)
        let context = makeOuterRunContext(mailbox: mailbox, sink: sink)

        let output = try await runSnippet(
            """
            const answer = await elicit("Proceed?");
            return [answer.action, String(answer.content)];
            """,
            under: context
        )

        #expect(try decode([String].self, from: output) == ["decline", "null"])
    }

    @Test("a cancelled elicitation surfaces as a cancel, distinct from a decline")
    func elicitSurfacesACancelDistinctly() async throws {
        let mailbox = SessionMailbox()
        let sink = ScriptedElicitationSink(mailbox: mailbox, answering: .cancel)
        let context = makeOuterRunContext(mailbox: mailbox, sink: sink)

        let output = try await runSnippet(
            """
            const answer = await elicit("Proceed?");
            return [answer.action, String(answer.content)];
            """,
            under: context
        )

        #expect(try decode([String].self, from: output) == ["cancel", "null"])
    }

    @Test("elicit({ message, requestedSchema }) carries the restricted form schema through unchanged")
    func elicitCarriesAFormSchemaThrough() async throws {
        let mailbox = SessionMailbox()
        let sink = ScriptedElicitationSink(
            mailbox: mailbox,
            answering: .accept(content: ["repo": .string("multitool")])
        )
        let context = makeOuterRunContext(mailbox: mailbox, sink: sink)

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

        #expect(try decode([String].self, from: output) == ["accept", "multitool"])
        let request = try #require(await sink.observedRequest)
        #expect(request.mode == .form)
        #expect(request.requestedSchema?.required == ["repo"])
        guard case .string(let repoSchema)? = request.requestedSchema?.properties["repo"] else {
            Issue.record("the repo property did not decode as a string schema")
            return
        }
        #expect(repoSchema.title == "Repository")
    }

    @Test("elicit({ message, url }) resolves only once the out-of-band flow completes")
    func elicitUrlModeResolvesAfterCompletion() async throws {
        let mailbox = SessionMailbox()
        let sink = ScriptedElicitationSink(mailbox: mailbox, answering: .accept(content: nil))
        let context = makeOuterRunContext(mailbox: mailbox, sink: sink)

        let output = try await runSnippet(
            """
            const answer = await elicit({ message: "Sign in", url: "https://example.com/auth" });
            return answer.action;
            """,
            under: context
        )

        #expect(try decode(String.self, from: output) == "accept")
        let request = try #require(await sink.observedRequest)
        #expect(request.mode == .url)
        #expect(request.url == URL(string: "https://example.com/auth"))
        #expect(await sink.deliveries == [.acceptedAwaitingCompletion])
        #expect(await sink.completions == [.completed])
    }

    @Test("elicit() with neither a question nor a message rejects with a repairable error naming the shape")
    func elicitWithoutAMessageRejectsRepairably() async throws {
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

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

        let message = try decode(String.self, from: output)
        #expect(message.hasPrefix("elicit: "))
        #expect(message.contains("elicit(\"question\")"))
    }

    // MARK: - notify() / progress()

    @Test("notify() and progress() reach the session's sink on the run's own correlation")
    func noticesReachTheSinkOnTheRunsCorrelation() async throws {
        let sink = RecordingEventSink()
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: sink)

        let output = try await runSnippet(
            """
            notify("starting the sweep");
            progress("half way");
            return "done";
            """,
            under: context
        )

        #expect(try decode(String.self, from: output) == "done")
        #expect(await sink.details(ofKind: .progress) == ["starting the sweep", "half way"])
        #expect(await sink.events.allSatisfy { $0.correlationID == context.completionToken })
    }

    @Test("a long snippet loop's notices reach the sink in the order the snippet enqueued them")
    func noticesArriveInSnippetOrder() async throws {
        let sink = RecordingEventSink()
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: sink)

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
            await sink.details(ofKind: .progress) == ["step 1", "step 2", "step 3", "step 4", "finished"]
        )
    }

    // MARK: - No ambient context: the run plane is absent, not broken

    @Test("each run-plane global rejects with a named, repairable error when the run has no session context")
    func runPlaneGlobalsRejectWithoutASessionContext() async throws {
        let output = try await runSnippet(
            """
            const calls = [
                ["status", () => status()],
                ["wait", () => wait("no-such-token", \(elapsedWaitSeconds))],
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

        let messages = try decode([String].self, from: output)
        #expect(messages.count == 4)
        for (name, message) in zip(["status", "wait", "cancel", "elicit"], messages) {
            #expect(message.hasPrefix("\(name): "))
            #expect(message.contains("no session context — this run has no run plane"))
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

        #expect(try decode(String.self, from: output) == "done")
    }
}

// MARK: - Suite helpers

/// Runs one snippet through a `runCode` tool over an empty registry, under
/// `context` when one is given.
///
/// An empty registry keeps every assertion about the globals themselves: the
/// six are installed unconditionally, so no wrapped tool has to exist for them
/// to be reachable. Passing `nil` for `context` is the no-ambient-context mode
/// every other unit suite in this package runs in — a `MultiTool` constructed
/// and called directly, outside any session.
///
/// - Parameters:
///   - code: the snippet to run.
///   - context: the ambient session context to bind around the call, or `nil`
///     to run with no run plane at all.
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

/// Decodes a rendered `runCode` result — always JSON, per `ResultRenderer` —
/// back into the value the snippet returned.
///
/// - Parameters:
///   - type: the value type to decode.
///   - output: the rendered result.
/// - Returns: the decoded value.
/// - Throws: a `DecodingError` when `output` is not the expected shape, which
///   for a `runCode` result means the snippet failed and the renderer produced
///   repairable-error text instead.
private func decode<Value: Decodable>(_ type: Value.Type, from output: String) throws -> Value {
    try JSONDecoder().decode(type, from: Data(output.utf8))
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
    guard
        let line = page.split(separator: "\n").first(where: { $0.hasPrefix("declare function \(name)(") }),
        let arguments = line.range(of: "): ", options: .backwards)
    else {
        return nil
    }
    return String(line[arguments.upperBound...].dropLast())
}

/// The field names the globals page's `declare type` line for `name` lists,
/// sorted.
///
/// - Parameters:
///   - name: the declared type's name.
///   - page: the rendered globals page.
/// - Returns: the declared field names in sorted order, or `nil` when the page
///   declares no such type.
private func declaredFields(of name: String, in page: String) -> [String]? {
    guard
        let line = page.split(separator: "\n").first(where: { $0.hasPrefix("declare type \(name) = {") }),
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
