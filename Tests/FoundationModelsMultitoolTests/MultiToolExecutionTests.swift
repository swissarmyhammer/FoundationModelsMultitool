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
                const cities = (await tools.cities()).cities;
                const temps = [];
                for (const c of cities) {
                  temps.push((await tools.temp({ city: c })).tempC);
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
            arguments: RunCodeArguments(code: "return (await tools.github.issueCount({ repo: 'demo' })).count;")
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
                  await tools.temp({});
                  return "unreachable";
                } catch (e) {
                  return e.message;
                }
                """)
        )
        let message = try JSONDecoder().decode(String.self, from: Data(output.utf8))

        #expect(message.hasSuffix("Tool \"temp\" is missing its required argument \"city\"."))
    }

    // MARK: - Mis-called tool: repairable error, not a crash

    @Test("a mis-called tool (missing required argument) surfaces ResultRenderer's repairable error text, not a crash")
    func misCalledToolSurfacesRepairableErrorText() async throws {
        let registry = try MultiTool.Builder()
            .addTool(TempTool())
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return tools.temp({});"))

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
        // Read-and-destructure the declared return type.
        #expect(description.localizedCaseInsensitiveContains("destructure"))
        // Answer only from real returns — never own knowledge, never invented.
        #expect(description.localizedCaseInsensitiveContains("never answer"))
        #expect(description.localizedCaseInsensitiveContains("never simulate or invent"))
        // The fix-and-retry contract.
        #expect(description.contains("call runCode again"))
        #expect(description.localizedCaseInsensitiveContains("never stop at an error"))
        #expect(description.localizedCaseInsensitiveContains("never claim success"))
        // The async-usage line (eventplan.md "Async JavaScript"): every
        // `tools.*` call returns a promise.
        #expect(description.localizedCaseInsensitiveContains("await each `tools.*` call"))
        #expect(description.contains("Promise.all"))
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
}
