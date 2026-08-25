import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the ``FileContext`` session state and its
/// ``FileChangeJournal`` wiring.
///
/// This suite is a port of the sibling FileTool `FileContextTests`, without
/// the diagnostics cases — decision 2026-08-11 in eventplan.md keeps the
/// diagnostics seam out of this package. The two `FileContext` cases from the
/// sibling `PathGuardTests` live here as well, thus each context test stands
/// in one suite. The journal cases are new to this port: the sibling proves
/// the journal wiring through its mutating operations, which are not in this
/// package yet, thus these cases drive the journal directly.
@Suite struct FileContextTests {
    // MARK: Guard and read-only wiring

    /// A `FileContext` exposes its root, its guard, and its read-only flag,
    /// and the guard enforces the session root as the workspace boundary.
    @Test func exposesRootGuardAndReadOnlyFlag() {
        let root = TestSupport.makeTemporaryDirectory(named: "FileContextTests")
        let context = FileContext(root: root, readOnly: true)
        #expect(context.root == root)
        #expect(context.readOnly)
        #expect(context.pathGuard.workspaceRoot == root)
    }

    /// A `FileContext` permits the mutating verbs unless a caller opts out.
    @Test func defaultsToReadWrite() {
        let context = FileContext(root: TestSupport.makeTemporaryDirectory(named: "FileContextTests"))
        #expect(!context.readOnly)
    }

    /// A ``FileContext`` created with `additionalRoots` threads them through
    /// to its ``PathGuard``, thus a path in a secondary root validates
    /// alongside the primary session root.
    @Test func acceptsAdditionalRootsAndValidatesPathsWithinThem() throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FileContextTests")
        let secondary = TestSupport.makeTemporaryDirectory(named: "FileContextTests")
        let file = secondary.appendingPathComponent("vendored.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)

        let context = FileContext(root: root, additionalRoots: [secondary])
        #expect(context.pathGuard.additionalWorkspaceRoots == [secondary])
        let resolved = try context.pathGuard.validatePath(file.path).get()
        #expect(resolved.lastPathComponent == "vendored.txt")
    }

    // MARK: Journal wiring

    /// A default context wires a disabled journal, and a disabled journal
    /// drops every record, thus a session that never asked for recording
    /// drains an empty change set.
    @Test func defaultJournalIsDisabledAndDropsRecords() async {
        let root = TestSupport.makeTemporaryDirectory(named: "FileContextTests")
        let context = FileContext(root: root)
        #expect(!context.changes.isRecording)

        await context.changes.record(FileChange(kind: .add, path: "/tmp/new.txt", newContent: "hello\n"))
        let drained = await context.changes.drain()
        #expect(drained.changes.isEmpty)
    }

    /// A context created with `recordsChanges` wires a recording journal
    /// whose root is the canonicalized session root, thus the drained
    /// change set and the paths the operations report spell the root the
    /// same way.
    @Test func recordsChangesWiresARecordingJournalWithACanonicalRoot() {
        let root = TestSupport.makeTemporaryDirectory(named: "FileContextTests")
        let context = FileContext(root: root, recordsChanges: true)
        #expect(context.changes.isRecording)
        #expect(context.changes.root == TestSupport.canonicalDirectory(root))
    }

    /// A recording journal drains the recorded changes in the order they
    /// were made, and the drain clears it, thus a second drain is empty.
    @Test func recordingJournalDrainsRecordedChangesInOrderThenClears() async {
        let root = TestSupport.makeTemporaryDirectory(named: "FileContextTests")
        let journal = FileChangeJournal(root: root, mode: .recording)
        let first = FileChange(kind: .add, path: "/tmp/first.txt", newContent: "one\n")
        let second = FileChange(kind: .delete, path: "/tmp/second.txt", oldContent: "two\n")

        await journal.record(first)
        await journal.record(second)
        let drained = await journal.drain()
        #expect(drained.changes == [first, second])
        #expect(drained.root == TestSupport.canonicalDirectory(root))

        let secondDrain = await journal.drain()
        #expect(secondDrain.changes.isEmpty)
    }
}
