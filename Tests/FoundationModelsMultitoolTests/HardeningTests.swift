import Foundation
import JavaScriptCore
import Testing

import FoundationModels
@testable import FoundationModelsMultitool

/// M10 coverage: cancellation reaching into an in-flight `runCode` snippet,
/// every `MultiToolConfiguration` limit enforced at its boundary, the
/// sandbox's reachable-global surface, and the machine-checked README↔code
/// sync of that surface's documented list (plan.md M10 acceptance criteria).
@Suite("Hardening")
struct HardeningTests {
    // MARK: - MultiToolConfiguration itself

    @Test("MultiToolConfiguration.default matches every mechanism's own pre-M10 default")
    func defaultConfigurationMatchesHistoricalDefaults() {
        let configuration = MultiToolConfiguration.default
        #expect(configuration.executionTimeLimit == 5.0)
        #expect(configuration.returnValueCharacterLimit == ResultRendererLimits.default.returnValueCharacterLimit)
        #expect(configuration.consoleCharacterLimit == ResultRendererLimits.default.consoleCharacterLimit)
        #expect(configuration.maxAgentTurns == 8)
        #expect(configuration.maxRepairTurns == 1)
    }

    @Test("MultiToolConfiguration clamps every limit to its valid range")
    func configurationClampsInvalidLimits() {
        let configuration = MultiToolConfiguration(
            executionTimeLimit: -1,
            returnValueCharacterLimit: -5,
            consoleCharacterLimit: -5,
            maxAgentTurns: -3,
            maxRepairTurns: -3
        )
        #expect(configuration.executionTimeLimit == 0)
        #expect(configuration.returnValueCharacterLimit == 0)
        #expect(configuration.consoleCharacterLimit == 0)
        #expect(configuration.maxAgentTurns == 1)
        #expect(configuration.maxRepairTurns == 0)
    }

    // MARK: - Cancellation (plan.md M10 acceptance: "no leaked JS thread or semaphore deadlock")

    @Test("cancelling the task running MultiTool.call terminates an infinite-loop snippet and throws CancellationError within the configured time limit")
    func cancellationTerminatesInfiniteLoopSnippetWithinTimeLimit() async throws {
        // A generous configured limit: if cancellation only worked by waiting
        // out the ordinary watchdog timeout, this assertion's `< .seconds(3)`
        // bound below would fail.
        let configuration = MultiToolConfiguration(executionTimeLimit: 10.0)
        let multiTool = MultiTool(registry: Self.emptyRegistry, configuration: configuration)

        let task = Task {
            try await multiTool.call(arguments: RunCodeArguments(code: "while (true) {}"))
        }
        // Let the loop actually start spinning before cancelling.
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let start = ContinuousClock.now
        await Self.expectCancellationError { _ = try await task.value }
        #expect(start.duration(to: .now) < .seconds(3))
    }

    @Test("cancelling the task running MultiToolAgent.respond(to:) terminates an in-flight runCode snippet and throws CancellationError")
    func cancellationTerminatesAgentRespondMidRunCode() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let mainSession = ScriptedAgentSession([
            "ACTION: runCode\nCODE:\n```js\nwhile (true) {}\n```"
        ])
        let configuration = MultiToolConfiguration(executionTimeLimit: 10.0)
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant.",
            configuration: configuration
        )

        let task = Task {
            try await agent.respond(to: "hello")
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()

        let start = ContinuousClock.now
        await Self.expectCancellationError { _ = try await task.value }
        #expect(start.duration(to: .now) < .seconds(3))
    }

    @Test(
        "repeated concurrent cancellations across many MultiTool.call invocations all complete cleanly, with no deadlock and no hung interpreter thread"
    )
    func cancellationStressTestNoDeadlock() async throws {
        let iterations = 40
        let configuration = MultiToolConfiguration(executionTimeLimit: 10.0)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    let multiTool = MultiTool(registry: Self.emptyRegistry, configuration: configuration)
                    let task = Task {
                        try await multiTool.call(arguments: RunCodeArguments(code: "while (true) {}"))
                    }
                    try await Task.sleep(nanoseconds: 20_000_000)
                    task.cancel()
                    await Self.expectCancellationError { _ = try await task.value }
                }
            }
            try await group.waitForAll()
        }
    }

    /// Awaits `operation`, recording a failure if it doesn't throw
    /// `CancellationError` — the shared assertion every cancellation test
    /// above needs, so the "did it actually cancel, not just fail some other
    /// way" check is written once.
    ///
    /// - Parameter operation: the operation expected to throw
    ///   `CancellationError`.
    private static func expectCancellationError(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            Issue.record("expected CancellationError to be thrown")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }
    }

    // MARK: - Configuration limits enforced at their boundary

    @Test("a small configured executionTimeLimit terminates a runaway snippet near that limit, not the (larger) default")
    func executionTimeLimitBoundaryTerminatesNearConfiguredLimit() async throws {
        let configuration = MultiToolConfiguration(executionTimeLimit: 0.3)
        let multiTool = MultiTool(registry: Self.emptyRegistry, configuration: configuration)

        let start = ContinuousClock.now
        let output = try await multiTool.call(arguments: RunCodeArguments(code: "while (true) {}"))
        let elapsed = start.duration(to: .now)

        #expect(output.contains("timed out"))
        // Comfortably above the 0.3s configured limit (watchdog scheduling
        // jitter) but far below the 5s package default — proves the
        // configured limit, not the default, was the one enforced.
        #expect(elapsed < .seconds(3))
    }

    @Test("a snippet finishing under a small configured executionTimeLimit succeeds normally")
    func executionTimeLimitBoundaryAllowsAFastSnippet() async throws {
        let configuration = MultiToolConfiguration(executionTimeLimit: 0.3)
        let multiTool = MultiTool(registry: Self.emptyRegistry, configuration: configuration)

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return 1 + 1;"))

        #expect(output == "2")
    }

    @Test("a return value serialized to exactly the configured returnValueCharacterLimit is not truncated")
    func returnValueCharacterLimitBoundaryAtLimitIsNotTruncated() async throws {
        let limit = 20
        let configuration = MultiToolConfiguration(returnValueCharacterLimit: limit, consoleCharacterLimit: 1000)
        let multiTool = MultiTool(registry: Self.emptyRegistry, configuration: configuration)

        // A plain-ASCII JS string of `limit - 2` characters serializes to
        // exactly `limit` JSON characters (the two surrounding quotes).
        let value = String(repeating: "a", count: limit - 2)
        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return \"\(value)\";"))

        #expect(!output.contains("truncated"))
        #expect(output == "\"\(value)\"")
    }

    @Test("a return value serialized to one character over the configured returnValueCharacterLimit is truncated")
    func returnValueCharacterLimitBoundaryOverLimitIsTruncated() async throws {
        let limit = 20
        let configuration = MultiToolConfiguration(returnValueCharacterLimit: limit, consoleCharacterLimit: 1000)
        let multiTool = MultiTool(registry: Self.emptyRegistry, configuration: configuration)

        // One character longer than the previous test's boundary case —
        // serializes to `limit + 1` JSON characters.
        let value = String(repeating: "a", count: limit - 1)
        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return \"\(value)\";"))

        #expect(output.contains("truncated"))
    }

    @Test("console output at exactly the configured consoleCharacterLimit is not truncated")
    func consoleCharacterLimitBoundaryAtLimitIsNotTruncated() async throws {
        let limit = 15
        let configuration = MultiToolConfiguration(returnValueCharacterLimit: 1000, consoleCharacterLimit: limit)
        let multiTool = MultiTool(registry: Self.emptyRegistry, configuration: configuration)

        let value = String(repeating: "b", count: limit)
        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "console.log(\"\(value)\"); return null;")
        )

        #expect(!output.contains("truncated"))
        #expect(output.contains(value))
    }

    @Test("console output one character over the configured consoleCharacterLimit is truncated")
    func consoleCharacterLimitBoundaryOverLimitIsTruncated() async throws {
        let limit = 15
        let configuration = MultiToolConfiguration(returnValueCharacterLimit: 1000, consoleCharacterLimit: limit)
        let multiTool = MultiTool(registry: Self.emptyRegistry, configuration: configuration)

        let value = String(repeating: "b", count: limit + 1)
        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "console.log(\"\(value)\"); return null;")
        )

        #expect(output.contains("truncated"))
    }

    @Test("a configured maxAgentTurns of N succeeds when the model finishes in exactly N turns")
    func maxAgentTurnsBoundaryAtLimitSucceeds() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let configuration = MultiToolConfiguration(maxAgentTurns: 2)
        let session = ScriptedAgentSession([
            "ACTION: runCode\nCODE:\n```js\nreturn 1;\n```",
            "ACTION: final\nANSWER: done",
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: session,
            instructions: "You are a travel assistant.",
            configuration: configuration
        )

        let reply = try await agent.respond(to: "hello")

        #expect(reply == "done")
    }

    @Test("a configured maxAgentTurns of N fails with a typed error when the model needs N+1 turns")
    func maxAgentTurnsBoundaryOverLimitFails() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let configuration = MultiToolConfiguration(maxAgentTurns: 2)
        let neverEndingResponse = "ACTION: runCode\nCODE:\n```js\nreturn 1;\n```"
        let session = ScriptedAgentSession(Array(repeating: neverEndingResponse, count: 5))
        let agent = MultiToolAgent(
            registry: registry,
            session: session,
            instructions: "You are a travel assistant.",
            configuration: configuration
        )

        await #expect(throws: MultiToolAgentError.maxTurnsExceeded(turns: 2)) {
            try await agent.respond(to: "hello")
        }
    }

    @Test("a configured maxRepairTurns of N recovers when exactly N consecutive turns are malformed")
    func maxRepairTurnsBoundaryAtLimitRecovers() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let configuration = MultiToolConfiguration(maxRepairTurns: 1)
        let session = ScriptedAgentSession([
            "garbage, not a valid action",
            "ACTION: final\nANSWER: recovered",
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: session,
            instructions: "You are a travel assistant.",
            configuration: configuration
        )

        let reply = try await agent.respond(to: "hello")

        #expect(reply == "recovered")
    }

    @Test("a configured maxRepairTurns of N fails the loop when N+1 consecutive turns are malformed")
    func maxRepairTurnsBoundaryOverLimitFails() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let configuration = MultiToolConfiguration(maxRepairTurns: 1)
        let session = ScriptedAgentSession([
            "garbage one",
            "garbage two",
            "ACTION: final\nANSWER: too late",
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: session,
            instructions: "You are a travel assistant.",
            configuration: configuration
        )

        await #expect(throws: MultiToolAgentError.self) {
            try await agent.respond(to: "hello")
        }
    }

    // MARK: - Sandbox surface & README↔code sync

    @Test("the injected globals reachable in a fresh MultiTool run, beyond JavaScriptCore's own standard environment, are exactly {console, tools, help, docs}")
    func sandboxInjectedGlobalsAreExactlyTheDocumentedSet() async throws {
        let injected = try await Self.injectedGlobals()
        #expect(injected == ["console", "tools", "help", "docs"])
    }

    @Test("README's enumerated 'Injected globals' list is set-equal to the runtime-enumerated sandbox globals")
    func readmeInjectedGlobalsListMatchesRuntime() async throws {
        let injected = try await Self.injectedGlobals()
        let documented = try Self.readmeInjectedGlobals()
        #expect(documented == injected)
    }

    /// The globals a fresh `MultiTool` run context can reach beyond a
    /// completely vanilla `JSContext`'s own standard ECMAScript environment
    /// — the "injected globals" plan.md M10's security-model section
    /// documents. An empty registry (no wrapped tools) keeps the set fixed
    /// and enumerable: `tools` itself is always installed, but with no
    /// per-tool positional bindings (`__tool0`, …) to vary the count.
    ///
    /// - Returns: the set of injected global names.
    private static func injectedGlobals() async throws -> Set<String> {
        try await Self.multiToolRunGlobals().subtracting(Self.rawJSContextGlobals())
    }

    /// Every own-property name on `globalThis` in a completely vanilla
    /// `JSContext` — the baseline JavaScriptCore itself ships with, before
    /// this package injects anything — **except** `console`.
    ///
    /// `console` is deliberately excluded from this baseline, even though
    /// it's already an own property of a bare `JSContext()` on this SDK
    /// (measured directly: a fresh `JSContext()`'s `globalThis` already has
    /// a `console`, one of Apple's own `JSContext` wrapper class's default
    /// conveniences — not an ECMAScript builtin at all, unlike this
    /// baseline's other members). `JSCInterpreter.installConsole` always
    /// *replaces* `globalThis.console` outright (`context.setObject(console,
    /// forKeyedSubscript: "console")`, where `console` is a brand-new
    /// object carrying only `log`) rather than extending whatever was there
    /// — so nothing of JSC's own default `console` (whatever other methods
    /// it might expose) is ever reachable from a `MultiTool` run; the
    /// `console` a snippet actually sees is 100% this package's minimal
    /// shim. Counting it as part of the untouched baseline here would make
    /// this test (and the README↔code sync it backs) miss that this
    /// package fully owns and controls `console`'s reachable surface, same
    /// as `tools`/`help`/`docs`.
    private static func rawJSContextGlobals() throws -> Set<String> {
        let context = try #require(JSContext())
        let namesValue = try #require(context.evaluateScript("Object.getOwnPropertyNames(globalThis)"))
        let names = try #require(namesValue.toArray() as? [String])
        return Set(names).subtracting(["console"])
    }

    /// Every own-property name on `globalThis` inside one fresh `MultiTool`
    /// run over an empty registry.
    private static func multiToolRunGlobals() async throws -> Set<String> {
        let multiTool = MultiTool(registry: Self.emptyRegistry)
        let output = try await multiTool.call(
            arguments: RunCodeArguments(code: "return Object.getOwnPropertyNames(globalThis);")
        )
        let names = try JSONDecoder().decode([String].self, from: Data(output.utf8))
        return Set(names)
    }

    /// A registry with no wrapped tools — enough for `MultiTool` to install
    /// its always-present `tools`/`help`/`docs` globals, with no per-tool
    /// positional bindings to complicate the enumeration.
    private static var emptyRegistry: MultiTool.Registry {
        MultiTool.Registry(surface: ApiSurface(entries: []), tools: [:])
    }

    /// Parses the `### Injected globals` section of the repo root's
    /// `README.md` — every `- \`name\`` list item between that heading and
    /// the next heading — the machine-checked half of "README↔code sync"
    /// (plan.md M10 acceptance: "drift fails CI").
    ///
    /// - Returns: every documented injected-global name.
    /// - Throws: `HardeningTestsError` if the section can't be found.
    private static func readmeInjectedGlobals() throws -> Set<String> {
        let readmeURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("README.md")
        let text = try String(contentsOf: readmeURL, encoding: .utf8)

        let heading = "### Injected globals"
        guard let headingRange = text.range(of: heading) else {
            throw HardeningTestsError(message: "README.md has no \"\(heading)\" section.")
        }

        let afterHeading = text[headingRange.upperBound...]
        let sectionEnd = afterHeading.range(of: "\n#")?.lowerBound ?? afterHeading.endIndex
        let section = afterHeading[..<sectionEnd]

        var names: Set<String> = []
        for rawLine in section.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- `"), trimmed.hasSuffix("`") else { continue }
            let name = trimmed.dropFirst(3).dropLast(1)
            guard !name.isEmpty else { continue }
            names.insert(String(name))
        }
        return names
    }
}

/// A parse failure reading `README.md`'s documented sandbox-surface list.
private struct HardeningTestsError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
