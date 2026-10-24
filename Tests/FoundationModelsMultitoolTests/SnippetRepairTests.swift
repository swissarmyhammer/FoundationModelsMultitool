// `SnippetRepairTests` — a snippet that does not parse because of one small
// typo is repaired, run, and the result says what was repaired ("Postel's
// rule": be liberal in what you accept).
//
// SWE-bench run bench24-1023b, django__django-13964 (child session, seq
// 4702): one missing `:` failed a whole snippet of three `grepCode` calls
// with "Expected a ':' following the property name 'pattern'".

import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The arguments of the stand-in `code_context.grepCode`.
@Generable
struct RepairGrepCodeArguments {
    @Guide(description: "The pattern.")
    var pattern: String
    @Guide(description: "The file pattern.")
    var filePattern: String?
    @Guide(description: "The most results.")
    var maxResults: Int?
}

/// A stand-in for `code_context.grepCode` that answers its own arguments.
struct RepairGrepCodeTool: Tool {
    let name = "grepCode"
    let description = "Searches the indexed code with a regular expression."
    func call(arguments: RepairGrepCodeArguments) async throws -> String {
        "\(arguments.pattern) in \(arguments.filePattern ?? "*")"
    }
}

/// One match of the stand-in `code_context.grepCode` that answers matches.
@Generable
struct RepairMatch {
    @Guide(description: "The file.")
    var filePath: String
    @Guide(description: "The line.")
    var startLine: Int
    @Guide(description: "The text.")
    var text: String
}

/// The result of the stand-in `code_context.grepCode` that answers matches.
@Generable
struct RepairMatchesResult {
    @Guide(description: "The matches.")
    var matches: [RepairMatch]
}

/// A stand-in for `code_context.grepCode` that answers one match per call.
struct RepairMatchesTool: Tool {
    let name = "grepCode"
    let description = "Searches the indexed code with a regular expression."
    func call(arguments: RepairGrepCodeArguments) async throws -> RepairMatchesResult {
        RepairMatchesResult(matches: [RepairMatch(filePath: "tests/x.py", startLine: 1, text: arguments.pattern)])
    }
}

@Suite("SnippetRepairTests")
struct SnippetRepairTests {

    /// The snippet of the run, byte for byte.
    private static let missingColonSnippet = """
        const g1 = await tools.code_context.grepCode({ pattern: "unsaved", filePattern: "tests/related_fields/*", maxResults: 20 });
        const g2 = await tools.code_context.grepCode({ pattern: "unsaved", filePattern: "tests/one_to_one/*", maxResults: 20 });
        const g3 = await tools.code_context.grepCode({ pattern "unsaved", filePattern: "tests/many_to_one/*", maxResults: 20 });
        return [g1, g2, g3];
        """

    /// Runs `code` on a surface with the stand-in `code_context` group.
    private func run(_ code: String) async throws -> String {
        let registry = try MultiTool.Builder()
            .addGroup(named: "code_context", [RepairGrepCodeTool()])
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    /// The rendered value before the repair note, and the note.
    private func split(_ output: String) -> (value: String, note: String?) {
        guard let range = output.range(of: "\n\n" + SnippetRepair.notePrefix) else { return (output, nil) }
        return (String(output[..<range.lowerBound]), String(output[range.lowerBound...].dropFirst(2)))
    }

    @Test("the snippet of the run, with one missing ':', is repaired and runs all three calls")
    func theMissingColonIsRepaired() async throws {
        let output = try await run(Self.missingColonSnippet)
        let (value, note) = split(output)

        #expect(
            try RunOutput.decoded([String].self, from: value) == [
                "unsaved in tests/related_fields/*", "unsaved in tests/one_to_one/*",
                "unsaved in tests/many_to_one/*",
            ], "output was: \(output)")
        #expect(note == "Repaired: added ':' after 'pattern' on line 3.", "output was: \(output)")
    }

    @Test("a missing ',' between properties on separate lines is repaired")
    func aMissingCommaIsRepaired() async throws {
        let output = try await run(
            """
            const g = await tools.code_context.grepCode({
              pattern: "a"
              filePattern: "b"
            });
            return g;
            """)
        let (value, note) = split(output)

        #expect(try RunOutput.decoded(String.self, from: value) == "a in b", "output was: \(output)")
        #expect(note == "Repaired: added ',' at the end of line 2.", "output was: \(output)")
    }

    @Test("an extra closer at the end is removed, and a missing one is added")
    func anUnbalancedCloserIsRepaired() async throws {
        let extra = try await run(#"return await tools.code_context.grepCode({ pattern: "a" }));"#)
        let missing = try await run(#"return await tools.code_context.grepCode({ pattern: "a" }"#)

        #expect(try RunOutput.decoded(String.self, from: split(extra).value) == "a in *", "output was: \(extra)")
        #expect(split(extra).note == "Repaired: removed an extra ')' at the end.", "output was: \(extra)")
        #expect(try RunOutput.decoded(String.self, from: split(missing).value) == "a in *", "output was: \(missing)")
        #expect(split(missing).note == "Repaired: added a missing ')' at the end.", "output was: \(missing)")
    }

    /// The snippet of bench24-1023b, django__django-14017 (child session, seq
    /// 7751), byte for byte: line 2 is missing its ')' before the ';'.
    private static let missingMidCloserSnippet = """
        const r1 = await tools.code_context.grepCode({ pattern: "class CombinableTests", filePattern: "tests/*", maxResults: 10 });
        const r2 = await tools.code_context.grepCode({ pattern: "NotImplementedError", filePattern: "tests/*", maxResults: 30 };
        const fmt = (m) => ({ f: m.filePath, l: m.startLine, t: m.text.replace(/\\n/g, " ").slice(0, 140) });
        return { r1: r1.matches.map(fmt), r2: r2.matches.map(fmt) };
        """

    @Test("a closer missing before the ';' of a middle line is added there")
    func aMissingCloserInTheMiddleIsRepaired() async throws {
        let registry = try MultiTool.Builder()
            .addGroup(named: "code_context", [RepairMatchesTool()])
            .buildRegistry()
        let output = try await MultiTool(registry: registry).call(
            arguments: RunCodeArguments(code: Self.missingMidCloserSnippet))
        let value = split(output).value

        #expect(!output.contains("The snippet failed"), "output was: \(output)")
        #expect(value.contains("CombinableTests") && value.contains("NotImplementedError"), "output was: \(output)")
        #expect(split(output).note == "Repaired: added a missing ')' at the end of line 2.", "output was: \(output)")
    }

    /// Runs `code` on a surface with the stand-in `grepCode` that answers
    /// matches.
    private func runMatches(_ code: String) async throws -> String {
        let registry = try MultiTool.Builder()
            .addGroup(named: "code_context", [RepairMatchesTool()])
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    /// bench24-1023b, django__django-14672 (seq 17733): the `}` of the object
    /// is missing before the `)`.
    private static let missingBraceSnippet = """
        const c4 = await tools.code_context.grepCode({ pattern: "class FieldCacheMixin", maxResults: 3 );
        return c4.matches.map((m) => m.text);
        """

    @Test("a '}' missing before the ')' of a call is added there")
    func aMissingBraceBeforeTheParenIsRepaired() async throws {
        let output = try await runMatches(Self.missingBraceSnippet)
        let (value, note) = split(output)

        #expect(try RunOutput.decoded([String].self, from: value) == ["class FieldCacheMixin"], "output was: \(output)")
        #expect(note == "Repaired: added '}' before ')' on line 1.", "output was: \(output)")
    }

    /// bench24-1023b, django__django-14672 (seq 17753): the same slip on two
    /// lines; the run elided the first pattern.
    private static let twoMissingBracesSnippet = """
        const a = await tools.code_context.grepCode({ pattern: "class FieldCacheMixin", maxResults: 5 });
        const b = await tools.code_context.grepCode({ pattern: "def __hash__", filePattern: "django/db/models/*", maxResults: 15 );
        const c = await tools.code_context.grepCode({ pattern: "hash\\\\(", filePattern: "django/core/checks/*", maxResults: 10 );
        return [a, b, c].map((r) => r.matches[0].text);
        """

    @Test("the same slip on two lines is repaired on both, one edit at a time")
    func theSameSlipOnTwoLinesIsRepaired() async throws {
        let output = try await runMatches(Self.twoMissingBracesSnippet)
        let (value, note) = split(output)

        #expect(
            try RunOutput.decoded([String].self, from: value) == ["class FieldCacheMixin", "def __hash__", #"hash\("#],
            "output was: \(output)")
        #expect(note == "Repaired: added '}' before ')' on lines 2 and 3.", "output was: \(output)")
    }

    @Test("a step with two repairs that parse further stops the repair")
    func twoStepsThatParseFurtherAreAmbiguous() {
        // Both candidates move the error to a later line, thus the meaning is
        // not clear, and nothing is repaired.
        let repaired = SnippetRepair.repair(
            "x",
            check: { $0 == "x" ? .fails(line: 1) : .fails(line: 2) },
            candidates: { _ in [.init(code: "x;", note: "one"), .init(code: "x+0", note: "two")] })
        #expect(repaired == nil)
    }

    @Test("the edits stop at the most edits")
    func theEditsStopAtTheMost() {
        // Each edit moves the error one line further and none parses.
        let repaired = SnippetRepair.repair(
            "",
            check: { .fails(line: $0.count + 1) },
            candidates: { [.init(code: $0 + "x", note: "added 'x' on line \($0.count + 1)")] })
        #expect(repaired == nil)
    }

    @Test("a snippet no single repair makes parse gives the parse error as before")
    func anUnrepairableSnippetGivesTheParseError() async throws {
        let output = try await run("return {{{ ]]] ;;; (((")

        #expect(output.contains("The snippet failed"), "output was: \(output)")
        #expect(!output.contains(SnippetRepair.notePrefix))
    }

    @Test("a snippet that parses and then throws is never repaired")
    func aRuntimeErrorIsNotRepaired() async throws {
        let output = try await run("throw new Error(\"boom\");")

        #expect(output.contains("boom"), "output was: \(output)")
        #expect(!output.contains(SnippetRepair.notePrefix))
    }

    @Test("the repair answers nothing when two repairs parse")
    func twoRepairsThatParseAreAmbiguous() {
        // The stand-in parser accepts each candidate, thus the meaning is
        // not clear, and nothing is repaired.
        let repaired = SnippetRepair.repair(
            "x", parses: { $0 != "x" },
            candidates: [.init(code: "x;", note: "one"), .init(code: "x+0", note: "two")])
        #expect(repaired == nil)
    }
}
