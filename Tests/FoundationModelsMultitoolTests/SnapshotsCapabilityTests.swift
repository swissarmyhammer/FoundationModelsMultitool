// `SnapshotsCapabilityTests` — the behavioral suite of the `tools.snapshots`
// verbs (tasks `^5wcd6b3` and `^f4d43vr`).
//
// Each test makes its own temporary git repository and its own
// `SnapshotStore` in a temporary folder outside the repository. The test opens
// the session key on the store, as `SnapshotHook` does on `SessionStart`, and
// then calls each verb under `HookSession.$current.withValue`, as Router does
// for each model call. Thus the tests are independent and they run in
// parallel safely. No test reads a clock or waits for time to pass.

import Foundation
import FoundationModels
import FoundationModelsHooks
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `tools.snapshots` verbs: `list`, `take` and
/// `rollback`.
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
    private static let snapshotPaths = ["list", "take", "rollback"].map { "snapshots.\($0)" }

    /// The path of the rollback verb.
    private static let rollbackPath = "snapshots.rollback"

    /// The plain-language goal of the discovery search.
    private static let discoveryTask = "roll back the work tree to an earlier checkpoint"

    /// The tool name of the `runCode` trigger that `SnapshotHook` records on
    /// `PostToolUse`.
    private static let runCodeToolName = "runCode"

    /// The file that the first of three checkpoints adds.
    private static let firstFile = "first.txt"

    /// The file that the second of three checkpoints adds.
    private static let secondFile = "second.txt"

    /// The file that the third of three checkpoints adds.
    private static let thirdFile = "third.txt"

    /// The file that the base commit holds.
    private static let baseFile = "base.txt"

    /// The text of ``baseFile`` in the base commit.
    private static let baseText = "base\n"

    /// The text of ``baseFile`` after the second of three checkpoints.
    private static let changedBaseText = "changed by two\n"

    /// The file that a snippet or a test writes after the three checkpoints.
    private static let laterFile = "later.txt"

    /// The count of checkpoints that ``makeThreeCheckpoints(in:)`` makes.
    private static let threeCheckpointCount = 3

    // MARK: - Helpers

    /// One open session key over one temporary repository.
    private struct Fixture {

        /// The repository whose work tree the store records.
        let repository: TemporaryGitRepository

        /// The folder that holds the shadow repositories of ``store``.
        let storeDirectory: URL

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
        try repository.write(baseText, to: baseFile)
        try repository.commit(message: "base")
        let storeDirectory = TestSupport.makeTemporaryDirectory(named: testDirectoryName)
        let store = SnapshotStore(directory: storeDirectory)
        let session = makeSession(key: key, workingDirectory: repository.workDirectory)
        try await store.open(sessionKey: key, owner: session.sessionID, workingDirectory: repository.workDirectory)
        return Fixture(
            repository: repository, storeDirectory: storeDirectory, store: store, session: session,
            context: SnapshotsContext(store: store))
    }

    /// Makes a second store on the store folder of `fixture`, and opens the
    /// key of `fixture` on it with the working directory of `fixture`.
    ///
    /// - Parameters:
    ///   - fixture: The fixture whose store folder and key the new store
    ///     uses.
    ///   - owner: The session ID that opens the key on the new store.
    /// - Returns: The new store.
    /// - Throws: What the store throws.
    private static func openSecondStore(on fixture: Fixture, owner: String) async throws -> SnapshotStore {
        let store = SnapshotStore(directory: fixture.storeDirectory)
        try await store.open(
            sessionKey: fixture.session.sessionKey, owner: owner, workingDirectory: fixture.repository.workDirectory)
        return store
    }

    /// Gives the correction of a `perform` result, or `nil` for a value.
    ///
    /// - Parameter result: The result of `SnapshotsContext.perform`.
    /// - Returns: The corrective message of the failure, or `nil`.
    private static func correction<Value>(of result: Result<Value, CorrectiveRejection>) -> String? {
        guard case .failure(let rejection) = result else { return nil }
        return rejection.correctiveMessage
    }

    /// Makes a session with `key` in `workingDirectory`.
    ///
    /// - Parameters:
    ///   - key: The session key.
    ///   - workingDirectory: The working directory of the session.
    /// - Returns: The session.
    private static func makeSession(key: String, workingDirectory: URL) -> HookSession {
        makeSession(id: "session-\(key)", key: key, workingDirectory: workingDirectory)
    }

    /// Makes a session with the session ID `id` and `key` in
    /// `workingDirectory`.
    ///
    /// - Parameters:
    ///   - id: The session ID, which the store reads as the owner.
    ///   - key: The session key.
    ///   - workingDirectory: The working directory of the session.
    /// - Returns: The session.
    private static func makeSession(id: String, key: String, workingDirectory: URL) -> HookSession {
        HookSession(
            sessionID: id, sessionKey: key, parentSessionID: nil,
            workingDirectory: workingDirectory,
            dataDirectory: TestSupport.makeTemporaryDirectory(named: testDirectoryName))
    }

    /// Makes three checkpoints in the fixture: the first adds ``firstFile``,
    /// the second adds ``secondFile`` and changes ``baseFile``, and the third
    /// adds ``thirdFile``.
    ///
    /// - Parameter fixture: The fixture whose work tree changes.
    /// - Throws: What the repository or the store throws.
    private static func makeThreeCheckpoints(in fixture: Fixture) async throws {
        try fixture.repository.write("one\n", to: firstFile)
        try await take(label: "one", in: fixture)
        try fixture.repository.write("two\n", to: secondFile)
        try fixture.repository.write(changedBaseText, to: baseFile)
        try await take(label: "two", in: fixture)
        try fixture.repository.write("three\n", to: thirdFile)
        try await take(label: "three", in: fixture)
    }

    /// Takes a snapshot with `trigger` directly on the store of `fixture`,
    /// for the key and the owner of the session of `fixture`.
    ///
    /// - Parameters:
    ///   - trigger: The trigger of the snapshot.
    ///   - fixture: The fixture whose key and owner take the snapshot.
    /// - Throws: What the store throws.
    private static func take(_ trigger: SnapshotTrigger, in fixture: Fixture) async throws {
        _ = try await fixture.store.take(
            sessionKey: fixture.session.sessionKey, owner: fixture.session.sessionID, trigger: trigger)
    }

    /// Takes a manual snapshot with `label` directly on the store of
    /// `fixture`, for the key and the owner of the session of `fixture`.
    ///
    /// - Parameters:
    ///   - label: The label of the snapshot.
    ///   - fixture: The fixture whose key and owner take the snapshot.
    /// - Throws: What the store throws.
    private static func take(label: String, in fixture: Fixture) async throws {
        try await take(.manual(label: label), in: fixture)
    }

    /// Reads the checkpoints directly from the store of `fixture`, for the key
    /// and the owner of the session of `fixture`.
    ///
    /// - Parameter fixture: The fixture whose key and owner read.
    /// - Returns: The checkpoints, oldest first.
    /// - Throws: What the store throws.
    private static func checkpoints(of fixture: Fixture) async throws -> [Checkpoint] {
        try await fixture.store.checkpoints(sessionKey: fixture.session.sessionKey, owner: fixture.session.sessionID)
    }

    /// Calls `list` under `session` with `context`.
    ///
    /// - Parameters:
    ///   - session: The session that is bound for the call.
    ///   - context: The context of the verb.
    /// - Returns: The result of the verb.
    /// - Throws: What the verb throws.
    private static func list(as session: HookSession, with context: SnapshotsContext) async throws
        -> ListSnapshotsResult
    {
        try await HookSession.$current.withValue(session) {
            try await ListSnapshots(context: context).call(arguments: ListSnapshotsArguments())
        }
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

    /// The text of each file that a test reads, by path, in the work tree of
    /// `repository`. A missing file has no key.
    ///
    /// - Parameter repository: The repository.
    /// - Returns: The text of each file that is present.
    private static func workTree(of repository: TemporaryGitRepository) -> [String: String] {
        let paths = [baseFile, firstFile, secondFile, thirdFile, laterFile]
        return paths.reduce(into: [:]) { tree, path in tree[path] = contents(of: path, in: repository) }
    }

    /// The work tree after the first of three checkpoints.
    private static let treeAfterFirst = [baseFile: baseText, firstFile: "one\n"]

    /// The work tree after the third of three checkpoints.
    private static let treeAfterThird = [
        baseFile: changedBaseText, firstFile: "one\n", secondFile: "two\n", thirdFile: "three\n",
    ]

    /// Calls `rollback` under the session of `fixture`.
    ///
    /// - Parameters:
    ///   - index: The checkpoint to go back to.
    ///   - fixture: The fixture whose session is bound.
    /// - Returns: The result of the verb.
    /// - Throws: What the verb throws.
    private static func rollback(to index: Int, in fixture: Fixture) async throws -> RollbackSnapshotResult {
        try await HookSession.$current.withValue(fixture.session) {
            try await RollbackSnapshot(context: fixture.context).call(arguments: RollbackSnapshotArguments(index: index))
        }
    }

    /// Runs `code` as a `runCode` snippet under the session of `fixture`, over
    /// a surface with the files and the snapshots capabilities, and then takes
    /// the `PostToolUse` snapshot of that call, as `SnapshotHook` does.
    ///
    /// - Parameters:
    ///   - code: The snippet.
    ///   - fixture: The fixture whose session is bound.
    /// - Returns: The output of the snippet.
    /// - Throws: What the surface, the snippet or the store throws.
    private static func runSnippetThenTake(_ code: String, in fixture: Fixture) async throws -> String {
        let registry = try MultiTool.Builder()
            .withFiles(root: fixture.repository.workDirectory, readOnly: false)
            .withCapability(SnapshotsCapability(store: fixture.store))
            .buildRegistry()
        let multiTool = MultiTool(registry: registry)
        let output = try await HookSession.$current.withValue(fixture.session) {
            try await multiTool.call(arguments: RunCodeArguments(code: code))
        }
        try await take(.toolUse(toolCallID: "call-run", toolName: runCodeToolName), in: fixture)
        return output
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
        try await Self.take(.toolUse(toolCallID: "call-1", toolName: "write"), in: fixture)
        try fixture.repository.write("two\n", to: "two.txt")
        try await Self.take(label: "second", in: fixture)

        let result = try await HookSession.$current.withValue(fixture.session) {
            try await ListSnapshots(context: fixture.context).call(arguments: ListSnapshotsArguments())
        }

        #expect(result.correction == nil)
        #expect(result.checkpoints.map(\.index) == [1, 2])
        #expect(result.checkpoints.map(\.trigger) == ["tool write (call call-1)", "label second"])
        #expect(result.checkpoints.map(\.files) == [["one.txt"], ["two.txt"]])
        #expect(result.checkpoints.allSatisfy { !$0.date.isEmpty })
    }

    // MARK: - take

    /// `take` with a label after a file write gives a new checkpoint that
    /// carries the label and the written file.
    @Test("take with a label after a file write gives a checkpoint with that label")
    func takeWithALabelGivesACheckpointWithThatLabel() async throws {
        let fixture = try await Self.makeFixture()
        try fixture.repository.write("changed\n", to: Self.baseFile)

        let result = try await HookSession.$current.withValue(fixture.session) {
            try await TakeSnapshot(context: fixture.context).call(
                arguments: TakeSnapshotArguments(label: "before refactor"))
        }

        #expect(result.correction == nil)
        #expect(!result.isUnchanged)
        let checkpoint = try #require(result.checkpoint)
        #expect(checkpoint.index == 1)
        #expect(checkpoint.trigger == "label before refactor")
        #expect(checkpoint.files == [Self.baseFile])
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

    // MARK: - rollback

    /// A rollback to checkpoint 1 makes the full work tree equal to the tree
    /// after checkpoint 1: it restores the changed file, and it deletes the
    /// files that checkpoints 2 and 3 added.
    @Test("rollback to 1 of three checkpoints gives the full work tree after checkpoint 1")
    func rollbackToOneGivesTheTreeAfterCheckpointOne() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeThreeCheckpoints(in: fixture)

        let result = try await Self.rollback(to: 1, in: fixture)

        #expect(result.correction == nil)
        #expect(!result.isUnchanged)
        #expect(Self.workTree(of: fixture.repository) == Self.treeAfterFirst)
        let checkpoint = try #require(result.checkpoint)
        #expect(checkpoint.index == Self.threeCheckpointCount + 1)
        #expect(checkpoint.files.sorted() == [Self.baseFile, Self.secondFile, Self.thirdFile])
    }

    /// The rollback is itself a checkpoint at the end of the list, and the
    /// checkpoints after the restored one stay.
    @Test("after a rollback to 1, list gives four checkpoints and the fourth is 'rollback to 1'")
    func rollbackAppendsACheckpointToTheList() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeThreeCheckpoints(in: fixture)
        _ = try await Self.rollback(to: 1, in: fixture)

        let list = try await HookSession.$current.withValue(fixture.session) {
            try await ListSnapshots(context: fixture.context).call(arguments: ListSnapshotsArguments())
        }

        #expect(list.correction == nil)
        #expect(list.checkpoints.map(\.trigger) == ["label one", "label two", "label three", "rollback to 1"])
    }

    /// A second rollback to a checkpoint after the restored one rolls forward.
    @Test("after a rollback to 1, a rollback to 3 gives the tree after checkpoint 3 again")
    func rollbackRollsForward() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeThreeCheckpoints(in: fixture)
        _ = try await Self.rollback(to: 1, in: fixture)

        let result = try await Self.rollback(to: Self.threeCheckpointCount, in: fixture)

        #expect(result.correction == nil)
        #expect(result.checkpoint?.trigger == "rollback to 3")
        #expect(Self.workTree(of: fixture.repository) == Self.treeAfterThird)
    }

    /// A change after a rollback does not remove the later checkpoints, thus
    /// a rollback to a later point still works.
    @Test("after a rollback and a new file change, a rollback to a later point still works")
    func rollbackToALaterPointWorksAfterANewChange() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeThreeCheckpoints(in: fixture)
        _ = try await Self.rollback(to: 1, in: fixture)
        try fixture.repository.write("later\n", to: Self.laterFile)
        try await Self.take(label: "later", in: fixture)

        let result = try await Self.rollback(to: Self.threeCheckpointCount, in: fixture)

        #expect(result.correction == nil)
        #expect(Self.workTree(of: fixture.repository) == Self.treeAfterThird)
    }

    /// A rollback to index 0 gives the baseline work tree: the state when the
    /// session opened.
    @Test("rollback to 0 gives the baseline work tree")
    func rollbackToZeroGivesTheBaseline() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeThreeCheckpoints(in: fixture)

        let result = try await Self.rollback(to: 0, in: fixture)

        #expect(result.correction == nil)
        #expect(result.checkpoint?.trigger == "rollback to 0")
        #expect(Self.workTree(of: fixture.repository) == [Self.baseFile: Self.baseText])
    }

    /// An index below 0 or above the checkpoint count gives the
    /// `invalidCheckpoint` correction, and does not change the work tree or
    /// the list.
    @Test("rollback with an index out of range gives the invalidCheckpoint corrective result", arguments: [-1, 4])
    func rollbackOutOfRangeGivesTheCorrectiveResult(index: Int) async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeThreeCheckpoints(in: fixture)

        let result = try await Self.rollback(to: index, in: fixture)

        #expect(result.correction == SnapshotError.invalidCheckpoint(index: index).correctiveMessage)
        #expect(result.checkpoint == nil)
        #expect(!result.isUnchanged)
        #expect(Self.workTree(of: fixture.repository) == Self.treeAfterThird)
        let checkpoints = try await Self.checkpoints(of: fixture)
        #expect(checkpoints.count == Self.threeCheckpointCount)
    }

    /// The `invalidCheckpoint` correction tells the valid range and tells the
    /// model to call `list`.
    @Test("the invalidCheckpoint correction tells the valid range and names tools.snapshots.list")
    func invalidCheckpointCorrectionTellsTheRange() {
        let message = SnapshotError.invalidCheckpoint(index: 9).correctiveMessage

        #expect(message.contains("There is no checkpoint 9."), "message was: \(message)")
        #expect(message.contains("from 0"), "message was: \(message)")
        #expect(message.contains("count of checkpoints"), "message was: \(message)")
        #expect(message.contains("tools.snapshots.list"), "message was: \(message)")
    }

    /// A rollback to a point that is equal to the work tree makes no
    /// checkpoint, and says so.
    @Test("rollback to a point equal to the work tree gives no change and no checkpoint")
    func rollbackToTheCurrentTreeGivesNoChange() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeThreeCheckpoints(in: fixture)

        let result = try await Self.rollback(to: Self.threeCheckpointCount, in: fixture)

        #expect(result.correction == nil)
        #expect(result.isUnchanged)
        #expect(result.checkpoint == nil)
        let checkpoints = try await Self.checkpoints(of: fixture)
        #expect(checkpoints.count == Self.threeCheckpointCount)
    }

    // MARK: - rollback inside runCode

    /// A snippet that only rolls back, and the `PostToolUse` snapshot after
    /// it, add exactly one checkpoint: the rollback checkpoint.
    @Test("a snippet that only rolls back adds exactly one checkpoint, the rollback")
    func aSnippetThatOnlyRollsBackAddsOneCheckpoint() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeThreeCheckpoints(in: fixture)

        let output = try await Self.runSnippetThenTake(
            "return await tools.snapshots.rollback({ index: 1 });", in: fixture)

        let result = try RunOutput.decoded(SnippetCheckpointResult.self, from: output)
        #expect(result.correction == nil)
        let checkpoints = try await Self.checkpoints(of: fixture)
        #expect(checkpoints.count == Self.threeCheckpointCount + 1)
        #expect(checkpoints.last?.trigger == .rollback(to: 1))
        #expect(Self.workTree(of: fixture.repository) == Self.treeAfterFirst)
    }

    /// A change in the snippet before the rollback goes into a `pending`
    /// checkpoint, and the `PostToolUse` snapshot finds no change.
    @Test("a snippet that writes a file and then rolls back gives pending, then the rollback, and no PostToolUse")
    func aSnippetThatWritesThenRollsBackGivesPendingThenRollback() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeThreeCheckpoints(in: fixture)

        _ = try await Self.runSnippetThenTake(
            """
            await tools.files.write({ path: "\(Self.laterFile)", content: "later" });
            return await tools.snapshots.rollback({ index: 1 });
            """, in: fixture)

        let checkpoints = try await Self.checkpoints(of: fixture)
        #expect(checkpoints.dropFirst(Self.threeCheckpointCount).map(\.trigger) == [.pending, .rollback(to: 1)])
        #expect(checkpoints.dropFirst(Self.threeCheckpointCount).first?.files == [Self.laterFile])
        #expect(Self.workTree(of: fixture.repository) == Self.treeAfterFirst)
    }

    /// A change in the snippet after the rollback goes into the `PostToolUse`
    /// checkpoint, with only that file.
    @Test("a snippet that rolls back and then writes a file gives the rollback, then PostToolUse with that file")
    func aSnippetThatRollsBackThenWritesGivesRollbackThenPostToolUse() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeThreeCheckpoints(in: fixture)

        _ = try await Self.runSnippetThenTake(
            """
            await tools.snapshots.rollback({ index: 1 });
            return await tools.files.write({ path: "\(Self.laterFile)", content: "later" });
            """, in: fixture)

        let checkpoints = try await Self.checkpoints(of: fixture)
        let added = Array(checkpoints.dropFirst(Self.threeCheckpointCount))
        #expect(
            added.map(\.trigger) == [
                .rollback(to: 1), .toolUse(toolCallID: "call-run", toolName: Self.runCodeToolName),
            ])
        #expect(added.last?.files == [Self.laterFile])
    }

    /// The fields of a checkpoint result that a snippet returns, as JSON.
    private struct SnippetCheckpointResult: Decodable {

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

    // MARK: - Changed while closed

    /// A change of the work tree while no store had the key open becomes a
    /// `changedWhileClosed` checkpoint when a store opens the key again.
    /// `list` shows that checkpoint as text that the model can read.
    @Test("list after a change while the key was closed gives a 'changed while closed' checkpoint")
    func listGivesAChangedWhileClosedCheckpoint() async throws {
        let fixture = try await Self.makeFixture()
        await fixture.store.release(sessionKey: Self.firstKey, owner: fixture.session.sessionID)
        try fixture.repository.write("later\n", to: Self.laterFile)
        let reopened = try await Self.openSecondStore(on: fixture, owner: fixture.session.sessionID)

        let result = try await HookSession.$current.withValue(fixture.session) {
            try await ListSnapshots(context: SnapshotsContext(store: reopened)).call(
                arguments: ListSnapshotsArguments())
        }

        #expect(result.correction == nil)
        #expect(result.checkpoints.map(\.trigger) == ["changed while closed"])
        #expect(result.checkpoints.map(\.files) == [[Self.laterFile]])
    }

    // MARK: - Store errors

    /// The session key that is not one path component, because it holds a
    /// `/`.
    private static let keyWithASlash = "lineage/one"

    /// The path of the timeline ref in a shadow repository, relative to the
    /// shadow folder of the key.
    private static let timelineReferencePath = "refs/snapshots/timeline"

    /// The session ID of a second writer on the key of a fixture.
    private static let otherWriter = "session-other-writer"

    /// Moves the timeline ref of the key of `fixture` to `commit`, as a
    /// damaged timeline does. A store that has the key open keeps its
    /// checkpoints in memory: only a later open reads the moved ref.
    ///
    /// The shadow repository reads the objects of the source repository
    /// through its alternates file, thus a commit of the source repository
    /// is a commit that the timeline can name.
    ///
    /// - Parameters:
    ///   - fixture: The fixture whose timeline ref moves.
    ///   - commit: The 40-hex SHA of the new tip.
    /// - Throws: The error of `FileManager` or of the write.
    private static func pointTimeline(of fixture: Fixture, at commit: String) throws {
        let reference = fixture.storeDirectory
            .appendingPathComponent(fixture.session.sessionKey, isDirectory: true)
            .appendingPathComponent(timelineReferencePath, isDirectory: false)
        try FileManager.default.createDirectory(
            at: reference.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "\(commit)\n".write(to: reference, atomically: true, encoding: .utf8)
    }

    /// The label of the checkpoint that the other writer of
    /// ``moveTimelineFromAnotherStore(of:)`` takes.
    private static let otherWriterLabel = "other"

    /// Opens the key of `fixture` on a second store for ``otherWriter``, and
    /// takes a snapshot on it. Thus the timeline ref moves after the store of
    /// `fixture` read it, and the next write of `fixture` meets a conflict.
    ///
    /// - Parameter fixture: The fixture whose timeline the other store moves.
    /// - Returns: The other store, which has the key open for ``otherWriter``.
    /// - Throws: What the repository or the store throws.
    private static func moveTimelineFromAnotherStore(of fixture: Fixture) async throws -> SnapshotStore {
        let otherStore = try await openSecondStore(on: fixture, owner: otherWriter)
        try fixture.repository.write("one\n", to: firstFile)
        _ = try await otherStore.take(
            sessionKey: fixture.session.sessionKey, owner: otherWriter, trigger: .manual(label: otherWriterLabel))
        try fixture.repository.write("two\n", to: secondFile)
        return otherStore
    }

    /// Calls `take` with no label under the session of `fixture`.
    ///
    /// - Parameter fixture: The fixture whose session is bound.
    /// - Returns: The result of the verb.
    /// - Throws: What the verb throws.
    private static func takeSnapshot(in fixture: Fixture) async throws -> TakeSnapshotResult {
        try await HookSession.$current.withValue(fixture.session) {
            try await TakeSnapshot(context: fixture.context).call(arguments: TakeSnapshotArguments(label: nil))
        }
    }

    /// A take after another store moved the timeline of the same key gives
    /// the `timelineConflict` correction, and no checkpoint.
    @Test("take after another store moved the timeline gives the timelineConflict corrective result")
    func takeAfterAnotherWriterGivesTimelineConflict() async throws {
        let fixture = try await Self.makeFixture()
        _ = try await Self.moveTimelineFromAnotherStore(of: fixture)

        let result = try await Self.takeSnapshot(in: fixture)

        #expect(result.correction == SnapshotError.timelineConflict.correctiveMessage)
        #expect(result.checkpoint == nil)
        #expect(!result.isUnchanged)
    }

    /// An open over a timeline commit that has no `Snapshot-Trigger` trailer
    /// gives the `unreadableTimeline` correction, not a thrown error.
    @Test("an open over a timeline commit with no trigger gives the unreadableTimeline corrective result")
    func anOpenOverAnUnreadableTimelineGivesUnreadableTimeline() async throws {
        let fixture = try await Self.makeFixture()
        await fixture.store.release(sessionKey: Self.firstKey, owner: fixture.session.sessionID)
        try fixture.repository.write("one\n", to: Self.firstFile)
        try Self.pointTimeline(of: fixture, at: try fixture.repository.commit(message: "no trigger"))
        let workDirectory = fixture.repository.workDirectory

        let result = try await HookSession.$current.withValue(fixture.session) {
            try await fixture.context.perform { store, sessionKey, owner in
                try await store.open(sessionKey: sessionKey, owner: owner, workingDirectory: workDirectory)
            }
        }

        #expect(Self.correction(of: result) == SnapshotError.unreadableTimeline.correctiveMessage)
    }

    /// A remove of a key that a session has open gives the `sessionKeyOpen`
    /// correction, not a thrown error.
    @Test("a remove of the open key gives the sessionKeyOpen corrective result")
    func aRemoveOfTheOpenKeyGivesSessionKeyOpen() async throws {
        let fixture = try await Self.makeFixture()

        let result = try await HookSession.$current.withValue(fixture.session) {
            try await fixture.context.perform { store, sessionKey, _ in try await store.remove(sessionKey: sessionKey) }
        }

        #expect(Self.correction(of: result) == SnapshotError.sessionKeyOpen.correctiveMessage)
    }

    /// A session key that is not one path component gives the
    /// `invalidSessionKey` correction, not a thrown error.
    @Test("a session key with a slash gives the invalidSessionKey corrective result")
    func aSessionKeyWithASlashGivesInvalidSessionKey() async throws {
        let fixture = try await Self.makeFixture()
        let session = Self.makeSession(key: Self.keyWithASlash, workingDirectory: fixture.repository.workDirectory)

        let result = try await HookSession.$current.withValue(session) {
            try await fixture.context.perform { store, sessionKey, _ in try await store.remove(sessionKey: sessionKey) }
        }

        #expect(Self.correction(of: result) == SnapshotError.invalidSessionKey.correctiveMessage)
    }

    /// The correction of each store error that FoundationModelsHooks added
    /// tells the model what to do next with `tools.snapshots`.
    @Test(
        "the correction of each new store error names tools.snapshots",
        arguments: [
            SnapshotError.timelineConflict, .unreadableTimeline, .sessionKeyOpen, .invalidSessionKey, .noTimeline,
            .notAvailable(cause: .workingDirectoryMismatch), .notAvailable(cause: .timelineConflict),
            .notAvailable(cause: .openFailed), .fileNotInCheckpoint(path: "README.md"),
        ])
    func eachNewStoreErrorCorrectionNamesTheNextStep(error: SnapshotError) {
        let message = error.correctiveMessage

        #expect(message.contains("tools.snapshots"), "message was: \(message)")
    }

    // MARK: - Not available for this session

    /// The session ID of a session that opens the key of a fixture after the
    /// fixture opened it.
    private static let laterOwner = "session-later-owner"

    /// The name of the folder that holds the moved copy of the project of a
    /// fixture.
    private static let movedProjectName = "moved-project"

    /// Copies the work tree of `fixture`, with its git folder, to a new
    /// folder, as a move of the project does.
    ///
    /// - Parameter fixture: The fixture whose project moves.
    /// - Returns: The folder of the moved project.
    /// - Throws: The error of `FileManager`.
    private static func moveProject(of fixture: Fixture) throws -> URL {
        let moved = TestSupport.makeTemporaryDirectory(named: testDirectoryName)
            .appendingPathComponent(movedProjectName, isDirectory: true)
        try FileManager.default.copyItem(at: fixture.repository.workDirectory, to: moved)
        return moved
    }

    /// Makes the session of ``laterOwner`` on the key of the first session of
    /// a test, in `workingDirectory`.
    ///
    /// - Parameter workingDirectory: The working directory of the session.
    /// - Returns: The session.
    private static func makeLaterSession(in workingDirectory: URL) -> HookSession {
        makeSession(id: laterOwner, key: firstKey, workingDirectory: workingDirectory)
    }

    /// A session that opens the key from a moved project, while the first
    /// session has the key open from the old folder, gets the
    /// `notAvailable(workingDirectoryMismatch)` correction from `list`, and
    /// none of the checkpoints of the first session.
    @Test("list after an open from a moved project gives notAvailable workingDirectoryMismatch and no other checkpoint")
    func listAfterAnOpenFromAMovedProjectGivesWorkingDirectoryMismatch() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeThreeCheckpoints(in: fixture)
        let moved = try Self.moveProject(of: fixture)
        await #expect(throws: SnapshotError.workingDirectoryMismatch) {
            try await fixture.store.open(sessionKey: Self.firstKey, owner: Self.laterOwner, workingDirectory: moved)
        }

        let result = try await Self.list(as: Self.makeLaterSession(in: moved), with: fixture.context)

        let correction = try #require(result.correction)
        #expect(correction == SnapshotError.notAvailable(cause: .workingDirectoryMismatch).correctiveMessage)
        #expect(!correction.contains(Self.movedProjectName), "correction was: \(correction)")
        #expect(!correction.contains(fixture.repository.workDirectory.path), "correction was: \(correction)")
        #expect(result.checkpoints.isEmpty)
        #expect(try await Self.checkpoints(of: fixture).count == Self.threeCheckpointCount)
    }

    /// After a take meets a timeline conflict, `list` gives the
    /// `notAvailable(timelineConflict)` correction, and not the checkpoint of
    /// the other writer that has the key open.
    @Test("list after a timeline conflict gives notAvailable timelineConflict and not the checkpoint of the other writer")
    func listAfterATimelineConflictGivesTimelineConflict() async throws {
        let fixture = try await Self.makeFixture()
        let otherStore = try await Self.moveTimelineFromAnotherStore(of: fixture)
        _ = try await Self.takeSnapshot(in: fixture)

        let result = try await Self.list(as: fixture.session, with: fixture.context)

        #expect(result.correction == SnapshotError.notAvailable(cause: .timelineConflict).correctiveMessage)
        #expect(result.checkpoints.isEmpty)
        let otherCheckpoints = try await otherStore.checkpoints(sessionKey: Self.firstKey, owner: Self.otherWriter)
        #expect(otherCheckpoints.map(\.trigger) == [.manual(label: Self.otherWriterLabel)])
    }

    /// A session whose open failed with an error that is not a working folder
    /// mismatch or a conflict (here a timeline commit with no trigger) gets
    /// the `notAvailable(openFailed)` correction from `list`, and none of the
    /// checkpoints of the first session, which has the key open on its own
    /// store.
    @Test("list after a failed open gives notAvailable openFailed and not the checkpoints of the open session")
    func listAfterAFailedOpenGivesOpenFailed() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeThreeCheckpoints(in: fixture)
        try fixture.repository.write("later\n", to: Self.laterFile)
        try Self.pointTimeline(of: fixture, at: try fixture.repository.commit(message: "no trigger"))
        let laterStore = SnapshotStore(directory: fixture.storeDirectory)
        let workDirectory = fixture.repository.workDirectory
        await #expect(throws: SnapshotError.unreadableTimeline) {
            try await laterStore.open(sessionKey: Self.firstKey, owner: Self.laterOwner, workingDirectory: workDirectory)
        }

        let result = try await Self.list(
            as: Self.makeLaterSession(in: workDirectory), with: SnapshotsContext(store: laterStore))

        #expect(result.correction == SnapshotError.notAvailable(cause: .openFailed).correctiveMessage)
        #expect(result.checkpoints.isEmpty)
        #expect(try await Self.checkpoints(of: fixture).count == Self.threeCheckpointCount)
    }

    /// A session that did not open the key, while another session has the
    /// key open on the same store, gets the `unavailable` correction from
    /// `list`, and none of the checkpoints of the other session.
    @Test("list from a session that did not open the key gives unavailable and not the checkpoints of the open session")
    func listFromASessionThatDidNotOpenTheKeyGivesUnavailable() async throws {
        let fixture = try await Self.makeFixture()
        try await Self.makeThreeCheckpoints(in: fixture)

        let result = try await Self.list(
            as: Self.makeLaterSession(in: fixture.repository.workDirectory), with: fixture.context)

        #expect(result.correction == Self.unavailableCorrection)
        #expect(result.checkpoints.isEmpty)
        #expect(try await Self.checkpoints(of: fixture).count == Self.threeCheckpointCount)
    }

    /// The `notAvailable` correction names the cause case, and tells the
    /// model not to call `tools.snapshots` again in the session.
    @Test(
        "the notAvailable correction names the cause and tells the model to stop",
        arguments: [
            (SnapshotUnavailableCause.workingDirectoryMismatch, "workingDirectoryMismatch"),
            (.timelineConflict, "timelineConflict"), (.openFailed, "openFailed"),
        ])
    func notAvailableCorrectionNamesTheCause(cause: SnapshotUnavailableCause, name: String) {
        let message = SnapshotError.notAvailable(cause: cause).correctiveMessage

        #expect(
            message
                == "Snapshots are not available for this session: \(name). "
                + "Do not call tools.snapshots again in this session.")
    }

    /// The `unavailable` correction names each reason: no bound session, a
    /// session that did not open its key, and a folder that is not in a git
    /// work tree.
    @Test("the unavailable correction names a session that did not open its session key")
    func unavailableCorrectionNamesEachReason() {
        let message = Self.unavailableCorrection

        #expect(message.contains("no session is bound to the call"), "message was: \(message)")
        #expect(message.contains("did not open its session key"), "message was: \(message)")
        #expect(message.contains("not in a git work tree"), "message was: \(message)")
    }

    // MARK: - Shared result builders

    /// The correction that the tests of the shared result builders give.
    private static let sharedCorrection = "Call tools.snapshots.list to see the checkpoints."

    /// Each result type of the capability gets its correction-only value from
    /// the one shared `corrective(_:)` of `SnapshotsVerbResult`.
    @Test("each result type builds a correction-only result through the shared builder")
    func eachResultTypeBuildsACorrectionOnlyResult() {
        let list = ListSnapshotsResult.corrective(Self.sharedCorrection)
        let take = TakeSnapshotResult.corrective(Self.sharedCorrection)
        let rollback = RollbackSnapshotResult.corrective(Self.sharedCorrection)

        #expect(list.correction == Self.sharedCorrection)
        #expect(list.checkpoints.isEmpty)
        #expect(take.correction == Self.sharedCorrection)
        #expect(take.checkpoint == nil)
        #expect(!take.isUnchanged)
        #expect(rollback.correction == Self.sharedCorrection)
        #expect(rollback.checkpoint == nil)
        #expect(!rollback.isUnchanged)
    }

    /// A take and a rollback that made no checkpoint each give "no change"
    /// through the one shared `result(of:)` of `SnapshotCheckpointResult`.
    @Test("each checkpoint result type builds a no-change result through the shared builder")
    func eachCheckpointResultTypeBuildsANoChangeResult() {
        let take = TakeSnapshotResult.result(of: nil)
        let rollback = RollbackSnapshotResult.result(of: nil)

        #expect(take.isUnchanged)
        #expect(take.checkpoint == nil)
        #expect(take.correction == nil)
        #expect(rollback.isUnchanged)
        #expect(rollback.checkpoint == nil)
        #expect(rollback.correction == nil)
    }

    // MARK: - Unavailable

    /// Each verb gives the `unavailable` correction when no session is bound.
    @Test("each verb with no bound session gives the unavailable corrective result")
    func eachVerbWithNoBoundSessionGivesUnavailable() async throws {
        let fixture = try await Self.makeFixture()

        let list = try await ListSnapshots(context: fixture.context).call(arguments: ListSnapshotsArguments())
        let take = try await TakeSnapshot(context: fixture.context).call(arguments: TakeSnapshotArguments(label: nil))
        let rollback = try await RollbackSnapshot(context: fixture.context).call(
            arguments: RollbackSnapshotArguments(index: 0))

        #expect(list.correction == Self.unavailableCorrection)
        #expect(take.correction == Self.unavailableCorrection)
        #expect(rollback.correction == Self.unavailableCorrection)
        #expect(rollback.checkpoint == nil)
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

        try first.repository.write("first change\n", to: Self.baseFile)
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
        #expect(firstList.checkpoints.map(\.files) == [[Self.baseFile]])
        #expect(secondList.checkpoints.map(\.trigger) == ["label second"])
        #expect(secondList.checkpoints.map(\.files) == [["other.txt"]])
    }

    /// One capability value rolls back the work tree of the key that the
    /// bound session names, for each of two keys.
    @Test("one capability value rolls back the work tree of the key of each bound session")
    func oneCapabilityRollsBackTheTreeOfEachBoundSession() async throws {
        let first = try await Self.makeFixture(key: Self.firstKey)
        let secondRepository = try TemporaryGitRepository()
        try secondRepository.write("other\n", to: "other.txt")
        try secondRepository.commit(message: "other")
        let secondSession = Self.makeSession(key: Self.secondKey, workingDirectory: secondRepository.workDirectory)
        try await first.store.open(
            sessionKey: Self.secondKey, owner: secondSession.sessionID,
            workingDirectory: secondRepository.workDirectory)
        try first.repository.write("first change\n", to: Self.baseFile)
        try await Self.take(label: "first", in: first)
        try secondRepository.write("second change\n", to: "other.txt")
        _ = try await first.store.take(
            sessionKey: Self.secondKey, owner: secondSession.sessionID, trigger: .manual(label: "second"))
        let rollback = RollbackSnapshot(context: first.context)

        let firstResult = try await HookSession.$current.withValue(first.session) {
            try await rollback.call(arguments: RollbackSnapshotArguments(index: 0))
        }
        let secondResult = try await HookSession.$current.withValue(secondSession) {
            try await rollback.call(arguments: RollbackSnapshotArguments(index: 0))
        }

        #expect(firstResult.checkpoint?.files == [Self.baseFile])
        #expect(secondResult.checkpoint?.files == ["other.txt"])
        #expect(Self.contents(of: Self.baseFile, in: first.repository) == Self.baseText)
        #expect(Self.contents(of: "other.txt", in: secondRepository) == "other\n")
    }

    /// A `tools.snapshots` call inside a `runCode` snippet sees the session
    /// that the `runCode` call was bound to, although the interpreter runs
    /// each job of the snippet on its own queue.
    @Test("a snippet call of tools.snapshots sees the session of the runCode call")
    func aSnippetCallSeesTheSessionOfTheRunCodeCall() async throws {
        let fixture = try await Self.makeFixture()
        try fixture.repository.write("changed\n", to: Self.baseFile)
        let multiTool = MultiTool(
            registry: try MultiTool.Builder().withCapability(SnapshotsCapability(store: fixture.store))
                .buildRegistry())

        let output = try await HookSession.$current.withValue(fixture.session) {
            try await multiTool.call(
                arguments: RunCodeArguments(
                    code: "return await tools.snapshots.take({ label: 'from snippet' });"))
        }

        let result = try RunOutput.decoded(SnippetCheckpointResult.self, from: output)
        #expect(result.correction == nil)
        #expect(result.checkpoint?.trigger == "label from snippet")
    }

    // MARK: - Discovery

    /// `searchTools` finds each of the three verbs of the capability.
    @Test("searchTools finds the three snapshots verbs")
    func searchToolsFindsTheThreeSnapshotsVerbs() async throws {
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

    /// The verb names `reset` and `rewind` in the snapshots group are
    /// answered with the rollback verb, through the verb alias table.
    @Test("snapshots.reset and snapshots.rewind are answered with snapshots.rollback", arguments: ["reset", "rewind"])
    func resetAndRewindAreAnsweredWithRollback(verb: String) async throws {
        let fixture = try await Self.makeFixture()
        let registry = try MultiTool.Builder().withCapability(SnapshotsCapability(store: fixture.store))
            .buildRegistry()
        let shape = MultiTool.RegistryBundleShape(bindsSearchTools: false, discovery: .none, embedder: nil)
        let bundle = MultiTool.RegistryBundle(registry: registry, shape: shape)
        let guess = "snapshots.\(verb)"

        let resolution = try #require(
            await UnknownToolHint.hint(
                message: "TypeError: tools.\(guess) is not a function",
                snippet: "return await tools.\(guess)({ index: 1 });",
                surface: registry.surface,
                searcher: bundle.hintSearcher))

        #expect(resolution.tier == .verbAlias)
        #expect(resolution.suggestedPaths == [Self.rollbackPath])
        #expect(resolution.text.contains("Call tools.\(Self.rollbackPath) instead."), "text was: \(resolution.text)")
    }
}
