import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsMultitool

/// # Canonical usage reference for FoundationModelsMultitool.
///
/// This suite is the **living documentation** for the library's public
/// API — each `@Test` is a self-contained, copy-pasteable "how do I…"
/// example whose body reads exactly like the code a real consumer writes,
/// mirroring `FoundationModelsRouter`'s own
/// `Tests/FoundationModelsRouterTests/ExamplesTests.swift` and
/// `FoundationModelsMetadataRegistry`'s `ExamplesSmokeTests.swift`. Read
/// these first to learn the call patterns: author a catalog with
/// `MultiTool.Builder`, register `MultiTool` (and, for discovery,
/// `FindAPIsTool`) directly on a native `FoundationModels
/// .LanguageModelSession`, and let Apple's own tool-calling loop drive the
/// findAPIs → runCode handoff.
///
/// Every example here runs fully offline — no live model, no network, no
/// `MULTITOOL_INTEGRATION` gate — via `ScriptedLanguageModel` below, the
/// **only** non-production code in this file. It is a minimal, from-scratch
/// conformer of `FoundationModels.LanguageModel`/`LanguageModelExecutor` —
/// the same third-party-model extension point `MLXLanguageModel`
/// (`multitool-cli`'s own production wiring, see `CLIRunner
/// .makeMLXLanguageModel(for:)`) uses — standing in for a real model so
/// these examples need neither MLX weights nor Apple Intelligence. Every
/// line *after* a `ScriptedLanguageModel` is constructed is real usage: a
/// genuine `LanguageModelSession` drives its own native multi-turn
/// tool-calling loop, actually invoking the real `MultiTool`/`FindAPIsTool`
/// this suite registers with it.
@Suite("Examples: canonical usage of the public API")
struct ExamplesTests {
    // MARK: - Unit-test seam (the ONLY non-production code in this file)

    /// One decision `ScriptedLanguageModel` streams for a single
    /// `respond()` round: either call a tool, or answer with final text.
    private enum ScriptedTurn {
        /// Emit a native tool call to `name`, with `argumentsJSON` as its
        /// JSON-encoded arguments (decoded by the session into that tool's
        /// real `Arguments` type).
        case callTool(name: String, argumentsJSON: String)
        /// Emit a final text answer, ending this `respond()` call.
        case answer(String)
    }

    /// An offline stand-in for a real model, conforming to `FoundationModels
    /// .LanguageModel`/`LanguageModelExecutor` — the same pluggable-model
    /// seam `MLXLanguageModel` fills in production (see
    /// `Sources/multitool-cli/CLIRunner.swift`). `LanguageModelSession`
    /// drives its own real native multi-turn tool-calling loop against this
    /// stub exactly as it would against a real model: it calls
    /// `nextTurn(transcript)` once per round, and — for a `.callTool`
    /// turn — actually executes the named tool for real (via whatever `Tool`
    /// conformers this suite registered) before looping back with the
    /// tool's real output appended to the transcript.
    ///
    /// `nextTurn` decides purely from `transcript`'s own entries so far —
    /// no hidden call-count state — so each example's script reads as "once
    /// the tool ran, answer; otherwise, call it," matching how a real model
    /// would decide from context alone.
    private struct ScriptedLanguageModel: LanguageModel {
        let capabilities = LanguageModelCapabilities([.toolCalling, .guidedGeneration])
        let nextTurn: @Sendable (Transcript) -> ScriptedTurn

        var executorConfiguration: Executor.Configuration { Executor.Configuration() }

        struct Executor: LanguageModelExecutor {
            struct Configuration: Hashable, Sendable {}

            init(configuration: Configuration) throws {}

            func respond(
                to request: LanguageModelExecutorGenerationRequest,
                model: ScriptedLanguageModel,
                streamingInto channel: LanguageModelExecutorGenerationChannel
            ) async throws {
                switch model.nextTurn(request.transcript) {
                case .callTool(let name, let argumentsJSON):
                    await channel.send(
                        .toolCalls(
                            entryID: UUID().uuidString,
                            action: .toolCall(
                                id: UUID().uuidString,
                                name: name,
                                action: .appendArguments(argumentsJSON, tokenCount: 1)
                            )
                        )
                    )
                case .answer(let text):
                    await channel.send(
                        .response(entryID: UUID().uuidString, action: .appendText(text, tokenCount: 1))
                    )
                }
            }
        }
    }

    /// Whether `transcript` already holds a real `toolOutput` entry from the
    /// tool named `toolName` — how a `ScriptedLanguageModel.nextTurn`
    /// closure tells "the tool already ran" from "still need to call it,"
    /// purely by reading the transcript the real session built.
    ///
    /// - Parameters:
    ///   - transcript: the transcript to inspect.
    ///   - toolName: the tool's `Tool.name` to look for.
    /// - Returns: `true` when a `toolOutput` entry from `toolName` is present.
    private static func hasToolOutput(_ transcript: Transcript, from toolName: String) -> Bool {
        transcript.contains {
            if case .toolOutput(let output) = $0 { return output.toolName == toolName }
            return false
        }
    }

    /// The rendered text of the most recent `toolOutput` entry from the tool
    /// named `toolName`, or `nil` if none is present yet — lets a test
    /// assert on what a tool genuinely returned through the real session,
    /// not just that a scripted answer happened to mention it.
    ///
    /// - Parameters:
    ///   - transcript: the transcript to inspect.
    ///   - toolName: the tool's `Tool.name` to look for.
    /// - Returns: the concatenated text segments of that tool's most recent
    ///   output, or `nil` if it never produced one.
    private static func toolOutputText(in transcript: Transcript, from toolName: String) -> String? {
        for entry in transcript.reversed() {
            guard case .toolOutput(let output) = entry, output.toolName == toolName else { continue }
            return output.segments.compactMap {
                if case .text(let segment) = $0 { return segment.content }
                return nil
            }.joined()
        }
        return nil
    }

    // MARK: - Catalog authoring

    @Test("Author a catalog with MultiTool.Builder: standalone and grouped tools")
    func authorCatalogStandaloneAndGrouped() throws {
        // Standalone tools render flat, at tools.<name>; a named group nests
        // its tools under tools.<group>.<name> (plan.md's namespacing).
        let surface = try MultiTool.Builder()
            .addTool(WeatherTool())
            .addGroup(named: "github", [GithubCreateIssueTool(), GithubSearchTool()])
            .build()

        #expect(surface.entries.map(\.path) == ["weather", "github.createIssue", "github.search"])
        #expect(surface.standaloneEntries.map(\.path) == ["weather"])
        #expect(surface.groupedEntries["github"]?.map(\.path) == ["github.createIssue", "github.search"])

        // Every entry's rendered block carries a banner naming its
        // fully-qualified call path, followed by its JSDoc + declaration.
        #expect(surface.source.contains("// tools.weather"))
        #expect(surface.source.contains("declare function weather("))
        #expect(surface.source.contains("// tools.github.createIssue"))
        #expect(surface.source.contains("declare function createIssue("))
    }

    // MARK: - Register MultiTool directly with a native LanguageModelSession

    @Test("Register MultiTool directly with Apple's LanguageModelSession, and show a tool call round-tripping")
    func registerMultiToolWithLanguageModelSession() async throws {
        let registry = try MultiTool.Builder().addTool(TripCitiesTool()).buildRegistry()
        let multiTool = MultiTool(registry: registry)

        // The stub "model": call runCode once, then answer once the tool ran.
        let model = ScriptedLanguageModel { transcript in
            Self.hasToolOutput(transcript, from: "runCode")
                ? .answer("Your itinerary: ATX, then SFO.")
                : .callTool(name: "runCode", argumentsJSON: #"{"code": "return tools.tripCities();"}"#)
        }

        // Real usage from here on: construct MultiTool(registry:), hand it
        // to a real LanguageModelSession, and let Apple's own native
        // tool-calling loop decide when to call it.
        let session = LanguageModelSession(
            model: model,
            tools: [multiTool],
            instructions: "Use runCode to answer questions about the trip."
        )

        // Explicitly typed to pin the native FoundationModels API over
        // `FoundationModelsRanker`'s shadowing `respond(to:) -> String`
        // `AgentSession` extension.
        let response: LanguageModelSession.Response<String> = try await session.respond(to: "List the cities on my trip.")

        #expect(response.content == "Your itinerary: ATX, then SFO.")
        // The round trip is real, not merely scripted: runCode's own
        // real execution (through the interpreter, dispatching to the real
        // TripCitiesTool) produced this tool-output text, landing in the
        // session's own transcript.
        let toolOutput = try #require(Self.toolOutputText(in: session.transcript, from: "runCode"))
        #expect(toolOutput.contains("ATX"))
        #expect(toolOutput.contains("SFO"))
    }

    // MARK: - findAPIs -> runCode discovery-then-call handoff

    @Test("The findAPIs -> runCode discovery-then-call handoff, via native tool-calling")
    func findAPIsThenRunCodeHandoff() async throws {
        let registry = try MultiTool.Builder()
            .addGroup(named: "github", [IssueCountTool()])
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)

        // findAPIs's own selection tier is scripted to pick
        // "github.issueCount" by id — see FindAPIsToolTests for the same
        // RootSessionRespondCalledDirectlySession pattern driving a real
        // MetadataSearcher/SelectionConfig.
        let selectionRoot = RootSessionRespondCalledDirectlySession(
            forkResponses: [#"{"ids":["github.issueCount"]}"#]
        )
        let searcher = MetadataSearcher(
            items: registry.surface.entries,
            mode: .auto,
            selection: SelectionConfig(model: { _, _ in selectionRoot }, capacityCharacterLimit: .max)
        )
        let findAPIsTool = FindAPIsTool(searcher: searcher, limit: registry.surface.entries.count)

        // The stub "model": findAPIs first, then runCode with the
        // discovered, properly-qualified call, then answer.
        let model = ScriptedLanguageModel { transcript in
            if Self.hasToolOutput(transcript, from: "runCode") {
                return .answer("There are 42 open issues.")
            }
            if Self.hasToolOutput(transcript, from: "findAPIs") {
                return .callTool(
                    name: "runCode",
                    argumentsJSON: #"{"code": "return tools.github.issueCount({repo: \"demo\"});"}"#
                )
            }
            return .callTool(name: "findAPIs", argumentsJSON: #"{"task": "count open github issues"}"#)
        }

        let session = LanguageModelSession(
            model: model,
            tools: [multiTool, findAPIsTool],
            instructions: "Call findAPIs to discover tools, then runCode to use them."
        )

        // Explicitly typed — same shadowing-extension disambiguation as above.
        let response: LanguageModelSession.Response<String> = try await session.respond(to: "How many open issues does the repo have?")

        #expect(response.content == "There are 42 open issues.")

        // The discovery text the model actually saw between the two steps —
        // the exact worked findAPIs("...") -> runCode(...) example: a
        // rendered block naming the fully-qualified tools.github.issueCount
        // path, plus a runnable, properly-qualified example call (never the
        // bare, wrong tools.issueCount(...) a model couldn't guess to
        // qualify on its own — task 12rtn85's fix).
        let discovery = try #require(Self.toolOutputText(in: session.transcript, from: "findAPIs"))
        #expect(discovery.contains("findAPIs(\"count open github issues\") found:"))
        #expect(discovery.contains("// tools.github.issueCount"))
        #expect(discovery.contains("tools.github.issueCount("))
        #expect(!discovery.contains("tools.issueCount("))

        // The handoff is real, not merely scripted: runCode's own real
        // execution — using the exact qualified call findAPIs's discovery
        // text handed back — actually called the real IssueCountTool.
        let runCodeOutput = try #require(Self.toolOutputText(in: session.transcript, from: "runCode"))
        #expect(runCodeOutput.contains("42"))
    }
}
