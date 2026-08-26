// `FilesCrossOpFlowTests` — the cross-operation flows of the files capability,
// driven end to end through `runCode`.
//
// The suites `FilesReadTests` through `FilesGrepTests` prove each verb alone,
// through direct `Verb.call(arguments:)` calls. This suite proves the six
// verbs as one session through the code-mode surface instead: each test runs
// one JavaScript snippet through `MultiTool.call(arguments:)`, which goes
// through the JSC interpreter and `ToolInvoker` — never through direct engine
// calls. The pattern is `SiblingToolPathTests` (a snippet drives a mounted
// surface) and the sibling cross-op suite at `../FoundationModelsFileTool/
// Tests/FileToolIntegrationTests/CrossOpFlowTests.swift` (the operations
// chain the way a model chains them).
//
// The intermediate-value criterion is read through the invocation ledger, in
// the pattern of `ToolReturnLedgerTests`: `MultiTool` wraps every `tools.*`
// binding so the run's `ToolReturnLedger` records what each inner call
// returned, and the rendered output ends with
// `ToolReturnLedger.uncarriedReturnNotice` when the snippet's own value
// carries none of it. A flow test asserts the notice is absent — the returned
// value carries the final value the inner calls produced — and the control
// test at the end asserts the notice fires when a snippet discards that
// value, which proves the ledger records the files calls at all.

import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The six files verbs as one session, each flow through one `runCode`
/// snippet against a temporary root.
///
/// The flows: write then read; glob then grep; a hashline read then an edit
/// by an anchor from that read; a patch then a read; a corrective answer
/// inside JavaScript that the snippet corrects in the same run; and a
/// `Promise.all` over two reads.
///
/// Each test roots its session in a temporary directory of its own, thus the
/// tests are independent and they run in parallel safely.
@Suite("FilesCrossOpFlowTests")
struct FilesCrossOpFlowTests {

    // MARK: - The names and contents of the fixture files

    /// The name of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryName = "FilesCrossOpFlowTests"

    /// The name of the directory that stands outside every session root.
    /// The corrective flow reads a file in it.
    private static let outsideDirectoryName = "FilesCrossOpFlowTests-outside"

    /// The file the write flow writes and the ledger control writes.
    private static let noteFileName = "note.txt"

    /// The content of ``noteFileName``: two lines, thus the read answers a
    /// list the test can compare.
    private static let noteContent = "alpha\nbeta\n"

    /// The `.txt` file whose line holds the grep needle.
    private static let alphaFileName = "alpha.txt"

    /// The content of ``alphaFileName``.
    private static let alphaContent = "needle here\n"

    /// The `.txt` file whose line does not hold the grep needle.
    private static let betaFileName = "beta.txt"

    /// The content of ``betaFileName``.
    private static let betaContent = "haystack only\n"

    /// The `.md` file whose line holds the needle. The glob and the grep
    /// filter both exclude it, thus a match in it would show a filter that
    /// did not narrow.
    private static let gammaFileName = "gamma.md"

    /// The content of ``gammaFileName``.
    private static let gammaContent = "needle in markdown\n"

    /// The glob pattern of the `.txt` fixtures. Not a broad pattern, thus
    /// the glob verb needs no `path` argument.
    private static let txtGlobPattern = "*.txt"

    /// The text the grep flow searches for.
    private static let grepNeedle = "needle"

    /// The file the edit flow and the patch flow change.
    private static let threeLineFileName = "code.txt"

    /// The file the patch flow updates. A name of its own, thus the two
    /// mutation flows cannot mask each other.
    private static let patchFileName = "update.txt"

    /// The seeded content of the two mutation flows: three lines, and the
    /// middle one is the edit target.
    private static let threeLineContent = "one\ntwo\nthree\n"

    /// The content the two mutation flows leave on disk: the middle line
    /// rewritten in upper case.
    private static let editedThreeLineContent = "one\nTWO\nthree\n"

    /// The `find` text of the patch envelope.
    private static let patchFindText = "two"

    /// The `replace` text of the edit call and of the patch envelope.
    private static let replacementText = "TWO"

    /// The file the corrective flow reads inside the root.
    private static let insideFileName = "inside.txt"

    /// The content of ``insideFileName``.
    private static let insideContent = "safe content\n"

    /// The file the corrective flow asks for outside the root.
    private static let outsideFileName = "secret.txt"

    /// The content of ``outsideFileName``. It exists, thus the correction
    /// reports the boundary and not a missing file.
    private static let outsideContent = "outside content\n"

    /// The first file of the parallel flow.
    private static let firstFileName = "first.txt"

    /// The content of ``firstFileName``.
    private static let firstContent = "first content\n"

    /// The second file of the parallel flow.
    private static let secondFileName = "second.txt"

    /// The content of ``secondFileName``.
    private static let secondContent = "second content\n"

    /// The sentence the corrective flow returns when the outside read came
    /// back with no correction. A test that reads this text in the output
    /// fails, thus the flow proves the correction arrived inside JavaScript.
    private static let uncorrectedMarker = "the outside read was not corrected"

    /// The sentence the ledger control returns in place of the value. It
    /// carries nothing the write returned, thus the ledger's notice fires.
    private static let discardedValueSentence = "The write began."

    /// The fragment of an encoded edit outcome that names an anchor match.
    /// `EditOutcomeProjection` encodes the outcomes with sorted keys, thus
    /// the fragment is stable.
    private static let anchorOutcomeFragment = #""matchedBy":"anchor""#

    // MARK: - The ground of one test

    /// The lines of `content` without their terminators, as the `plain`
    /// read format answers them.
    ///
    /// - Parameter content: the file content to split.
    /// - Returns: the plain lines.
    private static func plainLines(of content: String) -> [String] {
        Hashline.splitLines(content).map(\.text)
    }

    /// A session root directory this test owns.
    ///
    /// - Returns: A directory no other test shares.
    private static func makeRoot() -> URL {
        TestSupport.makeTemporaryDirectory(named: testDirectoryName)
    }

    /// Puts one UTF-8 file into a directory before a snippet runs.
    ///
    /// - Parameters:
    ///   - name: the file name.
    ///   - contents: the file's UTF-8 content.
    ///   - directory: the directory to put the file in.
    /// - Throws: When the file does not write.
    private static func seed(_ name: String, _ contents: String, in directory: URL) throws {
        try Data(contents.utf8)
            .write(to: directory.appendingPathComponent(name, isDirectory: false))
    }

    /// The on-disk content of one file under `root`.
    ///
    /// - Parameters:
    ///   - name: the file name.
    ///   - root: the session root.
    /// - Returns: the file's UTF-8 content.
    /// - Throws: When the file does not read.
    private static func diskContents(_ name: String, in root: URL) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(name, isDirectory: false), encoding: .utf8)
    }

    /// Runs one snippet against a surface that holds the files capability
    /// alone, rooted at `root`.
    ///
    /// The call goes through `MultiTool.call(arguments:)`, thus through the
    /// JSC interpreter, the `tools.*` bindings, and `ToolInvoker` — the same
    /// path a model's snippet takes.
    ///
    /// - Parameters:
    ///   - code: the snippet to run.
    ///   - root: the session root of the files capability.
    /// - Returns: the rendered output, as the model would read it.
    /// - Throws: whatever `MultiTool.call(arguments:)` throws.
    private static func run(_ code: String, root: URL) async throws -> String {
        let registry = try MultiTool.Builder().withFiles(root: root).buildRegistry()
        return try await MultiTool(registry: registry)
            .call(arguments: RunCodeArguments(code: code))
    }

    /// Decodes the JSON value one run returned.
    ///
    /// - Parameters:
    ///   - type: the value type to decode.
    ///   - output: the rendered run output.
    /// - Returns: the decoded value.
    /// - Throws: When `output` is not the JSON text of `type`. The raw
    ///   output is recorded first, thus the failure names what came back.
    private static func decoded<Value: Decodable>(
        _ type: Value.Type, from output: String
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: Data(output.utf8))
        } catch {
            Issue.record("the output did not decode as \(type): \(output)")
            throw error
        }
    }

    // MARK: - Write then read

    @Test("a snippet writes a file and reads the same content back")
    func writeThenReadAnswersTheWrittenContent() async throws {
        let root = Self.makeRoot()

        let output = try await Self.run(
            """
            const written = await tools.files.write({ path: "\(Self.noteFileName)", content: `\(Self.noteContent)` });
            if (written.correction) { return written.correction; }
            const read = await tools.files.read({ path: "\(Self.noteFileName)", format: "plain" });
            if (read.correction) { return read.correction; }
            return read.lines;
            """, root: root)

        #expect(
            !output.contains(ToolReturnLedger.uncarriedReturnNotice), "output was: \(output)")
        let lines = try Self.decoded([String].self, from: output)
        #expect(lines == Self.plainLines(of: Self.noteContent))
        #expect(try Self.diskContents(Self.noteFileName, in: root) == Self.noteContent)
    }

    // MARK: - Glob then grep

    /// The value the glob-then-grep snippet returns: the globbed files in
    /// name order, and the files whose lines matched the grep.
    private struct GlobGrepValue: Decodable {
        /// The globbed files, sorted by name inside the snippet. The glob
        /// answers newest first, and the fixture timestamps are not stable.
        let found: [String]

        /// The files of the matched grep lines.
        let matched: [String]
    }

    @Test("a snippet globs the root and greps a match in the found files")
    func globThenGrepMatchesInsideTheGlobbedFiles() async throws {
        let root = Self.makeRoot()
        try Self.seed(Self.alphaFileName, Self.alphaContent, in: root)
        try Self.seed(Self.betaFileName, Self.betaContent, in: root)
        try Self.seed(Self.gammaFileName, Self.gammaContent, in: root)

        let output = try await Self.run(
            """
            const globbed = await tools.files.glob({ pattern: "\(Self.txtGlobPattern)" });
            if (globbed.correction) { return globbed.correction; }
            const grep = await tools.files.grep({ pattern: "\(Self.grepNeedle)", glob: "\(Self.txtGlobPattern)" });
            if (grep.correction) { return grep.correction; }
            return {
                found: globbed.files.slice().sort(),
                matched: grep.matches.filter((m) => m.isMatch).map((m) => m.file),
            };
            """, root: root)

        #expect(
            !output.contains(ToolReturnLedger.uncarriedReturnNotice), "output was: \(output)")
        let value = try Self.decoded(GlobGrepValue.self, from: output)
        #expect(value.found == [Self.alphaFileName, Self.betaFileName])
        #expect(value.matched == [Self.alphaFileName])
    }

    // MARK: - Read then edit by an anchor

    /// The value the read-then-edit snippet returns: the edit's status, its
    /// encoded outcomes, and the committed tagged content.
    private struct EditValue: Decodable {
        /// The whole-batch status.
        let status: String

        /// The per-pair outcomes as JSON text.
        let outcomes: [String]

        /// The committed content with its hashline anchors.
        let lines: [String]
    }

    @Test("a snippet reads hashline anchors and edits by an anchor from that read")
    func readThenEditResolvesTheAnchorFromTheRead() async throws {
        let root = Self.makeRoot()
        try Self.seed(Self.threeLineFileName, Self.threeLineContent, in: root)

        let output = try await Self.run(
            """
            const read = await tools.files.read({ path: "\(Self.threeLineFileName)" });
            if (read.correction) { return read.correction; }
            const anchor = read.lines[1];
            const edited = await tools.files.edit({ path: "\(Self.threeLineFileName)", find: [anchor], replace: ["\(Self.replacementText)"] });
            if (edited.correction) { return edited.correction; }
            return { status: edited.status, outcomes: edited.outcomes, lines: edited.taggedContent };
            """, root: root)

        #expect(
            !output.contains(ToolReturnLedger.uncarriedReturnNotice), "output was: \(output)")
        let value = try Self.decoded(EditValue.self, from: output)
        #expect(value.status == EditOutcomeProjection.appliedStatus)
        #expect(
            value.outcomes.contains { $0.contains(Self.anchorOutcomeFragment) },
            "outcomes were: \(value.outcomes)")
        #expect(value.lines == Hashline.taggedLines(of: Self.editedThreeLineContent))
        #expect(
            try Self.diskContents(Self.threeLineFileName, in: root)
                == Self.editedThreeLineContent)
    }

    // MARK: - Patch then read

    @Test("a snippet applies a patch and reads the changed file")
    func patchThenReadAnswersThePatchedContent() async throws {
        let root = Self.makeRoot()
        try Self.seed(Self.patchFileName, Self.threeLineContent, in: root)

        let output = try await Self.run(
            """
            const patched = await tools.files.patch({ patch: `*** Begin Patch
            *** Update File: \(Self.patchFileName)
            *** Find:
            \(Self.patchFindText)
            *** Replace:
            \(Self.replacementText)
            *** End Patch
            ` });
            if (patched.correction) { return patched.correction; }
            const read = await tools.files.read({ path: "\(Self.patchFileName)", format: "plain" });
            if (read.correction) { return read.correction; }
            return read.lines;
            """, root: root)

        #expect(
            !output.contains(ToolReturnLedger.uncarriedReturnNotice), "output was: \(output)")
        let lines = try Self.decoded([String].self, from: output)
        #expect(lines == Self.plainLines(of: Self.editedThreeLineContent))
        #expect(
            try Self.diskContents(Self.patchFileName, in: root) == Self.editedThreeLineContent)
    }

    // MARK: - A correction inside JavaScript

    /// A path outside the root answers a `correction` inside JavaScript, and
    /// the run does not throw. The snippet reads the correction, corrects the
    /// call in the same run, and returns the corrected call's value alone.
    @Test("a path outside the root corrects in band, and the snippet corrects the call in the same run")
    func anOutsidePathCorrectsInBandAndTheSnippetRecovers() async throws {
        let root = Self.makeRoot()
        try Self.seed(Self.insideFileName, Self.insideContent, in: root)
        let outside = TestSupport.makeTemporaryDirectory(named: Self.outsideDirectoryName)
        try Self.seed(Self.outsideFileName, Self.outsideContent, in: outside)
        let outsidePath = TestSupport.path(Self.outsideFileName, in: outside)

        let output = try await Self.run(
            """
            const blocked = await tools.files.read({ path: "\(outsidePath)" });
            if (!blocked.correction) { return "\(Self.uncorrectedMarker)"; }
            const inside = await tools.files.read({ path: "\(Self.insideFileName)", format: "plain" });
            return inside.lines;
            """, root: root)

        #expect(!output.contains(Self.uncorrectedMarker), "output was: \(output)")
        #expect(
            !output.contains(ToolReturnLedger.uncarriedReturnNotice), "output was: \(output)")
        let lines = try Self.decoded([String].self, from: output)
        #expect(lines == Self.plainLines(of: Self.insideContent))
    }

    // MARK: - Parallel reads

    /// eventplan.md § "Async JavaScript": a snippet's promises settle inside
    /// the run, thus a `Promise.all` over two reads settles both and the
    /// snippet returns their values together.
    @Test("Promise.all over two reads settles both")
    func promiseAllOverTwoReadsSettlesBoth() async throws {
        let root = Self.makeRoot()
        try Self.seed(Self.firstFileName, Self.firstContent, in: root)
        try Self.seed(Self.secondFileName, Self.secondContent, in: root)

        let output = try await Self.run(
            """
            const [first, second] = await Promise.all([
                tools.files.read({ path: "\(Self.firstFileName)", format: "plain" }),
                tools.files.read({ path: "\(Self.secondFileName)", format: "plain" }),
            ]);
            return [first.lines[0], second.lines[0]];
            """, root: root)

        #expect(
            !output.contains(ToolReturnLedger.uncarriedReturnNotice), "output was: \(output)")
        let lines = try Self.decoded([String].self, from: output)
        #expect(
            lines == [
                Self.plainLines(of: Self.firstContent).first,
                Self.plainLines(of: Self.secondContent).first,
            ].compactMap { $0 })
    }

    // MARK: - The ledger control

    /// The control for the notice-absence assertions above: the same write
    /// runs, the snippet discards its value, and the ledger's notice fires.
    /// This proves the run's ledger records the files calls — the flows'
    /// notice-free outputs are a judgement, not silence.
    @Test("a snippet that discards a files result is told what it produced")
    func aDiscardedFilesResultGetsTheLedgerNotice() async throws {
        let root = Self.makeRoot()

        let output = try await Self.run(
            """
            await tools.files.write({ path: "\(Self.noteFileName)", content: `\(Self.noteContent)` });
            return "\(Self.discardedValueSentence)";
            """, root: root)

        #expect(output.hasSuffix(ToolReturnLedger.uncarriedReturnNotice))
        #expect(try Self.diskContents(Self.noteFileName, in: root) == Self.noteContent)
    }
}
