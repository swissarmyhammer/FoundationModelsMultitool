// `FileChangeSetTests` — the behavioral suite of the ACP change-set
// projection over the mutating file verbs.
//
// A port of `../FoundationModelsFileTool/Tests/FileToolTests/
// FileChangeSetTests.swift`, adapted to the `Tool` call shape: the sibling
// decoded `WriteFile`, `EditFile`, and `PatchFiles` operations out of
// `GeneratedContent`; here the suite constructs the argument structs with
// the memberwise initializers and calls the `Write`, `Edit`, and `Patch`
// verbs directly, the way `FilesPatchTests` calls its verb. The sibling's
// `filePath` parameter is the `path` parameter here. The sibling read the
// action-to-kind table as `PatchFiles.changeKinds`; the table lives on
// `Patch` in this package. The sibling's operation outputs were
// `Encodable` and were pinned through `JSONEncoder`; the flat results here
// are `@Generable`, thus the encoded-field and byte-identical tests read
// the `generatedContent` JSON instead. The sibling's write and edit field
// lists carried a `diagnostics` entry; this package has no diagnostics
// bridge (decision 2026-08-11 in eventplan.md), thus the pinned field
// lists name only the fields the flat results carry.

import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the ACP change-set projection: what a mutating
/// verb changed, and the git-format patch for that change set.
///
/// Covers the projection itself (one entry per affected file, carrying the
/// change kind and an absolute path, with move distinguishable from an
/// add-plus-delete pair), the opt-in recording seam on ``FileContext``, and
/// the rendered git patch.
@Suite struct FileChangeSetTests {
    // MARK: Test scaffolding

    /// The number of files the multi-file envelope touches: one add, one
    /// update, one delete, and one move.
    private static let touchedFileCount = 4

    /// Build a session context whose root is canonicalized, optionally seeded with files.
    ///
    /// - Parameters:
    ///   - recordsChanges: whether the context records a change set.
    ///   - files: the file names and UTF-8 contents to seed under the root.
    /// - Returns: the session context and its canonicalized root.
    /// - Throws: rethrows a seed-write failure.
    private static func makeContext(
        recordsChanges: Bool = true,
        seeding files: [(name: String, contents: String)] = []
    ) throws -> (context: FileContext, root: URL) {
        let root = TestSupport.canonicalDirectory(
            TestSupport.makeTemporaryDirectory(named: "FileChangeSetTests"))
        for file in files {
            try Data(file.contents.utf8).write(
                to: root.appendingPathComponent(file.name, isDirectory: false))
        }
        return (FileContext(root: root, recordsChanges: recordsChanges), root)
    }

    /// Run the `write` verb against a context.
    ///
    /// - Parameters:
    ///   - path: the absolute path to write.
    ///   - content: the content to write.
    ///   - context: the session context to run against.
    /// - Returns: the verb's flat result.
    @discardableResult
    private static func write(path: String, content: String, in context: FileContext) async throws
        -> WriteResult
    {
        try await Write(context: context).call(arguments: WriteArguments(path: path, content: content))
    }

    /// Run the `edit` verb against a context.
    ///
    /// - Parameters:
    ///   - path: the absolute path to edit.
    ///   - find: the `find` values.
    ///   - replace: the `replace` values.
    ///   - context: the session context to run against.
    /// - Returns: the verb's flat result.
    @discardableResult
    private static func edit(
        path: String,
        find: [String],
        replace: [String],
        in context: FileContext
    ) async throws -> EditResult {
        try await Edit(context: context).call(
            arguments: EditArguments(
                path: path, find: find, replace: replace, replacesAll: nil, occurrence: nil))
    }

    /// Run the `patch` verb against a context.
    ///
    /// - Parameters:
    ///   - body: the file-section text between the envelope markers.
    ///   - context: the session context to run against.
    /// - Returns: the verb's flat result.
    @discardableResult
    private static func patch(body: String, in context: FileContext) async throws -> PatchResult {
        let envelope = "*** Begin Patch\n\(body)\n*** End Patch\n"
        return try await Patch(context: context).call(arguments: PatchArguments(patch: envelope))
    }

    /// The change whose reported path ends with `suffix`.
    ///
    /// - Parameters:
    ///   - changes: the changes to search.
    ///   - suffix: the path suffix that identifies the wanted change.
    /// - Returns: the first matching change, or `nil` when none matches.
    private static func change(in changes: [FileChange], endingWith suffix: String) -> FileChange? {
        changes.first { $0.path.hasSuffix(suffix) }
    }

    /// The top-level field names of a result's `generatedContent` JSON, sorted.
    ///
    /// - Parameter output: the flat result to encode.
    /// - Returns: the encoded object's keys, in sorted order.
    /// - Throws: rethrows a JSON-reading failure.
    private static func encodedKeys(of output: some ConvertibleToGeneratedContent) throws -> [String] {
        try jsonObject(output.generatedContent.jsonString).keys.sorted()
    }

    /// The JSON object a text encodes.
    ///
    /// - Parameter text: the JSON text to read.
    /// - Returns: the top-level object, or an empty one when the text encodes
    ///   no object.
    /// - Throws: rethrows a JSON-reading failure.
    private static func jsonObject(_ text: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] ?? [:]
    }

    /// A change set with an add, a modify and a move, rooted at a canonical directory.
    ///
    /// The root comes from `FileWalker.canonicalDirectory(_:)`, the same call
    /// `FileChangeJournal` roots a drained set with, thus the round trip proves
    /// the shape a host receives.
    ///
    /// - Returns: the change set.
    private static func makeEnvelopeSet() -> FileChangeSet {
        let root = FileWalker.canonicalDirectory(
            TestSupport.makeTemporaryDirectory(named: "FileChangeSetTests"))
        return FileChangeSet(
            root: root,
            changes: [
                FileChange(
                    kind: .add, path: TestSupport.path("added.txt", in: root), newContent: "added\n"),
                FileChange(
                    kind: .modify,
                    path: TestSupport.path("code.txt", in: root),
                    oldContent: "one\ntwo\n",
                    newContent: "one\nTWO\n"
                ),
                FileChange(
                    kind: .move,
                    path: TestSupport.path("source.txt", in: root),
                    destinationPath: TestSupport.path("dest.txt", in: root),
                    oldContent: "keep me\n",
                    newContent: "keep me\n"
                ),
            ]
        )
    }

    /// Run one write, one edit, and one patch, returning their encoded results with the root elided.
    ///
    /// The session root differs between runs (each gets its own temporary
    /// directory), thus it is replaced by a fixed placeholder — everything
    /// else in the encoding must match byte for byte between a recording
    /// session and a non-recording one.
    ///
    /// - Parameter recordsChanges: whether the session records a change set.
    /// - Returns: the three encoded results, in operation order.
    /// - Throws: rethrows an operation or seed failure.
    private static func encodedMutationResults(recordsChanges: Bool) async throws -> [String] {
        let (context, root) = try makeContext(
            recordsChanges: recordsChanges,
            seeding: [("code.txt", "one\ntwo\n"), ("update.txt", "a\nb\n")]
        )
        let written = try await write(
            path: TestSupport.path("new.txt", in: root), content: "hello\n", in: context)
        let edited = try await edit(
            path: TestSupport.path("code.txt", in: root),
            find: ["two"],
            replace: ["TWO"],
            in: context
        )
        let patched = try await patch(
            body: """
                *** Update File: \(TestSupport.path("update.txt", in: root))
                *** Find:
                b
                *** Replace:
                B
                """,
            in: context
        )
        return [
            encodedJSON(of: written, eliding: root),
            encodedJSON(of: edited, eliding: root),
            encodedJSON(of: patched, eliding: root),
        ]
    }

    /// A result's `generatedContent` JSON with the session root replaced by a placeholder.
    ///
    /// The root path appears in three spellings. The top-level fields carry
    /// it plain. A per-file result of the patch verb is itself JSON text
    /// with `\/`-escaped separators, and the outer encoding escapes each of
    /// those backslashes again, thus the nested spelling is `\\/`. All
    /// three spellings are replaced, the most escaped one first.
    ///
    /// - Parameters:
    ///   - output: the flat result to encode.
    ///   - root: the session root to elide.
    /// - Returns: the encoded JSON, root-independent.
    private static func encodedJSON(of output: some ConvertibleToGeneratedContent, eliding root: URL) -> String {
        let nestedRoot = root.path.replacingOccurrences(of: "/", with: "\\\\/")
        let escapedRoot = root.path.replacingOccurrences(of: "/", with: "\\/")
        return output.generatedContent.jsonString
            .replacingOccurrences(of: nestedRoot, with: "<root>")
            .replacingOccurrences(of: escapedRoot, with: "<root>")
            .replacingOccurrences(of: root.path, with: "<root>")
    }

    // MARK: The write verb

    @Test func writeToANewPathProjectsAnAdd() async throws {
        let (context, root) = try Self.makeContext()
        let path = TestSupport.path("new.txt", in: root)

        try await Self.write(path: path, content: "hello\n", in: context)
        let changeSet = await context.changes.drain()

        #expect(changeSet.changes.count == 1)
        let change = try #require(changeSet.changes.first)
        #expect(change.kind == .add)
        #expect(change.path == path)
        #expect(change.oldContent == nil)
        #expect(change.newContent == "hello\n")
    }

    @Test func writeOverAnExistingPathProjectsAModify() async throws {
        let (context, root) = try Self.makeContext(seeding: [("kept.txt", "before\n")])
        let path = TestSupport.path("kept.txt", in: root)

        try await Self.write(path: path, content: "after\n", in: context)
        let changeSet = await context.changes.drain()

        let change = try #require(changeSet.changes.first)
        #expect(change.kind == .modify)
        #expect(change.path == path)
        #expect(change.oldContent == "before\n")
        #expect(change.newContent == "after\n")
    }

    @Test func aContextRecordsNothingUnlessAskedTo() async throws {
        let (context, root) = try Self.makeContext(recordsChanges: false)

        try await Self.write(
            path: TestSupport.path("new.txt", in: root), content: "hello\n", in: context)
        let changeSet = await context.changes.drain()

        #expect(changeSet.changes.isEmpty)
    }

    @Test func drainingClearsTheRecordedChanges() async throws {
        let (context, root) = try Self.makeContext()

        try await Self.write(
            path: TestSupport.path("new.txt", in: root), content: "hello\n", in: context)
        _ = await context.changes.drain()
        let second = await context.changes.drain()

        #expect(second.changes.isEmpty)
    }

    // MARK: The edit verb

    @Test func aSingleFileEditProjectsOneModifyWithAnAbsolutePath() async throws {
        let (context, root) = try Self.makeContext(seeding: [("code.txt", "one\ntwo\nthree\n")])
        let path = TestSupport.path("code.txt", in: root)

        try await Self.edit(path: path, find: ["two"], replace: ["TWO"], in: context)
        let changeSet = await context.changes.drain()

        #expect(changeSet.changes.count == 1)
        let change = try #require(changeSet.changes.first)
        #expect(change.kind == .modify)
        #expect(change.path == path)
        #expect(change.destinationPath == nil)
        #expect(change.oldContent == "one\ntwo\nthree\n")
        #expect(change.newContent == "one\nTWO\nthree\n")
    }

    @Test func editsAcrossThreeFilesProjectThreeChanges() async throws {
        let (context, root) = try Self.makeContext(seeding: [
            ("first.txt", "alpha\n"),
            ("second.txt", "beta\n"),
            ("third.txt", "gamma\n"),
        ])
        let names = ["first.txt", "second.txt", "third.txt"]

        for (name, find) in zip(names, ["alpha", "beta", "gamma"]) {
            try await Self.edit(
                path: TestSupport.path(name, in: root),
                find: [find],
                replace: [find.uppercased()],
                in: context
            )
        }
        let changeSet = await context.changes.drain()

        #expect(changeSet.changes.count == names.count)
        #expect(changeSet.changes.map(\.path) == names.map { TestSupport.path($0, in: root) })
        #expect(changeSet.changes.allSatisfy { $0.kind == .modify })
        #expect(changeSet.changes.map(\.newContent) == ["ALPHA\n", "BETA\n", "GAMMA\n"])
    }

    @Test func anUnresolvedEditRecordsNothing() async throws {
        let (context, root) = try Self.makeContext(seeding: [("code.txt", "one\ntwo\nthree\n")])

        try await Self.edit(
            path: TestSupport.path("code.txt", in: root),
            find: ["nothing like this line"],
            replace: ["replacement"],
            in: context
        )
        let changeSet = await context.changes.drain()

        #expect(changeSet.changes.isEmpty)
    }

    // MARK: The patch verb

    @Test func aMultiFilePatchProjectsOneChangePerTouchedFile() async throws {
        let (context, root) = try Self.makeContext(seeding: [
            ("update.txt", "one\ntwo\nthree\n"),
            ("delete.txt", "obsolete\n"),
            ("source.txt", "keep me\n"),
        ])
        let body = """
            *** Add File: \(TestSupport.path("added.txt", in: root))
            +added
            *** Update File: \(TestSupport.path("update.txt", in: root))
            *** Find:
            two
            *** Replace:
            TWO
            *** Delete File: \(TestSupport.path("delete.txt", in: root))
            *** Update File: \(TestSupport.path("source.txt", in: root))
            *** Move to: \(TestSupport.path("dest.txt", in: root))
            """

        try await Self.patch(body: body, in: context)
        let changes = await context.changes.drain().changes

        #expect(changes.count == Self.touchedFileCount)

        let added = try #require(Self.change(in: changes, endingWith: "added.txt"))
        #expect(added.kind == .add)
        #expect(added.path == TestSupport.path("added.txt", in: root))
        #expect(added.oldContent == nil)
        #expect(added.newContent == "added\n")

        let updated = try #require(Self.change(in: changes, endingWith: "update.txt"))
        #expect(updated.kind == .modify)
        #expect(updated.oldContent == "one\ntwo\nthree\n")
        #expect(updated.newContent == "one\nTWO\nthree\n")

        let deleted = try #require(Self.change(in: changes, endingWith: "delete.txt"))
        #expect(deleted.kind == .delete)
        #expect(deleted.oldContent == "obsolete\n")
        #expect(deleted.newContent == nil)

        let moved = try #require(Self.change(in: changes, endingWith: "source.txt"))
        #expect(moved.kind == .move)
        #expect(moved.destinationPath == TestSupport.path("dest.txt", in: root))
        #expect(moved.oldContent == "keep me\n")
        #expect(moved.newContent == "keep me\n")
    }

    @Test func aMoveOntoAnExistingDestinationAlsoRecordsItsDestructionAsADelete() async throws {
        let (context, root) = try Self.makeContext(seeding: [
            ("source.txt", "keep me\n"),
            ("dest.txt", "clobbered\n"),
        ])
        let body = """
            *** Update File: \(TestSupport.path("source.txt", in: root))
            *** Move to: \(TestSupport.path("dest.txt", in: root))
            """

        try await Self.patch(body: body, in: context)
        let changes = await context.changes.drain().changes

        // The rename itself is still one entry describing the source's own
        // before/after text — the destructive fact that the destination's
        // prior content is gone is a second, distinct entry, not a rewrite of
        // the rename's own diff.
        #expect(changes.map(\.kind) == [.move, .delete])

        let moved = try #require(Self.change(in: changes, endingWith: "source.txt"))
        #expect(moved.kind == .move)
        #expect(moved.destinationPath == TestSupport.path("dest.txt", in: root))
        #expect(moved.oldContent == "keep me\n")
        #expect(moved.newContent == "keep me\n")

        let destroyed = try #require(Self.change(in: changes, endingWith: "dest.txt"))
        #expect(destroyed.kind == .delete)
        #expect(destroyed.path == TestSupport.path("dest.txt", in: root))
        #expect(destroyed.destinationPath == nil)
        #expect(destroyed.oldContent == "clobbered\n")
        #expect(destroyed.newContent == nil)
    }

    @Test func aSwapRecordsOnlyTwoMovesWithNoSpuriousDestructionEntries() async throws {
        let (context, root) = try Self.makeContext(seeding: [
            ("alpha.txt", "alpha\n"),
            ("beta.txt", "beta\n"),
        ])
        let body = """
            *** Update File: \(TestSupport.path("alpha.txt", in: root))
            *** Move to: \(TestSupport.path("beta.txt", in: root))
            *** Update File: \(TestSupport.path("beta.txt", in: root))
            *** Move to: \(TestSupport.path("alpha.txt", in: root))
            """

        try await Self.patch(body: body, in: context)
        let changes = await context.changes.drain().changes

        // Each destination pre-exists — that is what makes it a swap — but
        // neither file's prior content is destroyed: the peer hunk relocates
        // it within this same atomic patch. Exactly two `.move` entries, no
        // fan-out `.delete` for either "clobbered" destination.
        #expect(changes.map(\.kind) == [.move, .move])
    }

    /// The engine-action-to-change-kind table names every engine action.
    ///
    /// The table replaced an exhaustive `switch`, whose compiler-checked
    /// totality this test stands in for: an action the table omits would
    /// silently be recorded under ``Patch``'s fallback kind rather than
    /// failing to compile, and no behavioral test would notice, since a new
    /// action can only be produced by engine behavior that does not exist yet.
    /// The kinds themselves are pinned by
    /// ``aMultiFilePatchProjectsOneChangePerTouchedFile()``.
    @Test func everyEngineActionHasAChangeKind() {
        #expect(PatchEngine.Action.allCases.allSatisfy { Patch.changeKinds[$0] != nil })
    }

    // MARK: Patch rendering end to end

    @Test func theChangeSetOfAnEditRendersTheEditAsAGitPatch() async throws {
        let (context, root) = try Self.makeContext(seeding: [("code.txt", "one\ntwo\nthree\n")])

        try await Self.edit(
            path: TestSupport.path("code.txt", in: root),
            find: ["two"],
            replace: ["TWO"],
            in: context
        )
        let patch = await context.changes.drain().patch

        #expect(
            patch == """
                diff --git a/code.txt b/code.txt
                --- a/code.txt
                +++ b/code.txt
                @@ -1,3 +1,3 @@
                 one
                -two
                +TWO
                 three

                """
        )
    }

    @Test func theChangeSetOfAMoveOntoAnExistingDestinationRendersTheDestructionAlongsideTheRename() async throws {
        let (context, root) = try Self.makeContext(seeding: [
            ("source.txt", "keep me\n"),
            ("dest.txt", "clobbered\n"),
        ])
        let body = """
            *** Update File: \(TestSupport.path("source.txt", in: root))
            *** Move to: \(TestSupport.path("dest.txt", in: root))
            """

        try await Self.patch(body: body, in: context)
        let patch = await context.changes.drain().patch

        // The rename headers are still there, but a client reading only the
        // rename section would never learn the destination's prior content is
        // gone — the second, `deleted file mode` section is what shows it.
        #expect(patch.contains("rename from source.txt"))
        #expect(patch.contains("rename to dest.txt"))
        #expect(patch.contains("deleted file mode 100644"))
        #expect(patch.contains("-clobbered"))
    }

    // MARK: Encoded results are untouched

    @Test func theEncodedWriteResultCarriesExactlyItsExistingFields() async throws {
        let (context, root) = try Self.makeContext()

        let output = try await Self.write(
            path: TestSupport.path("new.txt", in: root),
            content: "hello\n",
            in: context
        )

        // The `nil` `correction` is omitted from the encoding, exactly as
        // the sibling's `JSONEncoder` omitted its `nil` fields.
        #expect(
            try Self.encodedKeys(of: output) == [
                "bytesWritten", "hash", "path", "taggedContent",
            ]
        )
    }

    @Test func theEncodedEditResultCarriesExactlyItsExistingFields() async throws {
        let (context, root) = try Self.makeContext(seeding: [("code.txt", "one\ntwo\n")])

        let output = try await Self.edit(
            path: TestSupport.path("code.txt", in: root),
            find: ["two"],
            replace: ["TWO"],
            in: context
        )

        #expect(
            try Self.encodedKeys(of: output) == [
                "applied", "bytesWritten", "encoding", "hash", "lineEndings", "outcomes",
                "path", "status", "taggedContent",
            ]
        )
    }

    @Test func theEncodedPatchResultCarriesExactlyItsExistingFields() async throws {
        let (context, root) = try Self.makeContext(seeding: [("update.txt", "a\nb\n")])
        let body = """
            *** Update File: \(TestSupport.path("update.txt", in: root))
            *** Find:
            b
            *** Replace:
            B
            """

        let output = try await Self.patch(body: body, in: context)

        #expect(try Self.encodedKeys(of: output) == ["files", "status"])
    }

    @Test func recordingChangesLeavesTheEncodedResultsByteIdentical() async throws {
        let recording = try await Self.encodedMutationResults(recordsChanges: true)
        let notRecording = try await Self.encodedMutationResults(recordsChanges: false)

        #expect(recording == notRecording)
    }

    // MARK: The OperationEvent detail envelope

    @Test func encodedOperationEventDetailRoundTrips() throws {
        let set = Self.makeEnvelopeSet()

        let text = set.encodedOperationEventDetail()
        let decoded = try #require(FileChangeSet(operationEventDetail: text))

        #expect(try Self.jsonObject(text).keys.sorted() == [FileChangeSet.operationEventDetailKey])
        #expect(decoded == set)
        #expect(decoded.root == set.root)
        #expect(decoded.changes == set.changes)
    }

    @Test func operationEventDetailRejectsForeignText() {
        #expect(FileChangeSet(operationEventDetail: "starting the sweep") == nil)
        #expect(FileChangeSet(operationEventDetail: "{}") == nil)
        #expect(FileChangeSet(operationEventDetail: "{\"fileChanges\": 1}") == nil)
    }

    @Test func encodedOperationEventDetailCarriesThePatch() throws {
        let set = Self.makeEnvelopeSet()

        let envelope = try Self.jsonObject(set.encodedOperationEventDetail())
        let encodedSet = envelope[FileChangeSet.operationEventDetailKey] as? [String: Any] ?? [:]

        #expect(encodedSet["patch"] as? String == set.patch)

        // A decode reads `root` and `changes` and ignores `patch`: the patch is
        // rendered from the changes, never read back, thus a foreign patch text
        // changes nothing about the decoded set.
        var foreign = encodedSet
        foreign["patch"] = "not a patch"
        let foreignText = try JSONSerialization.data(
            withJSONObject: [FileChangeSet.operationEventDetailKey: foreign])
        let decoded = try #require(
            FileChangeSet(operationEventDetail: String(decoding: foreignText, as: UTF8.self)))
        #expect(decoded == set)
        #expect(decoded.patch == set.patch)
    }

    // MARK: Partially applied patches

    /// Apply a patch that adds one file and deletes an unlinkable one, returning what the session saw.
    ///
    /// The delete target is locked immutable, thus its unlink fails — and
    /// removals run only *after* every write has committed, thus the add
    /// landed on disk while the whole patch still returns a correction. That
    /// is the post-commit failure path where the change set must still report
    /// what changed.
    ///
    /// - Parameter recordsChanges: whether the session records a change set.
    /// - Returns: the correction, the recorded changes, and the session root.
    /// - Throws: rethrows an operation or seed failure.
    private static func partiallyAppliedPatch(recordsChanges: Bool) async throws -> (
        correction: String?, changes: [FileChange], root: URL
    ) {
        let (context, root) = try makeContext(
            recordsChanges: recordsChanges, seeding: [("doomed.txt", "obsolete\n")])
        let doomed = TestSupport.path("doomed.txt", in: root)
        #expect(TestSupport.setImmutable(doomed, to: true))
        defer { TestSupport.setImmutable(doomed, to: false) }

        let output = try await patch(
            body: """
                *** Add File: \(TestSupport.path("added.txt", in: root))
                +added
                *** Delete File: \(doomed)
                """,
            in: context
        )
        return (output.correction, await context.changes.drain().changes, root)
    }

    @Test func aPatchWhoseCommitFailsPartwayRecordsTheFilesThatLanded() async throws {
        let (context, root) = try Self.makeContext(seeding: [
            ("first.txt", "first\n"),
            ("locked.txt", "locked\n"),
        ])
        let locked = TestSupport.path("locked.txt", in: root)
        // A rename onto an immutable file fails, thus the second section's
        // commit fails after the first section's has already been renamed
        // into place.
        #expect(TestSupport.setImmutable(locked, to: true))
        defer { TestSupport.setImmutable(locked, to: false) }

        let output = try await Self.patch(
            body: """
                *** Update File: \(TestSupport.path("first.txt", in: root))
                *** Find:
                first
                *** Replace:
                FIRST
                *** Update File: \(locked)
                *** Find:
                locked
                *** Replace:
                LOCKED
                """,
            in: context
        )
        let changes = await context.changes.drain().changes

        #expect(
            output.correction
                == "The patch resolved but a file could not be committed: \(locked)")
        #expect(changes.count == 1)
        let landed = try #require(changes.first)
        #expect(landed.kind == .modify)
        #expect(landed.path == TestSupport.path("first.txt", in: root))
        #expect(landed.oldContent == "first\n")
        #expect(landed.newContent == "FIRST\n")
    }

    @Test func aPatchWhosePostCommitUnlinkFailsRecordsEveryCommittedWrite() async throws {
        let (correction, changes, root) = try await Self.partiallyAppliedPatch(recordsChanges: true)

        #expect(
            correction == "The patch's writes committed but a file could not be removed, "
                + "so it remains on disk: \(TestSupport.path("doomed.txt", in: root))")
        #expect(changes.count == 1)
        let landed = try #require(changes.first)
        #expect(landed.kind == .add)
        #expect(landed.path == TestSupport.path("added.txt", in: root))
        #expect(landed.oldContent == nil)
        #expect(landed.newContent == "added\n")
    }

    @Test func aStrandedMoveIsRecordedAsAnAddAtItsDestination() async throws {
        let (context, root) = try Self.makeContext(seeding: [("locked-source.txt", "payload\n")])
        let source = TestSupport.path("locked-source.txt", in: root)
        let destination = TestSupport.path("moved-dest.txt", in: root)
        // The destination write commits but the source cannot be unlinked,
        // thus the rename is half-done: the change set must describe the file
        // that actually appeared, not claim a rename that did not happen.
        #expect(TestSupport.setImmutable(source, to: true))
        defer { TestSupport.setImmutable(source, to: false) }

        let output = try await Self.patch(
            body: """
                *** Update File: \(source)
                *** Move to: \(destination)
                """,
            in: context
        )
        let changes = await context.changes.drain().changes

        #expect(output.correction != nil)
        #expect(changes.count == 1)
        let landed = try #require(changes.first)
        #expect(landed.kind == .add)
        #expect(landed.path == destination)
        #expect(landed.destinationPath == nil)
        #expect(landed.newContent == "payload\n")
    }

    @Test func aPartiallyAppliedPatchReturnsTheSameCorrectionWithoutRecording() async throws {
        let (correction, changes, root) = try await Self.partiallyAppliedPatch(recordsChanges: false)

        #expect(
            correction == "The patch's writes committed but a file could not be removed, "
                + "so it remains on disk: \(TestSupport.path("doomed.txt", in: root))")
        #expect(changes.isEmpty)
    }

    @Test func anUnresolvedPatchRecordsNothing() async throws {
        let (context, root) = try Self.makeContext(seeding: [("update.txt", "one\ntwo\nthree\n")])
        let body = """
            *** Update File: \(TestSupport.path("update.txt", in: root))
            *** Find:
            nothing like this line
            *** Replace:
            replacement
            """

        try await Self.patch(body: body, in: context)
        let changeSet = await context.changes.drain()

        #expect(changeSet.changes.isEmpty)
    }
}
