import Darwin
import Foundation
import Testing

@testable import FoundationModelsMultitool

/// A host that crashed leaves the shell children it started. A new
/// `ShellState` on the same `.shell` directory kills the process group of each
/// leftover, and only that group: the pid AND the start time of the record
/// must match a live process.
///
/// Each test spawns its own children (`OwnedChild`). No test signals any other
/// process, and no test waits for a time: a child ends by a kill or by the
/// close of its input, and `waitpid` returns on that end.
@Suite("ShellCrashReapTests", .ownsTemporaryDirectories)
struct ShellCrashReapTests {

    /// Owns the temporary directories of the shell stores of this suite.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test.
    private static let testDirectoryNamePrefix = "crash-reap-tests"

    /// The offset, in seconds, that makes a start time differ from the real
    /// one. It stands for a pid that another process took.
    private static let otherStartOffset: Int64 = 1

    /// The key of the record that a test writes.
    private static let recordKey = "leftover"

    /// An owner that is not alive: the pid of this process with a start time
    /// that this process never had.
    private static var deadOwner: ProcessIdentity {
        ProcessIdentity(
            pid: ProcessIdentity.own.pid, startSeconds: 0, startMicroseconds: 0)
    }

    // MARK: - Helpers

    /// A store directory that this test owns.
    ///
    /// - Throws: When the directory does not prepare.
    private func makeStoreDirectory() throws -> URL {
        try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
            .appendingPathComponent(".shell")
    }

    /// Writes a record for `child` as a crashed host would have left it, and
    /// then makes a new store over the same directory.
    ///
    /// - Parameters:
    ///   - child: The identity the record holds for the child.
    ///   - owner: The host that wrote the record.
    /// - Throws: When the store or the record does not write.
    private func openStoreAfterCrash(child: ProcessIdentity, owner: ProcessIdentity) throws {
        let directory = try makeStoreDirectory()
        let first = try ShellState(preferredDirectory: directory)
        try first.processLedger.record(key: Self.recordKey, child: child, owner: owner)
        _ = try ShellState(preferredDirectory: directory)
    }

    // MARK: - The reap

    @Test("a new store kills the group of a leftover whose pid and start time match")
    func killsMatchingLeftover() throws {
        let leftover = try OwnedChild()
        let identity = try #require(ProcessIdentity.of(pid: leftover.pid))

        try openStoreAfterCrash(child: identity, owner: Self.deadOwner)

        #expect(leftover.finish() == .signaled(SIGKILL))
    }

    @Test("a new store spares a process that has the pid of the record and another start time")
    func sparesReusedPid() throws {
        let bystander = try OwnedChild()
        var identity = try #require(ProcessIdentity.of(pid: bystander.pid))
        identity.startSeconds += Self.otherStartOffset

        try openStoreAfterCrash(child: identity, owner: Self.deadOwner)

        #expect(bystander.finish() == .exited(0))
    }

    @Test("a new store spares the child of a record whose host is alive")
    func sparesChildOfLiveHost() throws {
        let running = try OwnedChild()
        let identity = try #require(ProcessIdentity.of(pid: running.pid))

        try openStoreAfterCrash(child: identity, owner: .own)

        #expect(running.finish() == .exited(0))
    }

    @Test("a new store removes the record that it handled")
    func removesHandledRecord() throws {
        let leftover = try OwnedChild()
        let identity = try #require(ProcessIdentity.of(pid: leftover.pid))
        let directory = try makeStoreDirectory()
        let first = try ShellState(preferredDirectory: directory)
        try first.processLedger.record(key: Self.recordKey, child: identity, owner: Self.deadOwner)

        let second = try ShellState(preferredDirectory: directory)

        #expect(second.processLedger.recordedKeys().isEmpty)
        _ = leftover.finish()
    }

    // MARK: - The record of a live command

    @Test("a registered process has a record with the key of its command")
    func recordStartsWithProcess() async throws {
        let child = try OwnedChild()
        let state = try ShellState(preferredDirectory: makeStoreDirectory())
        let noSignal = ProcessGroupKill(pid: child.pid, signal: { _ in })

        await state.registerProcess(commandID: Self.recordKey, group: noSignal)

        #expect(state.processLedger.recordedKeys() == [Self.recordKey])
        _ = child.finish()
    }

    @Test("the end of a command removes its record")
    func recordEndsWithCommand() async throws {
        let child = try OwnedChild()
        let state = try ShellState(preferredDirectory: makeStoreDirectory())
        let noSignal = ProcessGroupKill(pid: child.pid, signal: { _ in })
        await state.registerProcess(commandID: Self.recordKey, group: noSignal)

        await state.completeCommand(commandID: Self.recordKey)

        #expect(state.processLedger.recordedKeys().isEmpty)
        _ = child.finish()
    }
}
