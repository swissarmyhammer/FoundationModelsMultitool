import Foundation
import FoundationModels
import Testing

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

    @Test("runCode's schema exposes code, waitSeconds and timeout, each with its own guidance")
    func runCodeSchemaExposesBothClocks() throws {
        let registry = try MultiTool.Builder().addTool(TempTool()).buildRegistry()

        let schema = try ToolAPIRenderer.jsonSchemaString(for: MultiTool(registry: registry).parameters)

        for property in ["code", "waitSeconds", "timeout"] {
            #expect(schema.contains(property))
        }
        // Each clock's own `@Guide` text, so the model reads what the two
        // clocks mean rather than only their names.
        #expect(schema.contains("hands back a pending completion token"))
        #expect(schema.contains("Progress resets this clock"))
        // The reset is bounded. The interpreter watchdog is armed from
        // sandbox creation and nothing extends it, so the guidance must not
        // leave a model believing progress buys unlimited time.
        #expect(schema.contains("only up to the host's ceiling, which is absolute"))
    }

    @Test("runCode arguments carrying only code still decode, leaving both clocks to their defaults")
    func runCodeArgumentsDecodeFromCodeAlone() async throws {
        let registry = try MultiTool.Builder().addTool(TempTool()).buildRegistry()
        let content = try ArgumentMarshaler.marshalArguments(.object(["code": .string("return 1 + 1;")]))

        let arguments = try RunCodeArguments(content)

        #expect(arguments.code == "return 1 + 1;")
        #expect(arguments.waitSeconds == nil)
        #expect(arguments.timeout == nil)
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

        let start = ContinuousClock.now
        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: """
                await Promise.all([tools.slowA(), tools.slowB()]);
                return "done";
                """)
        )
        let elapsed = start.duration(to: .now)

        #expect(output == "\"done\"")
        // ~max (150ms) of the two delays, not ~sum (300ms) — real
        // concurrency, not the old bridge's serialized blocking.
        #expect(elapsed < .milliseconds(280))
        let windowA = try #require(toolA.window)
        let windowB = try #require(toolB.window)
        // Each call's run window overlaps the other's — if the two ran one
        // after another, one window would start only after the other had
        // already ended.
        let overlap = windowA.start < windowB.end && windowB.start < windowA.end
        #expect(overlap)
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

        #expect(output == "\"done\"")
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

        #expect(output.contains("Fix the snippet and call runCode again."))
        #expect(output.contains("city"))
    }

    // MARK: - Description: the no-system-prompt error-recovery contract

    @Test("runCode's description alone carries the findAPIs-first workflow and the error-recovery contract — no system prompt required")
    func descriptionCarriesTheErrorRecoveryContract() throws {
        let registry = try MultiTool.Builder().addTool(TempTool()).buildRegistry()
        // Collapse the multiline literal's hard line-wraps to single spaces
        // so an assertion probes the guidance, not incidental wrapping.
        let description = MultiTool(registry: registry)
            .description
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        // The first-move stance — load-bearing, and only effective from a
        // description the model reads upfront alongside every tool schema.
        #expect(description.localizedCaseInsensitiveContains("call findAPIs first"))
        // runCode is a general-purpose isolated runtime, and the findAPIs prior is
        // stated rather than left as a judgment the model makes before acting. This
        // description is always in the prompt, and `sessionInstructions` no longer
        // exists (task tkrdwb8), so the contract has to hold here on its own.
        #expect(description.contains("isolated JavaScript runtime"))
        #expect(description.contains("arithmetic, string work, dates, sorting"))
        #expect(description.contains("rather than in your head"))
        #expect(description.contains("Assume any user request needs this session's functions"))
        #expect(description.contains("pure arithmetic or string work needs no functions"))
        #expect(!description.localizedCaseInsensitiveContains("real-time"))
        // Persona-free, and refusal is never named — naming it would put it
        // back in the option set. An honest failure report replaces it.
        #expect(!description.localizedCaseInsensitiveContains("helpful assistant"))
        #expect(!description.localizedCaseInsensitiveContains("refus"))
        // The numbered procedure comes before any rule.
        #expect(description.contains("Writing the snippet:"))
        // The findAPIs-first prior comes before the snippet mechanics, so a reader
        // meets "search first" before "here is how to write it".
        let priorRange = try #require(description.range(of: "Assume any user request needs this session's functions"))
        let mechanicsRange = try #require(description.range(of: "Writing the snippet:"))
        #expect(priorRange.upperBound <= mechanicsRange.lowerBound)
        // Provenance, stated positively so it cannot invert. An earlier draft shipped
        // "State no fact ... that a tools.* call returned", which forbids exactly what
        // it means to require.
        #expect(description.contains("Every fact you state about the user's data comes from a"))
        // In-sandbox discovery is named at step 1, not left as an aside:
        // `help()`/`docs(name)` are synchronous inside the sandbox, so a
        // snippet confirms the surface without a second round trip — which is
        // where every recorded plan-and-stop happens.
        // The anti-guessing trigger is checkable conversational state, never
        // the model's own confidence.
        #expect(description.contains("write the snippet against the paths findAPIs returned"))
        #expect(!description.localizedCaseInsensitiveContains("if you are unsure"))
        // Read-and-destructure the declared return type.
        #expect(description.localizedCaseInsensitiveContains("destructure"))
        // JavaScript work over returned values is the feature; only
        // fabricating a fact is closed off.
        #expect(description.contains("arithmetic, string work, dates, sorting"))
        // Answer only from real returns — never own knowledge, never invented,
        // and never an outcome no snippet returned. This sits directly under
        // the procedure with its consequence attached: buried lower down, it
        // was violated by runs reporting a booking as confirmed with nothing
        // invoked.
        #expect(description.localizedCaseInsensitiveContains("never answer"))
        #expect(description.localizedCaseInsensitiveContains("never simulate or invent"))
        #expect(description.localizedCaseInsensitiveContains("never claim success"))
        // The fix-and-retry contract.
        #expect(description.contains("call runCode again"))
        #expect(description.localizedCaseInsensitiveContains("never stop at an error"))
        // The async-usage line (eventplan.md "Async JavaScript"): every
        // `tools.*` call returns a promise.
        #expect(description.localizedCaseInsensitiveContains("await each `tools.*` call"))
        #expect(description.contains("Promise.all"))
        // The ambient-globals pointer (eventplan.md "The sandbox globals"):
        // the six globals carry no `findAPIs` entry, so the description is
        // the only place the model learns they exist — but it carries the
        // pointer, not the contract, which `docs("globals")` hands back on
        // demand (`SandboxGlobalsTests` pins what comes back).
        #expect(description.contains("never appear in findAPIs"))
        #expect(description.contains("docs(\"\(MultiTool.sandboxGlobalsDocsTopic)\")"))
    }

    // MARK: - directMode(): a runCode-only surface

    @Test("registry.directMode() reports no findAPIs affordance; a plain registry reports both")
    func directModeReportsRunCodeOnlySurface() throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .buildRegistry()

        #expect(registry.isDirectMode == false)
        #expect(registry.supportsFindAPIs == true)
        #expect(registry.affordances == ["runCode", "findAPIs"])

        let direct = registry.directMode()

        #expect(direct.isDirectMode == true)
        #expect(direct.supportsFindAPIs == false)
        #expect(direct.affordances == ["runCode"])
        // `directMode()` only flips the affordance metadata — the executable
        // surface itself (and its rendered catalog) is unchanged.
        #expect(direct.surface.entries.map(\.path) == registry.surface.entries.map(\.path))
    }

    // MARK: - makeSessionTools(): the array a host mounts, in presentation order

    @Test("makeSessionTools() presents findAPIs before runCode")
    func sessionToolsPresentDiscoveryBeforeExecution() throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .buildRegistry()

        let mounted = try registry.makeSessionTools(librarian: nil)

        #expect(mounted.map(\.name) == ["findAPIs", "runCode"])
    }

    @Test("A direct-mode registry vends runCode alone — there is no findAPIs to present")
    func directModeSessionToolsOmitFindAPIs() throws {
        let registry = try MultiTool.Builder()
            .addTool(CitiesTool())
            .buildRegistry()
            .directMode()

        let mounted = try registry.makeSessionTools(librarian: nil)

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
        let runCode = try #require(mounted.last as? MultiTool)
        let itinerary = try await runCode.call(
            arguments: RunCodeArguments(code: #"return (await tools.getCities()).cities.join("-");"#)
        )
        #expect(itinerary == "\"AAA-BBB-CCC\"")

        // The findAPIs half searches the same registry's rendered catalog.
        // `librarian: nil` leaves the searcher in cheap retrieval, so this
        // needs no model.
        let findAPIs = try #require(mounted.first as? FindAPIsTool)
        let discovery = try await findAPIs.call(arguments: FindAPIsArguments(task: "the cities on the trip"))
        #expect(discovery.contains("tools.getCities"))
    }
}
