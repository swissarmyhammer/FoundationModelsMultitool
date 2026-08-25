import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the ``PatchParser`` pure `patch files` envelope parser.
///
/// This suite is a port of the sibling FileTool suite
/// (`../FoundationModelsFileTool/Tests/FileToolTests/PatchParserTests.swift`).
/// The parser is IO-free: it turns a `patch files` envelope string — the codex
/// apply_patch file-op headers with `@@` hunks replaced by hashline-style
/// Find/Replace bodies — into an ordered list of ``PatchParser/Hunk`` values, or
/// a ``ParseFailure`` carrying a corrective message and a 1-based line number.
/// These tests exercise the worked multi-section example, each section kind in
/// isolation, the Add contents round-trip, the pure-rename and pairs-only
/// update shapes, hashline pass-through, whitespace-tolerant markers,
/// duplicate-path rejection, the empty envelope, every enumerated error rule
/// with its expected line number, and the ``CorrectiveFailure`` conformance
/// this package adds beside the port.
@Suite struct PatchParserTests {
    // MARK: Helpers

    /// The hunks of a patch that must parse, failing the test otherwise.
    ///
    /// - Parameter patch: the envelope to parse.
    /// - Returns: the parsed hunks, or an empty array after recording an issue.
    private func hunks(_ patch: String) -> [PatchParser.Hunk] {
        switch PatchParser.parse(patch) {
        case .success(let hunks):
            return hunks
        case .failure(let failure):
            Issue.record("expected success, got failure: \(failure.message) (line \(failure.line))")
            return []
        }
    }

    /// The failure of a patch that must not parse, failing the test otherwise.
    ///
    /// - Parameter patch: the envelope to parse.
    /// - Returns: the parse failure, or a sentinel after recording an issue.
    private func failure(_ patch: String) -> ParseFailure {
        switch PatchParser.parse(patch) {
        case .success(let hunks):
            Issue.record("expected failure, got success: \(hunks)")
            return ParseFailure(message: "", line: -1)
        case .failure(let failure):
            return failure
        }
    }

    // MARK: Worked example

    @Test func workedMultiSectionExampleParses() {
        let patch = """
            *** Begin Patch
            *** Add File: added.txt
            +new content
            *** Update File: existing.txt
            *** Move to: renamed.txt
            *** Find:
            12:a7|old line
            *** Replace:
            new line
            *** Delete File: gone.txt
            *** End Patch
            """
        #expect(
            hunks(patch) == [
                .addFile(path: "added.txt", contents: "new content\n"),
                .updateFile(
                    path: "existing.txt",
                    movePath: "renamed.txt",
                    pairs: [(find: "12:a7|old line", replace: "new line")]
                ),
                .deleteFile(path: "gone.txt"),
            ]
        )
    }

    // MARK: Section kinds alone

    @Test func addFileAlone() {
        let patch = """
            *** Begin Patch
            *** Add File: notes.txt
            +line one
            +line two
            *** End Patch
            """
        #expect(hunks(patch) == [.addFile(path: "notes.txt", contents: "line one\nline two\n")])
    }

    @Test func deleteFileAlone() {
        let patch = """
            *** Begin Patch
            *** Delete File: obsolete.txt
            *** End Patch
            """
        #expect(hunks(patch) == [.deleteFile(path: "obsolete.txt")])
    }

    @Test func updateWithPairsOnly() {
        let patch = """
            *** Begin Patch
            *** Update File: main.swift
            *** Find:
            let x = 1
            *** Replace:
            let x = 2
            *** End Patch
            """
        #expect(
            hunks(patch) == [
                .updateFile(path: "main.swift", movePath: nil, pairs: [(find: "let x = 1", replace: "let x = 2")])
            ]
        )
    }

    @Test func updateWithMultilineFindAndReplace() {
        let patch = """
            *** Begin Patch
            *** Update File: main.swift
            *** Find:
            foo
            bar
            *** Replace:
            baz
            qux
            *** End Patch
            """
        #expect(
            hunks(patch) == [
                .updateFile(path: "main.swift", movePath: nil, pairs: [(find: "foo\nbar", replace: "baz\nqux")])
            ]
        )
    }

    @Test func updateMoveOnlyIsPureRename() {
        let patch = """
            *** Begin Patch
            *** Update File: old.txt
            *** Move to: new.txt
            *** End Patch
            """
        #expect(hunks(patch) == [.updateFile(path: "old.txt", movePath: "new.txt", pairs: [])])
    }

    @Test func updateWithMoveAndPairs() {
        let patch = """
            *** Begin Patch
            *** Update File: old.txt
            *** Move to: new.txt
            *** Find:
            a
            *** Replace:
            b
            *** Find:
            c
            *** Replace:
            d
            *** End Patch
            """
        #expect(
            hunks(patch) == [
                .updateFile(
                    path: "old.txt",
                    movePath: "new.txt",
                    pairs: [(find: "a", replace: "b"), (find: "c", replace: "d")]
                )
            ]
        )
    }

    // MARK: Add contents round-trip

    @Test func addWithZeroLinesYieldsEmptyContents() {
        let patch = """
            *** Begin Patch
            *** Add File: empty.txt
            *** End Patch
            """
        #expect(hunks(patch) == [.addFile(path: "empty.txt", contents: "")])
    }

    @Test func addStripsPlusPrefixAndAppendsTrailingNewline() {
        let patch = """
            *** Begin Patch
            *** Add File: a.txt
            +only line
            *** End Patch
            """
        #expect(hunks(patch) == [.addFile(path: "a.txt", contents: "only line\n")])
    }

    // MARK: Hashline pass-through

    @Test func hashlineTaggedFindBodyPassesThroughByteIdentical() {
        let patch = """
            *** Begin Patch
            *** Update File: code.swift
            *** Find:
            12:a7|    let value = 1
            *** Replace:
                let value = 2
            *** End Patch
            """
        #expect(
            hunks(patch) == [
                .updateFile(
                    path: "code.swift",
                    movePath: nil,
                    pairs: [(find: "12:a7|    let value = 1", replace: "    let value = 2")]
                )
            ]
        )
    }

    // MARK: Whitespace-tolerant markers

    @Test func whitespaceAroundMarkersIsTolerated() {
        let patch =
            "   *** Begin Patch  \n"
            + "\t*** Delete File: x.txt\n"
            + "  *** End Patch   \n"
        #expect(hunks(patch) == [.deleteFile(path: "x.txt")])
    }

    // MARK: Empty envelope

    @Test func emptyEnvelopeYieldsZeroHunks() {
        let patch = """
            *** Begin Patch
            *** End Patch
            """
        #expect(hunks(patch) == [])
    }

    // MARK: Error rules

    @Test func missingBeginPatchIsError() {
        let patch = """
            garbage line
            *** Begin Patch
            *** End Patch
            """
        let failure = failure(patch)
        #expect(failure.message.contains("Begin Patch"))
        #expect(failure.line == 1)
    }

    @Test func heredocWrappedEnvelopeFailsAsEnvelopeError() {
        // Documented divergence from grok: no heredoc leniency. An unrecognized
        // first line is a plain envelope error, not a stripped `<<EOF` wrapper.
        let patch = """
            <<EOF
            *** Begin Patch
            *** End Patch
            EOF
            """
        let failure = failure(patch)
        #expect(failure.message.contains("Begin Patch"))
        #expect(failure.line == 1)
    }

    @Test func missingEndPatchIsError() {
        let patch = """
            *** Begin Patch
            *** Delete File: x.txt
            """
        let failure = failure(patch)
        #expect(failure.message.contains("End Patch"))
        #expect(failure.line == 2)
    }

    @Test func unknownMarkerIsError() {
        let patch = """
            *** Begin Patch
            *** Frobnicate: x.txt
            *** End Patch
            """
        let failure = failure(patch)
        #expect(failure.message.contains("Unknown"))
        #expect(failure.message.contains("Frobnicate"))
        #expect(failure.line == 2)
    }

    @Test func replaceWithoutPrecedingFindIsError() {
        let patch = """
            *** Begin Patch
            *** Update File: a.txt
            *** Replace:
            foo
            *** End Patch
            """
        let failure = failure(patch)
        #expect(failure.message.contains("preceded"))
        #expect(failure.line == 3)
    }

    @Test func findWithEmptyBodyIsError() {
        let patch = """
            *** Begin Patch
            *** Update File: a.txt
            *** Find:
            *** Replace:
            foo
            *** End Patch
            """
        let failure = failure(patch)
        #expect(failure.message.contains("non-empty"))
        #expect(failure.line == 3)
    }

    @Test func findWithoutFollowingReplaceIsError() {
        let patch = """
            *** Begin Patch
            *** Update File: a.txt
            *** Find:
            foo
            *** Delete File: b.txt
            *** End Patch
            """
        let failure = failure(patch)
        #expect(failure.message.contains("followed"))
        #expect(failure.line == 3)
    }

    @Test func updateWithNeitherPairsNorMoveIsError() {
        let patch = """
            *** Begin Patch
            *** Update File: a.txt
            *** End Patch
            """
        let failure = failure(patch)
        #expect(failure.message.contains("at least one"))
        #expect(failure.line == 2)
    }

    @Test func duplicatePathAcrossSectionsIsError() {
        let patch = """
            *** Begin Patch
            *** Delete File: dup.txt
            *** Delete File: dup.txt
            *** End Patch
            """
        let failure = failure(patch)
        #expect(failure.message.contains("more than one"))
        #expect(failure.message.contains("dup.txt"))
        #expect(failure.line == 3)
    }

    // MARK: Corrective conformance

    @Test func correctiveMessageCarriesTheLineNumber() {
        let failure = ParseFailure(message: "A `patch files` envelope must begin with `*** Begin Patch`.", line: 2)
        #expect(failure.correctiveMessage == "\(failure.message) (line 2)")
    }
}
