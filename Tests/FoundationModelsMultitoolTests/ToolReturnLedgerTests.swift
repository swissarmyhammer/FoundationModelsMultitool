import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool

/// Coverage for the in-band notice a `runCode` snippet gets back when it called
/// `tools.*` and returned a value carrying nothing those calls returned (task
/// `wnfzwxg`).
///
/// Driven end to end through `MultiTool.call`, because the notice is a fact
/// about a whole run — which `tools.*` calls it made, and what it handed
/// back — and a test that poked the ledger directly would prove the arithmetic
/// while proving that no snippet reaches it. The one bound no snippet can reach
/// is graded on the ledger itself, at the end.
///
/// The notice text is read from ``ToolReturnLedger/uncarriedReturnNotice``
/// rather than restated here, for ``RepairDirective/closingLine``'s reason: a
/// copy in a test would go on satisfying `!output.contains(_:)` after a reword,
/// holding whether or not anything was said.
@Suite("ToolReturnLedger")
struct ToolReturnLedgerTests {
    /// Runs one snippet against a `getIssueCount` binding and hands back the
    /// text the model would read.
    ///
    /// `IssueCountTool` is the fixture throughout: it takes an argument, so a
    /// call cannot be written by accident, and it answers one scalar, so what
    /// the run recorded is a set of exactly one value.
    ///
    /// - Parameter code: the snippet to run.
    /// - Returns: the rendered `runCode` output.
    /// - Throws: whatever `MultiTool.call(arguments:)` throws.
    private static func run(_ code: String) async throws -> String {
        let registry = try MultiTool.Builder().addTool(IssueCountTool()).buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    // MARK: - A snippet that promised instead of read

    @Test("a snippet that fires a tool, discards its return and answers in prose is told what it produced")
    func aSnippetThatNarratesIsToldItCarriedNothing() async throws {
        // The recorded failure, in miniature: the call happens, the value is
        // thrown away, and a sentence about the value goes back in its place.
        // Nothing about the shape of that snippet is wrong — it returns a
        // string, which is a successful snippet — so the whole of what
        // separates it from a real answer is what this notice says.
        let output = try await Self.run("""
            await tools.getIssueCount({ repo: 'demo' });
            return "I have started the issue count and will report it shortly.";
            """)

        #expect(output.contains(ToolReturnLedger.uncarriedReturnNotice))
    }

    @Test("the notice is the last thing the model reads, after the value and after any console output")
    func theNoticeClosesTheOutput() async throws {
        // Same placement as `RepairDirective.closingLine`: the action to take
        // next is the last line, so it is not buried above a console section
        // the model reads afterwards.
        let output = try await Self.run("""
            console.log('looked the repository up');
            await tools.getIssueCount({ repo: 'demo' });
            return "I will send the count along soon.";
            """)

        #expect(output.hasSuffix(ToolReturnLedger.uncarriedReturnNotice))
        #expect(output.contains("looked the repository up"))
    }

    // MARK: - Every snippet that really reported is left alone

    @Test("a snippet that returns the value its tool call gave it gets the value alone")
    func aSnippetThatReportsGetsNoNotice() async throws {
        // The passing shape. A notice here would be a false claim, and would
        // send a model that answered correctly back around for another turn.
        let output = try await Self.run("return (await tools.getIssueCount({ repo: 'demo' })).count;")

        #expect(output == "42")
    }

    @Test("a sentence built around the value a tool returned carries it, and gets the value alone")
    func aSentenceCarryingTheValueGetsNoNotice() async throws {
        // A returned string is not the defect; a returned string carrying
        // nothing is. This snippet formats the value it read into prose, which
        // still delivers it.
        let output = try await Self.run("""
            const issues = (await tools.getIssueCount({ repo: 'demo' })).count;
            return "Open issues: " + issues;
            """)

        #expect(output == "\"Open issues: 42\"")
    }

    @Test("a snippet that computed its answer, with no text in it at all, gets the value alone")
    func aComputedValueGetsNoNotice() async throws {
        // Doubling the count carries no text from the call, and it is not the
        // failure either: the narration this notice reports is a sentence, and
        // this value holds no sentence to mistake for one.
        let output = try await Self.run("return (await tools.getIssueCount({ repo: 'demo' })).count * 2;")

        #expect(output == "84")
    }

    @Test("a snippet that called no tool at all gets the value alone, whatever it returned")
    func aSnippetThatCalledNothingGetsNoNotice() async throws {
        // With no call recorded there is no value the snippet could have
        // carried, so there is nothing to say. `runCode` is a calculator as
        // well as a tool surface, and a plain computation must stay silent.
        let output = try await Self.run("return \"nothing was called here\";")

        #expect(output == "\"nothing was called here\"")
    }

    // MARK: - The bound no snippet can reach

    @Test("a run whose recorded values pass the bound judges nothing rather than guessing")
    func aLedgerPastItsBoundJudgesNothing() async throws {
        // The check is bounded, and past the bound it stays silent instead of
        // reporting on a comparison it did not make. Reached here directly:
        // a snippet large enough to cross the bound would grade the fixture's
        // size rather than this rule.
        let ledger = ToolReturnLedger()
        let wide = InterpreterValue.array(
            (0...ToolReturnLedger.maximumRecordedValues).map { .number(Double($0)) }
        )
        _ = await ledger.recording { wide }

        #expect(ledger.notice(forReturnValue: .string("a sentence carrying none of that")) == nil)
    }

    @Test("a run that recorded one value still judges the answer beside it")
    func aLedgerInsideItsBoundStillJudges() async throws {
        // The control for the bound above: the same ledger, one value under it,
        // reports.
        let ledger = ToolReturnLedger()
        _ = await ledger.recording { .number(Double(ToolReturnLedger.maximumRecordedValues)) }

        #expect(ledger.notice(forReturnValue: .string("a sentence carrying none of that")) != nil)
    }
}
