// `SnapshotsCapabilityTests` — the behavioral suite of the `tools.snapshots`
// verbs (task `^5wcd6b3`).
//
// Each test makes its own temporary git repository and its own
// `SnapshotStore` in a temporary folder outside the repository. The test opens
// the session key on the store, as `SnapshotHook` does on `SessionStart`, and
// then calls each verb under `HookSession.$current.withValue`, as Router does
// for each model call. Thus the tests are independent and they run in
// parallel safely.

import Foundation
import FoundationModelsHooks
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `tools.snapshots` verbs: `list`, `take`, `undo`
/// and `redo`.
@Suite("SnapshotsCapabilityTests", .ownsTemporaryDirectories)
struct SnapshotsCapabilityTests {

    /// The name of each temporary folder of a test. Thus a leaked folder is
    /// traceable to this suite.
    private static let testDirectoryName = "SnapshotsCapabilityTests"

    /// The session key of the first session of a test.
    private static let firstKey = "lineage-one"

    /// The session key of the second session of a test.
    private static let secondKey = "lineage-two"

    /// The path of each verb of the capability, in render order.
    private static let snapshotPaths = ["list", "take", "undo", "redo"].map { "snapshots.\($0)" }

    /// The plain-language goal of the discovery search.
    private static let discoveryTask = "undo the last change to the work tree"

    // MARK: - Helpers

    /// One open session key over one temporary repository.
    private struct Fixture {

        /// The repository whose work tree the store records.
        let repository: TemporaryGitRepository

        /// The store that the capability and the test share.
        let store: SnapshotStore

        /// The session that a test binds for each call.
        let session: HookSession

        /// The verbs over the store.
        let context: SnapshotsContext
    }

    /// Makes a repository, a store, and a session key open on the store.
    ///
    /// - Parameter key: The session key to open.
    /// - Returns: The fixture.
    /// - Throws: What the repository or the store throws.
    private static func makeFixture(key: String = firstKey) async throws -> Fixture {
        let repository = try TemporaryGitRepository()
        try repository.write("base\n", to: "base.txt")
        try repository.commit(message: "base")
        let store = SnapshotStore(directory: TestSupport.makeTemporaryDirectory(named: testDirectoryName))
        let session = makeSession(key: key, workingDirectory: repository.workDirectory)
        try await store.open(sessionKey: key, owner: session.sessionID, workingDirectory: repository.workDirectory)
        return Fixture(repository: repository, store: store, session: session, context: SnapshotsContext(store: store))
    }

    /// Makes a session with `key` in `workingDirectory`.
    ///
    /// - Parameters:
    ///   - key: The session key.
    ///   - workingDirectory: The working directory of the session.
    /// - Returns: The session.
    private static func makeSession(key: String, workingDirectory: URL) -> HookSession {
        HookSession(
            sessionID: "session-\(key)", sessionKey: key, parentSessionID: nil,
            workingDirectory: workingDirectory,
            dataDirectory: TestSupport.makeTemporaryDirectory(named: testDirectoryName))
    }

    /// Reads the text of the file at `path` in the work tree of `repository`.
    ///
    /// - Parameters:
    ///   - path: The path, relative to the work tree.
    ///   - repository: The repository.
    /// - Returns: The text, or `nil` when the file is missing.
    private static func contents(of path: String, in repository: TemporaryGitRepository) -> String? {
        try? String(contentsOf: repository.workDirectory.appendingPathComponent(path), encoding: .utf8)
    }

    /// The correction that each verb gives when no snapshot is available.
    private static var unavailableCorrection: String {
        SnapshotError.unavailable.correctiveMessage
    }

    // MARK: - list

    /// `list` gives each checkpoint of the session key, oldest first, with its
    /// trigger and its files.
    @Test("list over a store with two checkpoints gives both, oldest first")
    func listGivesBothCheckpointsOldestFirst() async throws {
        let fixture = try await Self.makeFixture()
        try fixture.repository.write("one\n", to: "one.txt")
        _ = try await fixture.store.take(
            sessionKey: Self.firstKey, trigger: .toolUse(toolCallID: "call-1", toolName: "write"))
        try fixture.repository.write("two\n", to: "two.txt")
        _ = try await fixture.store.take(sessionKey: Self.firstKey, trigger: .manual(label: "second"))

        let result = try await HookSession.$current.withValue(fixture.session) {
            try await ListSnapshots(context: fixture.context).call(arguments: ListSnapshotsArguments())
        }

        #expect(result.correction == nil)
        #expect(result.checkpoints.map(\.index) == [1, 2])
        #expect(result.checkpoints.map(\.trigger) == ["tool write (call call-1)", "label second"])
        #expect(result.checkpoints.map(\.files) == [["one.txt"], ["two.txt"]])
        #expect(result.checkpoints.allSatisfy { !$0.date.isEmpty })
    }

    /// `list` says that a redo is available after an undo, and that no redo
    /// is available before an undo and after the redo.
    @Test("list says a redo is available after an undo, and not before an undo or after a redo")
    func listSaysIfARedoIsAvailable() async throws {
        let fixture = try await Self.makeFixture()
        try fixture.repository.write("changed\n", to: "base.txt")
        _ = try await fixture.store.take(sessionKey: Self.firstKey, trigger: .manual(label: nil))
        let list = ListSnapshots(context: fixture.context)

        let (beforeUndo, afterUndo, afterRedo) = try await HookSession.$current.withValue(fixture.session) {
            let beforeUndo = try await list.call(arguments: ListSnapshotsArguments())
            _ = try await UndoSnapshot(context: fixture.context).call(arguments: UndoSnapshotArguments())
            let afterUndo = try await list.call(arguments: ListSnapshotsArguments())
            _ = try await RedoSnapshot(context: fixture.context).call(arguments: RedoSnapshotArguments())
            let afterRedo = try await list.call(arguments: ListSnapshotsArguments())
            return (beforeUndo, afterUndo, afterRedo)
        }

        #expect(beforeUndo.correction == nil)
        #expect(!beforeUndo.isRedoAvailable)
        #expect(afterUndo.correction == nil)
        #expect(afterUndo.isRedoAvailable)
        #expect(afterUndo.checkpoints.isEmpty)
        #expect(afterRedo.correction == nil)
        #expect(!afterRedo.isRedoAvailable)
        #expect(afterRedo.checkpoints.map(\.index) == [1])
    }

    /// A `list` with no bound session says that no redo is available.
    @Test("list with no bound session says no redo is available")
    func listWithNoBoundSessionSaysNoRedo() async throws {
        let fixture = try await Self.makeFixture()

        let result = try await ListSnapshots(context: fixture.context).call(arguments: ListSnapshotsArguments())

        #expect(result.correction == Self.unavailableCorrection)
        #expect(!result.isRedoAvailable)
    }

    // MARK: - take

    /// `take` with a label after a file write gives a new checkpoint that
    /// carries the label and the written file.
    @Test("take with a label after a file write gives a checkpoint with that label")
    func takeWithALabelGivesACheckpointWithThatLabel() async throws {
        let fixture = try await Self.makeFixture()
        try fixture.repository.write("changed\n", to: "base.txt")

        let result = try await HookSession.$current.withValue(fixture.session) {
            try await TakeSnapshot(context: fixture.context).call(
                arguments: TakeSnapshotArguments(label: "before refactor"))
        }

        #expect(result.correction == nil)
        #expect(!result.isUnchanged)
        let checkpoint = try #require(result.checkpoint)
        #expect(checkpoint.index == 1)
        #expect(checkpoint.trigger == "label before refactor")
        #expect(checkpoint.files == ["base.txt"])
    }

    /// `take` when no file changed after the last snapshot makes no
    /// checkpoint, and says so.
    @Test("take with no change gives no checkpoint and says no change")
    func takeWithNoChangeGivesNoCheckpoint() async throws {
        let fixture = try await Self.makeFixture()

        let result = try await HookSession.$current.withValue(fixture.session) {
            try await TakeSnapshot(context: fixture.context).call(arguments: TakeSnapshotArguments(label: nil))
        }

        #expect(result.correction == nil)
        #expect(result.isUnchanged)
        #expect(result.checkpoint == nil)
    }

    // MARK: - undo and redo

    /// `undo` restores the work tree before the last checkpoint and gives the
    /// restored files. `redo` then gives the work tree before the undo back.
    @Test("undo then redo gives the work tree before the undo")
    func undoThenRedoGivesTheWorkTreeBeforeTheUndo() async throws {
        let fixture = try await Self.makeFixture()
        try fixture.repository.write("changed\n", to: "base.txt")
        _ = try await fixture.store.take(sessionKey: Self.firstKey, trigger: .manual(label: nil))

        let undone = try await HookSession.$current.withValue(fixture.session) {
            try await UndoSnapshot(context: fixture.context).call(arguments: UndoSnapshotArguments())
        }

        #expect(undone.correction == nil)
        #expect(undone.checkpoint?.files == ["base.txt"])
        #expect(Self.contents(of: "base.txt", in: fixture.repository) == "base\n")

        let redone = try await HookSession.$current.withValue(fixture.session) {
            try await RedoSnapshot(context: fixture.context).call(arguments: RedoSnapshotArguments())
        }

        #expect(redone.correction == nil)
        #expect(redone.checkpoint?.files == ["base.txt"])
        #expect(Self.contents(of: "base.txt", in: fixture.repository) == "changed\n")
    }

    /// `undo` with no checkpoint gives the correction of
    /// `SnapshotError.nothingToUndo`, and does not throw.
    @Test("undo with nothing to undo gives the corrective result")
    func undoWithNothingToUndoGivesTheCorrectiveResult() async throws {
        let fixture = try await Self.makeFixture()

        let result = try await HookSession.$current.withValue(fixture.session) {
            try await UndoSnapshot(context: fixture.context).call(arguments: UndoSnapshotArguments())
        }

        #expect(result.correction == SnapshotError.nothingToUndo.correctiveMessage)
        #expect(result.checkpoint == nil)
    }

    /// `redo` with no undone checkpoint gives the correction of
    /// `SnapshotError.nothingToRedo`, and does not throw.
    @Test("redo with nothing to redo gives the corrective result")
    func redoWithNothingToRedoGivesTheCorrectiveResult() async throws {
        let fixture = try await Self.makeFixture()

        let result = try await HookSession.$current.withValue(fixture.session) {
            try await RedoSnapshot(context: fixture.context).call(arguments: RedoSnapshotArguments())
        }

        #expect(result.correction == SnapshotError.nothingToRedo.correctiveMessage)
        #expect(result.checkpoint == nil)
    }

    // MARK: - Unavailable

    /// Each verb gives the `unavailable` correction when no session is bound.
    @Test("each verb with no bound session gives the unavailable corrective result")
    func eachVerbWithNoBoundSessionGivesUnavailable() async throws {
        let fixture = try await Self.makeFixture()

        let list = try await ListSnapshots(context: fixture.context).call(arguments: ListSnapshotsArguments())
        let take = try await TakeSnapshot(context: fixture.context).call(arguments: TakeSnapshotArguments(label: nil))
        let undo = try await UndoSnapshot(context: fixture.context).call(arguments: UndoSnapshotArguments())
        let redo = try await RedoSnapshot(context: fixture.context).call(arguments: RedoSnapshotArguments())

        #expect(list.correction == Self.unavailableCorrection)
        #expect(take.correction == Self.unavailableCorrection)
        #expect(undo.correction == Self.unavailableCorrection)
        #expect(redo.correction == Self.unavailableCorrection)
    }

    /// A session key whose working directory is not in a git work tree has no
    /// snapshots, thus each verb gives the `unavailable` correction.
    @Test("a session that is not in a git work tree gives the unavailable corrective result")
    func aSessionOutsideAGitWorkTreeGivesUnavailable() async throws {
        let folder = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let store = SnapshotStore(directory: TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName))
        let session = Self.makeSession(key: Self.firstKey, workingDirectory: folder)
        try await store.open(sessionKey: Self.firstKey, owner: session.sessionID, workingDirectory: folder)
        let context = SnapshotsContext(store: store)

        let result = try await HookSession.$current.withValue(session) {
            try await TakeSnapshot(context: context).call(arguments: TakeSnapshotArguments(label: nil))
        }

        #expect(result.correction == Self.unavailableCorrection)
        #expect(result.checkpoint == nil)
    }

    // MARK: - Session key at call time

    /// One capability value acts on the store state of the key that the bound
    /// session names at call time, and not on a key fixed at build time.
    @Test("one capability value acts on the state of the key of each bound session")
    func oneCapabilityActsOnTheKeyOfEachBoundSession() async throws {
        let first = try await Self.makeFixture(key: Self.firstKey)
        let secondRepository = try TemporaryGitRepository()
        try secondRepository.write("other\n", to: "other.txt")
        try secondRepository.commit(message: "other")
        let secondSession = Self.makeSession(key: Self.secondKey, workingDirectory: secondRepository.workDirectory)
        try await first.store.open(
            sessionKey: Self.secondKey, owner: secondSession.sessionID,
            workingDirectory: secondRepository.workDirectory)
        let take = TakeSnapshot(context: first.context)
        let list = ListSnapshots(context: first.context)

        try first.repository.write("first change\n", to: "base.txt")
        try secondRepository.write("second change\n", to: "other.txt")
        _ = try await HookSession.$current.withValue(first.session) {
            try await take.call(arguments: TakeSnapshotArguments(label: "first"))
        }
        _ = try await HookSession.$current.withValue(secondSession) {
            try await take.call(arguments: TakeSnapshotArguments(label: "second"))
        }
        let firstList = try await HookSession.$current.withValue(first.session) {
            try await list.call(arguments: ListSnapshotsArguments())
        }
        let secondList = try await HookSession.$current.withValue(secondSession) {
            try await list.call(arguments: ListSnapshotsArguments())
        }

        #expect(firstList.checkpoints.map(\.trigger) == ["label first"])
        #expect(firstList.checkpoints.map(\.files) == [["base.txt"]])
        #expect(secondList.checkpoints.map(\.trigger) == ["label second"])
        #expect(secondList.checkpoints.map(\.files) == [["other.txt"]])
    }

    /// A `tools.snapshots` call inside a `runCode` snippet sees the session
    /// that the `runCode` call was bound to, although the interpreter runs
    /// each job of the snippet on its own queue.
    @Test("a snippet call of tools.snapshots sees the session of the runCode call")
    func aSnippetCallSeesTheSessionOfTheRunCodeCall() async throws {
        let fixture = try await Self.makeFixture()
        try fixture.repository.write("changed\n", to: "base.txt")
        let multiTool = MultiTool(
            registry: try MultiTool.Builder().withCapability(SnapshotsCapability(store: fixture.store))
                .buildRegistry())

        let output = try await HookSession.$current.withValue(fixture.session) {
            try await multiTool.call(
                arguments: RunCodeArguments(
                    code: "return await tools.snapshots.take({ label: 'from snippet' });"))
        }

        let result = try RunOutput.decoded(SnippetTakeResult.self, from: output)
        #expect(result.correction == nil)
        #expect(result.checkpoint?.trigger == "label from snippet")
    }

    /// The fields of a `take` result that a snippet returns, as JSON.
    private struct SnippetTakeResult: Decodable {

        /// The checkpoint of the result.
        struct Checkpoint: Decodable {

            /// The trigger of the checkpoint.
            let trigger: String
        }

        /// The new checkpoint, or `nil`.
        let checkpoint: Checkpoint?

        /// The correction, or `nil`.
        let correction: String?
    }

    // MARK: - Discovery

    /// `searchTools` finds each of the four verbs of the capability.
    @Test("searchTools finds the four snapshots verbs")
    func searchToolsFindsTheFourSnapshotsVerbs() async throws {
        let fixture = try await Self.makeFixture()
        let surface = try MultiTool.Builder().withCapability(SnapshotsCapability(store: fixture.store)).build()

        let feedback = try await CapabilityDiscoveryProbe.searchToolsFeedback(
            over: surface, selecting: Self.snapshotPaths, task: Self.discoveryTask)

        #expect(surface.entries.map(\.path) == Self.snapshotPaths)
        for path in Self.snapshotPaths {
            let entry = try #require(surface.entries.first { $0.path == path })
            #expect(feedback.contains(entry.block), "feedback was: \(feedback)")
        }
    }
}
