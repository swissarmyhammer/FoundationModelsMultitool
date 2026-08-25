// `FilesPatchTests` — the behavioral suite of the `tools.files.patch` verb.
//
// A port of `../FoundationModelsFileTool/Tests/FileToolTests/
// PatchFilesTests.swift`, adapted to the `Tool` call shape: the sibling
// decoded a `PatchFiles` operation out of `GeneratedContent`; here the suite
// constructs `PatchArguments` with the memberwise initializer and calls the
// `Patch` verb directly, the way `FilesEditTests` calls its verb. The
// sibling's fused-tool dispatch and op-inference tests do not port: this
// package has no `FileTool`, thus there is no op dispatch to exercise. The
// sibling's `PatchOutput` accessors do not port either: the flat result
// carries a `correction` field, and the suite reads it directly. The
// sibling's per-file results were typed values; here each one is one JSON
// string (sorted keys), thus the assertions read the JSON text.
//
// Four tests are not in the sibling: the outside-the-root correction, the
// read-only-context correction, and the add-onto-existing correction, which
// the card's acceptance criteria name, and three journal tests — a recorded
// multi-file patch, a disabled journal, and an unresolved patch that records
// nothing — which the card's shape section names.

import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the `tools.files.patch` verb.
///
/// The verb is exercised end-to-end: a multi-file add/update/delete/move
/// envelope applied in one call; a malformed envelope returning a correction
/// naming the offending line while leaving the filesystem untouched; a hunk
/// that cannot apply (an Add onto an existing file) returning the engine's
/// corrective description; an unresolved update pair returning a structured
/// `nearMiss`/`ambiguous` result carrying the failing file's path and the
/// same candidates/near-miss diffs the `edit` verb produces (all files
/// byte-identical); the encoded per-file field names; and the description
/// pinning the envelope syntax it must carry. From this card's own criteria:
/// the outside-the-root correction, the read-only-context correction, and
/// the journal recording.
@Suite struct FilesPatchTests {
    // MARK: Test scaffolding

    /// The number of files the multi-file envelope touches: one add, one
    /// update, one delete, and one move.
    private static let touchedFileCount = 4

    /// The 1-based selector of the second candidate occurrence.
    private static let secondOccurrence = 2

    /// Call the `tools.files.patch` verb over a session context.
    ///
    /// - Parameters:
    ///   - envelope: the whole patch envelope.
    ///   - context: the session context the verb applies against.
    /// - Returns: the verb's flat result.
    private static func patch(_ envelope: String, in context: FileContext) async throws -> PatchResult {
        try await Patch(context: context).call(arguments: PatchArguments(patch: envelope))
    }

    /// Wrap a section body in the envelope markers.
    ///
    /// - Parameter body: the file-section text between the markers.
    /// - Returns: the complete `*** Begin Patch` … `*** End Patch` envelope.
    private static func envelope(_ body: String) -> String {
        "*** Begin Patch\n\(body)\n*** End Patch\n"
    }

    /// Seed files with UTF-8 contents inside a fresh temporary directory.
    ///
    /// - Parameters:
    ///   - files: the file names and UTF-8 contents to seed.
    ///   - recordsChanges: whether the context records changes.
    /// - Returns: the session ``FileContext`` and the temporary root URL.
    private static func makeContext(
        seeding files: [(name: String, contents: String)] = [],
        recordsChanges: Bool = false
    ) throws -> (context: FileContext, root: URL) {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesPatchTests")
        for file in files {
            try Data(file.contents.utf8).write(to: root.appendingPathComponent(file.name, isDirectory: false))
        }
        return (FileContext(root: root, recordsChanges: recordsChanges), root)
    }

    /// The raw on-disk bytes of a file, or `nil` when it does not exist.
    ///
    /// - Parameter path: the absolute path to read.
    /// - Returns: the file's bytes, or `nil`.
    private static func bytes(_ path: String) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// Read a committed file back through the `read` verb.
    ///
    /// - Parameters:
    ///   - path: the absolute path to read.
    ///   - context: the session context the verb reads against.
    /// - Returns: the read verb's flat result.
    private static func readBack(path: String, in context: FileContext) async throws -> ReadResult {
        try await Read(context: context)
            .call(arguments: ReadArguments(path: path, offset: nil, limit: nil, format: nil))
    }

    /// The per-file JSON result whose text contains `fragment`.
    ///
    /// - Parameters:
    ///   - files: the per-file JSON results to search.
    ///   - fragment: the text identifying the wanted result.
    /// - Returns: the first matching JSON text, or `nil` when none matches.
    private static func file(in files: [String], containing fragment: String) -> String? {
        files.first { $0.contains(fragment) }
    }

    // MARK: Multi-file apply

    /// One envelope adds, updates, deletes, and moves in one call, and the
    /// result reports every touched file.
    @Test func multiFilePatchAppliesAndReportsEveryTouchedFile() async throws {
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
        let result = try await Self.patch(Self.envelope(body), in: context)

        #expect(result.correction == nil)
        #expect(result.status == "applied")
        #expect(result.files.count == Self.touchedFileCount)
        #expect(result.path == nil)
        #expect(result.outcome == nil)

        let addedBytes = Data("added\n".utf8)
        let add = try #require(Self.file(in: result.files, containing: "added.txt"))
        #expect(add.contains("\"action\":\"added\""))
        #expect(add.contains("\"applied\":0"))
        #expect(add.contains("\"bytesWritten\":\(addedBytes.count)"))
        #expect(add.contains("\"hash\":\"\(Hashline.wholeFileHash(bytes: addedBytes))\""))
        let addedRead = try await Self.readBack(path: TestSupport.path("added.txt", in: root), in: context)
        #expect(addedRead.lines == Hashline.taggedLines(of: "added\n"))

        let update = try #require(Self.file(in: result.files, containing: "update.txt"))
        #expect(update.contains("\"action\":\"modified\""))
        #expect(update.contains("\"applied\":1"))
        let updatedRead = try await Self.readBack(path: TestSupport.path("update.txt", in: root), in: context)
        #expect(updatedRead.lines == Hashline.taggedLines(of: "one\nTWO\nthree\n"))

        let delete = try #require(Self.file(in: result.files, containing: "delete.txt"))
        #expect(delete.contains("\"action\":\"deleted\""))
        #expect(!delete.contains("\"bytesWritten\""), "a delete commits no bytes")
        #expect(!delete.contains("\"hash\""), "a delete has no freshness token")
        #expect(Self.bytes(TestSupport.path("delete.txt", in: root)) == nil)

        let move = try #require(Self.file(in: result.files, containing: "source.txt"))
        #expect(move.contains("\"action\":\"moved\""))
        // The destination is the guard-resolved absolute path (the `/var` →
        // `/private/var` canonicalization again), thus match the key and the
        // name rather than the raw seed path.
        #expect(move.contains("\"movedTo\":\""))
        #expect(move.contains("dest.txt\""))
        let movedRead = try await Self.readBack(path: TestSupport.path("dest.txt", in: root), in: context)
        #expect(movedRead.lines == Hashline.taggedLines(of: "keep me\n"))
        #expect(Self.bytes(TestSupport.path("source.txt", in: root)) == nil)
    }

    // MARK: Malformed envelope

    /// A patch that cannot parse comes back as a correction that names the
    /// offending line, and no file changes.
    @Test func malformedEnvelopeIsCorrectiveNamingTheLineAndLeavesFilesUntouched() async throws {
        let (context, root) = try Self.makeContext(seeding: [("keep.txt", "unchanged\n")])
        // A `*** Begin Patch` with no `*** End Patch`.
        let malformed = "*** Begin Patch\n*** Add File: \(TestSupport.path("nope.txt", in: root))\n+x\n"
        let result = try await Self.patch(malformed, in: context)
        let message = try #require(result.correction)

        #expect(message.contains("line"))
        #expect(result.status.isEmpty)
        #expect(result.files.isEmpty)
        #expect(Self.bytes(TestSupport.path("keep.txt", in: root)) == Data("unchanged\n".utf8))
        #expect(Self.bytes(TestSupport.path("nope.txt", in: root)) == nil)
    }

    // MARK: A hunk that cannot apply

    /// An Add onto an existing file comes back as the engine's corrective
    /// description, and the file stays byte-identical.
    @Test func addOntoAnExistingFileIsCorrectiveAndLeavesItByteIdentical() async throws {
        let original = "already here\n"
        let (context, root) = try Self.makeContext(seeding: [("existing.txt", original)])
        let body = "*** Add File: \(TestSupport.path("existing.txt", in: root))\n+overwrite"
        let result = try await Self.patch(Self.envelope(body), in: context)
        let message = try #require(result.correction)

        #expect(message.contains("already exists"))
        #expect(Self.bytes(TestSupport.path("existing.txt", in: root)) == Data(original.utf8))
    }

    // MARK: Unresolved update pair (structured, byte-identical)

    /// A near-miss update reports the failing file's path and a line diff,
    /// and commits nothing.
    @Test func nearMissUpdateReportsPathAndDiffAndCommitsNothing() async throws {
        let original = "the quick brown fox\n"
        let (context, root) = try Self.makeContext(seeding: [("prose.txt", original)])
        let target = TestSupport.path("prose.txt", in: root)
        let body = """
            *** Update File: \(target)
            *** Find:
            the quick red fox
            *** Replace:
            X
            """
        let result = try await Self.patch(Self.envelope(body), in: context)

        #expect(result.correction == nil)
        #expect(result.status == "nearMiss")
        // The failing file's path is the guard-resolved absolute path
        // (existing files canonicalize the `/var` → `/private/var` symlink,
        // exactly as the `edit` verb reports it), thus match by suffix
        // rather than by the raw seed path.
        #expect(result.path?.hasSuffix("prose.txt") == true)
        #expect(result.files.isEmpty)
        let outcome = try #require(result.outcome)
        #expect(outcome.contains("{\"change\":\"expected\",\"text\":\"the quick red fox\"}"))
        #expect(outcome.contains("{\"change\":\"actual\",\"text\":\"the quick brown fox\"}"))
        #expect(Self.bytes(target) == Data(original.utf8), "an unresolved patch must leave every file byte-identical")
    }

    /// An ambiguous update reports its candidate sites and commits nothing.
    @Test func ambiguousUpdateReportsCandidatesAndCommitsNothing() async throws {
        let original = "x\nx\n"
        let (context, root) = try Self.makeContext(seeding: [("dup.txt", original)])
        let target = TestSupport.path("dup.txt", in: root)
        let body = """
            *** Update File: \(target)
            *** Find:
            x
            *** Replace:
            y
            """
        let result = try await Self.patch(Self.envelope(body), in: context)

        #expect(result.status == "ambiguous")
        let outcome = try #require(result.outcome)
        #expect(outcome.contains("\"matchedBy\":\"ambiguous\""))
        #expect(outcome.contains("\"occurrence\":1"))
        #expect(outcome.contains("\"occurrence\":\(Self.secondOccurrence)"))
        #expect(Self.bytes(target) == Data(original.utf8))
    }

    // MARK: Corrective paths of this card

    /// A path outside the session root comes back as a correction and the
    /// outside location stays untouched: the patch stays bounded through the
    /// session's path guard.
    @Test func pathOutsideTheRootIsCorrective() async throws {
        let (context, _) = try Self.makeContext()
        let outside = TestSupport.makeTemporaryDirectory(named: "FilesPatchTestsOutside")
        let target = TestSupport.path("escape.txt", in: outside)
        let body = "*** Add File: \(target)\n+nope"
        let result = try await Self.patch(Self.envelope(body), in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
        #expect(Self.bytes(target) == nil, "a rejected patch must not write outside the root")
    }

    /// A patch on a read-only context comes back as a correction and no file
    /// is written: the context flag forbids the mutating verbs up front.
    @Test func readOnlyContextIsCorrectiveAndWritesNothing() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesPatchTests")
        let context = FileContext(root: root, readOnly: true)
        let target = TestSupport.path("blocked.txt", in: root)
        let body = "*** Add File: \(target)\n+nope"
        let result = try await Self.patch(Self.envelope(body), in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
        #expect(result.status.isEmpty)
        #expect(Self.bytes(target) == nil, "a read-only context must not write the file")
    }

    // MARK: Encoded per-file field names

    /// The per-file JSON results carry the expected field names.
    @Test func encodedFileResultsCarryTheExpectedFieldNames() async throws {
        let (context, root) = try Self.makeContext(seeding: [("src.txt", "hi\n")])
        let body = """
            *** Add File: \(TestSupport.path("made.txt", in: root))
            +made
            *** Update File: \(TestSupport.path("src.txt", in: root))
            *** Move to: \(TestSupport.path("moved.txt", in: root))
            """
        let result = try await Self.patch(Self.envelope(body), in: context)

        #expect(result.status == "applied")
        for json in result.files {
            #expect(json.contains("\"path\""))
            #expect(json.contains("\"action\""))
            #expect(json.contains("\"applied\""))
            #expect(json.contains("\"bytesWritten\""))
            #expect(json.contains("\"hash\""))
        }
        let move = try #require(Self.file(in: result.files, containing: "src.txt"))
        #expect(move.contains("\"movedTo\""))
    }

    // MARK: Format-teaching description

    /// The verb's description documents the whole envelope syntax.
    @Test func descriptionTeachesTheEnvelopeSyntax() throws {
        let (context, _) = try Self.makeContext()
        let description = Patch(context: context).description
        for marker in [
            "*** Begin Patch",
            "*** Add File:",
            "*** Update File:",
            "*** Delete File:",
            "*** Move to:",
            "*** Find:",
            "*** Replace:",
            "*** End Patch",
        ] {
            #expect(description.contains(marker), "the description must document `\(marker)`")
        }
    }

    // MARK: Change recording

    /// An applied multi-file patch on a recording context records one change
    /// for each touched file, with the change-set kinds.
    @Test func aRecordingContextRecordsEveryCommittedChange() async throws {
        let (context, root) = try Self.makeContext(
            seeding: [
                ("update.txt", "one\ntwo\nthree\n"),
                ("delete.txt", "obsolete\n"),
                ("source.txt", "keep me\n"),
            ],
            recordsChanges: true
        )
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
        let result = try await Self.patch(Self.envelope(body), in: context)
        #expect(result.correction == nil)

        let changes = await context.changes.drain().changes
        #expect(changes.count == Self.touchedFileCount)
        #expect(Set(changes.map(\.kind)) == [.add, .modify, .delete, .move])

        let modify = try #require(changes.first { $0.kind == .modify })
        #expect(modify.oldContent == "one\ntwo\nthree\n")
        #expect(modify.newContent == "one\nTWO\nthree\n")

        let move = try #require(changes.first { $0.kind == .move })
        #expect(move.destinationPath?.hasSuffix("dest.txt") == true)
    }

    /// A patch on a non-recording context records nothing: the journal is
    /// disabled.
    @Test func aDisabledJournalRecordsNothing() async throws {
        let (context, root) = try Self.makeContext()
        let body = "*** Add File: \(TestSupport.path("quiet.txt", in: root))\n+quiet"
        let result = try await Self.patch(Self.envelope(body), in: context)
        #expect(result.correction == nil)

        let changes = await context.changes.drain().changes
        #expect(changes.isEmpty)
    }

    /// An unresolved patch commits nothing and records nothing, on a
    /// recording context.
    @Test func anUnresolvedPatchRecordsNothing() async throws {
        let (context, root) = try Self.makeContext(
            seeding: [("dup.txt", "x\nx\n")], recordsChanges: true)
        let body = """
            *** Update File: \(TestSupport.path("dup.txt", in: root))
            *** Find:
            x
            *** Replace:
            y
            """
        let result = try await Self.patch(Self.envelope(body), in: context)
        #expect(result.status == "ambiguous")

        let changes = await context.changes.drain().changes
        #expect(changes.isEmpty, "an unresolved patch must record no change")
    }
}
