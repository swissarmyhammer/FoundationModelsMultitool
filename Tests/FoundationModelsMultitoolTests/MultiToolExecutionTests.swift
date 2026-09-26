import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing
import os

@testable import FoundationModelsMultitool

/// M4a coverage for `MultiTool`: the `runCode` `Tool` conformance that wires
/// together every prior milestone — `JSCInterpreter` (M1), `ArgumentMarshaler`
/// + `ToolInvoker` (M3), `MultiTool.Builder` + `APISurface` (M2.5), and
/// `ResultRenderer` (M5) — into a single working execution path: `tools.*`
/// installed in a fresh sandbox per call, dispatching into real wrapped
/// `Tool`s. No model is needed for any of this; `RunCodeArguments` is built
/// directly, standing in for what a real agent loop (M4b) would decode.
@Suite("MultiToolExecution")
struct MultiToolExecutionTests {
    // MARK: - The runCode envelope (eventplan.md § "The constraint boundary")

    @Test("runCode's schema exposes code alone — waiting is not one of its options")
    func runCodeSchemaExposesCodeAlone() throws {
        let registry = try MultiTool.Builder().addTool(TempTool()).buildRegistry()

        let schema = try ToolAPIRenderer.jsonSchemaString(for: MultiTool(registry: registry).parameters)

        #expect(schema.contains("code"))
        // `runCode` always backgrounds, so the concept of waiting is out of the
        // schema rather than set to zero (task ^cv98vff). A model cannot ask
        // for a shape this tool does not have.
        #expect(!schema.contains("waitSeconds"))
        #expect(!schema.contains("timeout"))
    }

    /// A snippet can run for hours, so the tool states the background mount
    /// itself rather than take whatever mount its composition site applies.
    /// The per-call work bound stays with the tool as well, thus no site can
    /// raise it over the configured ceiling.
    @Test("runCode declares the background mount, and bounds each call at the configured ceiling")
    func runCodeDeclaresTheBackgroundMount() throws {
        let ceiling: TimeInterval = 30
        let registry = try MultiTool.Builder().addTool(TempTool()).buildRegistry()
        let multiTool = MultiTool(
            registry: registry, configuration: MultiToolConfiguration(executionTimeLimit: ceiling))

        #expect(multiTool.mount == ToolMount(mode: .background, timeout: nil))
        let bound = multiTool.timeout(from: RunCodeArguments(code: "return 1;").generatedContent)
        #expect(bound == ceiling)
    }

    @Test("runCode arguments carrying only code still decode")
    func runCodeArgumentsDecodeFromCodeAlone() async throws {
        let registry = try MultiTool.Builder().addTool(TempTool()).buildRegistry()
        let content = try ArgumentMarshaler.marshalArguments(.object(["code": .string("return 1 + 1;")]))

        let arguments = try RunCodeArguments(content)

        #expect(arguments.code == "return 1 + 1;")
        #expect(try await MultiTool(registry: registry).call(arguments: arguments) == "2")
    }

    // MARK: - Composition: intermediates stay in the sandbox

    @Test("composing two tools in one snippet returns only the final value; intermediates never appear in the rendered output")
    func composedSnippetReturnsOnlyFinalValue() async throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .addTool(TempTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: """
                const cities = (await tools.getCities()).cities;
                const temps = [];
                for (const c of cities) {
                  temps.push((await tools.getTemperature({ city: c })).tempC);
                }
                return Math.max(...temps);
                """)
        )

        #expect(output == "33")
        for intermediate in ["AAA", "BBB", "CCC", "11", "22"] {
            #expect(!output.contains(intermediate))
        }
    }

    // MARK: - Grouped-namespace dispatch

    @Test("tools.github.<name> dispatches to the correct grouped tool")
    func groupedCallDispatchesToCorrectTool() async throws {
        let registry = try MultiTool.Builder()
            .addGroup(named: "github", [IssueCountTool()])
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return (await tools.github.getIssueCount({ repo: 'demo' })).count;")
        )

        #expect(output == "42")
    }

    // MARK: - The async promise-pump bridge (eventplan.md "Async JavaScript")

    @Test("an async (delayed) tool's result arrives through the promise-pump bridge, off the main thread, when the snippet's unawaited return settles at the boundary")
    func delayedToolResolvesThroughTheAsyncBridge() async throws {
        let delayedTool = DelayedTool()
        let registry = try MultiTool.Builder()
            .addTool(delayedTool)
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        // `return tools.delayed();`, with no `await`, is correct per
        // eventplan.md: "An unawaited return settles at the boundary...
        // `return tools.x.y(...)` is correct."
        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return tools.delayed();"))

        #expect(output == "\"delayed-result\"")
        #expect(delayedTool.ranOnMainThread == false)
    }

    @Test("an explicitly awaited tools.* call resolves to the tool's real result")
    func awaitedDelayedToolCallResolvesToItsValue() async throws {
        let delayedTool = DelayedTool()
        let registry = try MultiTool.Builder()
            .addTool(delayedTool)
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "const result = await tools.delayed(); return result;")
        )

        #expect(output == "\"delayed-result\"")
        #expect(delayedTool.ranOnMainThread == false)
    }

    @Test("Promise.all over two slow tools.* calls completes in ~max, not ~sum, of their durations")
    func promiseAllRunsToolCallsConcurrently() async throws {
        let toolA = WindowRecordingTool(name: "slowA", delayNanoseconds: 150_000_000)
        let toolB = WindowRecordingTool(name: "slowB", delayNanoseconds: 150_000_000)
        let registry = try MultiTool.Builder()
            .addTool(toolA)
            .addTool(toolB)
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: """
                await Promise.all([tools.slowA(), tools.slowB()]);
                return "done";
                """)
        )
        // This snippet fires both calls and answers with a status word, so it
        // carries nothing either call returned and the run closes with
        // `ToolReturnLedger`'s notice. That is the notice reporting correctly
        // rather than noise — the whole output is asserted, not a loosened
        // comparison, so a reword of the notice reaches this test too.
        #expect(output == "\"done\"\n\n\(ToolReturnLedger.uncarriedReturnNotice)")

        let windowA = try #require(toolA.window)
        let windowB = try #require(toolB.window)
        let callA = windowA.start.duration(to: windowA.end)
        let callB = windowB.start.duration(to: windowB.end)
        let span = min(windowA.start, windowB.start)
            .duration(to: max(windowA.end, windowB.end))
        // How much of the two calls ran at the same time: their durations added
        // together, less the span they jointly occupy. Serialized calls leave
        // disjoint windows, so this is zero or negative however slow the box is.
        let overlap = (callA + callB) - span
        // Half of the shorter call. Serialized execution overlaps by nothing at
        // all, so any positive share separates the two cases; a half leaves room
        // for scheduling jitter without pinning the test to a wall-clock speed.
        let minimumOverlapShare = 0.5
        // Read from the calls' own clocks rather than the turn's, so machine load
        // stretches both sides of the comparison together. No absolute budget on
        // the whole turn can separate these cases: a genuinely concurrent run has
        // been measured at 319ms under load, slower than the 321ms a serialized
        // control measures on an idle box.
        #expect(overlap >= min(callA, callB) * minimumOverlapShare)
    }

    @Test("a floating (unawaited) tools.* call still completes its real work before runCode returns")
    func floatingToolCallSettlesBeforeReturn() async throws {
        let delayedTool = DelayedTool()
        let registry = try MultiTool.Builder()
            .addTool(delayedTool)
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "tools.delayed(); return \"done\";")
        )

        // The floating call is the point of this test, and it is also exactly
        // the shape `ToolReturnLedger` reports: a call fired, its value never
        // read, and a status word answered in its place. So the run closes with
        // that notice, and the whole output is asserted rather than a loosened
        // comparison.
        #expect(output == "\"done\"\n\n\(ToolReturnLedger.uncarriedReturnNotice)")
        #expect(delayedTool.ranOnMainThread != nil)
    }

    @Test("a validation failure inside an awaited tools.* call rejects with the identical ToolInvokerError message text the v1 blocking bridge produced")
    func awaitedValidationFailureRejectsWithIdenticalMessageText() async throws {
        let registry = try MultiTool.Builder().addTool(TempTool()).buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: """
                try {
                  await tools.getTemperature({});
                  return "unreachable";
                } catch (e) {
                  return e.message;
                }
                """)
        )
        let message = try JSONDecoder().decode(String.self, from: Data(output.utf8))

        #expect(message.hasSuffix("Tool \"getTemperature\" is missing its required argument \"city\"."))
    }

    // MARK: - Mis-called tool: repairable error, not a crash

    @Test("a mis-called tool (missing required argument) surfaces ResultRenderer's repairable error text, not a crash")
    func misCalledToolSurfacesRepairableErrorText() async throws {
        let registry = try MultiTool.Builder()
            .addTool(TempTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return tools.getTemperature({});"))

        #expect(output.contains(RepairDirective.repairSnippet.closingLine))
        #expect(output.contains("city"))
    }

    // MARK: - Description: the no-system-prompt error-recovery contract

    @Test("runCode's description alone carries the searchTools-first workflow and the error-recovery contract — no system prompt required")
    func descriptionCarriesTheErrorRecoveryContract() throws {
        let registry = try MultiTool.Builder().addTool(TempTool()).buildRegistry()
        // Collapse the multiline literal's hard line-wraps to single spaces
        // so an assertion probes the guidance, not incidental wrapping.
        let description = MultiTool(registry: registry)
            .description
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        // runCode is a general-purpose isolated runtime. `sessionInstructions`
        // no longer exists (task tkrdwb8), so the contract lives entirely in the
        // two mounted descriptions, and task 5qadve5 split it between them: the
        // mandate to search first is asserted once, on searchTools' own
        // description, which is in the prompt alongside this one. runCode's
        // share is the sentence pointing the snippet at what searchTools returned.
        #expect(description.contains("isolated JavaScript runtime"))
        #expect(description.contains("arithmetic, string work, dates, sorting"))
        #expect(!description.localizedCaseInsensitiveContains("real-time"))
        // The dialect and its boundary, named. A real-model run opened with `import
        // requests` and Python comments, which the description permitted by
        // saying only what the runtime *is*. The engine is named because a
        // model already knows what JavaScriptCore implies — no module loader,
        // none of node's, deno's or bun's APIs — so naming it carries the whole
        // restriction in one word.
        #expect(description.contains("JavaScriptCore, core JavaScript only"))
        #expect(description.contains("`import` and `require` do not exist"))
        #expect(description.contains("no node, deno or bun APIs"))
        #expect(description.contains("every function you can call is under `tools.*`"))
        // Coordination is awaiting, and `wait()` is forbidden by name. Naming a
        // thing to forbid it normally puts it back in the option set — the
        // reason refusal is never named below — but `wait()` is already in the
        // option set from outside: a model that learned the old sandbox
        // global still writes it, so a prohibition has to name what it
        // overrides. The sandbox keeps the name only for a repair text. A pending
        // envelope tells the model to end its answer, because the settled run
        // comes back as mail, and the description says the same thing (task
        // ^4qcf1v9), so the two texts cannot pull the model two ways. No text
        // sends the model to a `wait` tool: none is mounted.
        #expect(description.contains("Awaiting a call is the whole of how a snippet coordinates its work"))
        #expect(description.contains("do not wait()"))
        #expect(description.contains("never time a call or poll for one"))
        #expect(description.contains("end your answer now"))
        #expect(description.contains("comes back to you as a new message"))
        #expect(!description.contains("wait tool"))
        // Persona-free, and refusal is never named — naming it would put it
        // back in the option set. An honest failure report replaces it.
        #expect(!description.localizedCaseInsensitiveContains("helpful assistant"))
        #expect(!description.localizedCaseInsensitiveContains("refus"))
        // No exemption clause survives: task 5qadve5 deleted the arithmetic
        // carve-out, so nothing gives a reason to skip the search.
        #expect(!description.localizedCaseInsensitiveContains("needs no functions"))
        // The snippet runs against the paths searchTools returned, and the
        // trigger is never the model's own confidence.
        #expect(description.contains("the exact `tools.*` paths searchTools returned"))
        #expect(!description.localizedCaseInsensitiveContains("if you are unsure"))
        // Every call is awaited, and only the returned value escapes the sandbox.
        #expect(description.localizedCaseInsensitiveContains("await every call"))
        #expect(description.contains("only that value comes back"))
        // Answer only from real returns — never own knowledge, never invented,
        // and never an outcome no snippet returned. Buried lower down, this was
        // violated by runs reporting a booking confirmed with nothing invoked.
        #expect(description.contains("Answer only from what the snippet returns"))
        #expect(description.localizedCaseInsensitiveContains("never state a fact"))
        #expect(description.localizedCaseInsensitiveContains("never claim success"))
        // The fix-and-retry contract.
        #expect(description.contains("call runCode again"))
        // The ambient-globals pointer (eventplan.md "The sandbox globals"): the
        // globals carry no searchTools entry, so this description is the only
        // place the model learns they exist — and it carries the pointer, not
        // the contract, which `docs("globals")` hands back on demand
        // (`SandboxGlobalsTests` pins what comes back).
        #expect(description.contains("never appear in searchTools"))
        #expect(description.contains("docs(\"\(MultiTool.sandboxGlobalsDocsTopic)\")"))
    }

    // MARK: - directMode(): a surface with discovery taken away

    @Test("registry.directMode() drops the searchTools affordance; neither arm reports a wait tool")
    func directModeReportsRunCodeOnlySurface() throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .buildRegistry()

        #expect(registry.isDirectMode == false)
        #expect(registry.supportsSearchTools == true)
        // No `wait` in either arm: a settled background run comes back to the
        // session as mail, and `makeSessionTools(librarian:)` mounts no `wait`.
        #expect(registry.affordances == ["runCode", "searchTools"])

        let direct = registry.directMode()

        #expect(direct.isDirectMode == true)
        #expect(direct.supportsSearchTools == false)
        #expect(direct.affordances == ["runCode"])
        // `directMode()` only flips the affordance metadata — the executable
        // surface itself (and its rendered catalog) is unchanged.
        #expect(direct.surface.entries.map(\.path) == registry.surface.entries.map(\.path))
    }

    // MARK: - makeSessionTools(): the array a host mounts, in presentation order

    @Test("makeSessionTools() presents searchTools before runCode")
    func sessionToolsPresentDiscoveryBeforeExecution() throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .buildRegistry()

        let mounted = try registry.makeSessionTools(librarian: nil)

        // Discover, then execute. No `wait` tool is mounted: a settled
        // background run comes back to the session as mail.
        #expect(mounted.map(\.name) == ["searchTools", "runCode"])
    }

    @Test("A direct-mode registry vends runCode alone — there is no searchTools to present and no wait tool")
    func directModeSessionToolsOmitSearchTools() throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .buildRegistry()
            .directMode()

        let mounted = try registry.makeSessionTools(librarian: nil)

        // Direct mode drops discovery and nothing else: a slow `runCode` still
        // goes to the background, and its result still comes back as mail.
        #expect(mounted.map(\.name) == ["runCode"])
    }

    @Test("Both vended tools are backed by the registry they were vended from, not an empty one")
    func vendedToolsAreBackedByTheirOwnRegistry() async throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .buildRegistry()

        let mounted = try registry.makeSessionTools(librarian: nil)

        // The runCode half dispatches into the registry's real wrapped tool:
        // a `MultiTool` over an empty registry would render a repairable
        // error for `tools.getCities` instead of the itinerary.
        // Found by type, never by position: a positional read silently tested
        // the wrong tool the moment the array grew.
        let runCode = try #require(mounted.compactMap { $0 as? MultiTool }.first)
        let itinerary = try await runCode.call(
            arguments: RunCodeArguments(code: #"return (await tools.getCities()).cities.join("-");"#)
        )
        #expect(itinerary == "\"AAA-BBB-CCC\"")

        // The searchTools half searches the same registry's rendered catalog.
        // `librarian: nil` leaves the searcher in cheap retrieval, so this
        // needs no model.
        let searchTools = try #require(mounted.first as? SearchToolsTool)
        let discovery = try await searchTools.call(arguments: SearchToolsArguments(task: "the cities on the trip"))
        #expect(discovery.contains("tools.getCities"))
    }

    // MARK: - A settled background run comes back as mail

    /// How long the removed-`wait()` test lets a `runCode` call wait for its
    /// own snippet. It is long enough for a snippet that fails at once, and it
    /// is the time the gated snippet stays pending before its envelope comes
    /// back.
    private static let shortInlineSettleGrace: TimeInterval = 1

    /// The seconds argument of the removed sandbox `wait()` in the snippet
    /// that tries to collect a run. The call throws before it reads the
    /// argument, thus the value has no effect.
    private static let removedWaitSecondsArgument = 1

    /// A `runCode` over one ``GatedCodeTool``.
    ///
    /// - Parameters:
    ///   - gate: The gate the tool waits on.
    ///   - inlineSettleGrace: How long a mounted call waits for its snippet.
    /// - Returns: The tool.
    private static func gatedRunCode(gate: ReleaseGate, inlineSettleGrace: TimeInterval) throws -> MultiTool {
        MultiTool(
            registry: try MultiTool.Builder().addTool(GatedCodeTool(gate: gate)).buildRegistry(),
            configuration: MultiToolConfiguration(inlineSettleGrace: inlineSettleGrace)
        )
    }

    /// The prompts after the first one that carry the gated tool's result.
    ///
    /// - Parameter prompts: Every prompt the backend got, in order.
    /// - Returns: The later prompts that contain ``mailProbeResultCode``.
    private static func laterPromptsCarryingTheResult(_ prompts: [String]) -> [String] {
        prompts.dropFirst().filter { $0.contains(mailProbeResultCode) }
    }

    @Test("a background runCode that settles after the answer comes back as one mail submission that carries the result, and exactly one")
    func settledRunComesBackAsOneMail() async throws {
        let gate = ReleaseGate()
        let prompts = MailProbePrompts()
        let session = try await makeMailProbeSession(
            mounting: try Self.gatedRunCode(gate: gate, inlineSettleGrace: 0),
            prompts: prompts
        ) { index, runCode in
            // The first submission starts the snippet and ends its answer, as
            // the pending envelope tells the model to do. Every later
            // submission only answers.
            guard index == 0 else { return "answered" }
            _ = try mailProbeEnvelope(
                try await runCode.call(arguments: RunCodeArguments(code: gatedCodeSnippet)))
            return "the result comes back later"
        }

        _ = try await session.respond(to: "start the snippet")
        await gate.release()
        let afterMail = await prompts.awaiting(2)
        // One more caller message after the mail: mail that stays in the
        // outbox, or a second copy of it, goes into this submission.
        _ = try await session.respond(to: "one more message")
        let all = await prompts.awaiting(3)

        #expect(afterMail.count == 2)
        #expect(Self.laterPromptsCarryingTheResult(all).count == 1)
        #expect(all.count >= 2 && all[1].contains(mailProbeResultCode))
        #expect(all.count == 3 && !all[2].contains(mailProbeResultCode))
    }

    /// Records the fix of task `^11cfnx0` for the finding of task `^q4jrnd0`.
    /// A run that the sandbox `wait()` global collected was ALSO delivered as
    /// mail, because `SessionMailbox.wait` does not withdraw the staged
    /// terminal event. Thus the model read the result two times. The global is
    /// removed. A snippet that calls `wait()` now gets the repair text at once,
    /// with no result in it, and the run comes back one time only, as mail.
    @Test("a snippet that calls the removed sandbox wait() gets the repair text, and the run comes back as exactly one mail")
    func sandboxWaitIsRemovedAndTheRunComesBackAsOneMail() async throws {
        let gate = ReleaseGate()
        let prompts = MailProbePrompts()
        let refused = OSAllocatedUnfairLock<PendingRunEnvelope?>(initialState: nil)
        let session = try await makeMailProbeSession(
            mounting: try Self.gatedRunCode(gate: gate, inlineSettleGrace: Self.shortInlineSettleGrace),
            prompts: prompts
        ) { index, runCode in
            guard index == 0 else { return "answered" }
            // The gated snippet outlasts the grace, so its call answers with a
            // pending envelope. A second snippet then tries to collect the run
            // with the removed sandbox `wait()`, and the gate opens after it.
            let pending = try mailProbeEnvelope(
                try await runCode.call(arguments: RunCodeArguments(code: gatedCodeSnippet)))
            let collector = "return (await wait(\"\(pending.completionToken)\", "
                + "\(Self.removedWaitSecondsArgument))).detail;"
            let answer = try mailProbeEnvelope(
                try await runCode.call(arguments: RunCodeArguments(code: collector)))
            refused.withLock { $0 = answer }
            await gate.release()
            return "the result comes back later"
        }

        _ = try await session.respond(to: "start the snippet and try to collect it")
        _ = await prompts.awaiting(2)
        _ = try await session.respond(to: "one more message")
        let all = await prompts.awaiting(3)

        let collector = try #require(refused.withLock { $0 })
        #expect(!collector.pending)
        #expect(collector.detail?.contains(SandboxGlobalError.waitRemoved.description) == true)
        #expect(collector.detail?.contains(mailProbeResultCode) == false)
        #expect(Self.laterPromptsCarryingTheResult(all).count == 1)
    }
}
