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

    /// The name prefix of the temporary directory of one test.
    private static let testDirectoryNamePrefix = "crash-reap-tests"

    // MARK: - Helpers

    /// A store directory that this test owns.
    private func makeStoreDirectory() -> URL {
        CrashReapFixture.makeDirectory(prefix: Self.testDirectoryNamePrefix)
            .appendingPathComponent(".shell")
    }

    /// Writes a record for `child` as a crashed host would have left it, and
    /// then makes a new store over the same directory and asks it to reap.
    ///
    /// - Parameters:
    ///   - child: The identity the record holds for the child.
    ///   - owner: The host that wrote the record.
    /// - Throws: When the store or the record does not write.
    private func openStoreAfterCrash(child: ProcessIdentity, owner: ProcessIdentity) throws {
        let directory = makeStoreDirectory()
        let first = try ShellState(preferredDirectory: directory)
        try first.processLedger.record(key: CrashReapFixture.recordKey, child: child, owner: owner)
        try ShellState(preferredDirectory: directory).reapLeftovers()
    }

    // MARK: - The reap

    @Test("a new store kills the group of a leftover whose pid and start time match")
    func killsMatchingLeftover() throws {
        try CrashReapFixture.expectMatchingLeftoverKilled(reapAfterCrash: openStoreAfterCrash)
    }

    @Test("a new store spares a process that has the pid of the record and another start time")
    func sparesReusedPid() throws {
        try CrashReapFixture.expectReusedPidSpared(reapAfterCrash: openStoreAfterCrash)
    }

    @Test("a new store spares the child of a record whose host is alive")
    func sparesChildOfLiveHost() throws {
        let running = try OwnedChild()
        let identity = try #require(ProcessIdentity.of(pid: running.pid))

        try openStoreAfterCrash(child: identity, owner: try #require(ProcessIdentity.own))

        #expect(running.finish() == .exited(0))
    }

    @Test("a new store removes the record that it handled")
    func removesHandledRecord() throws {
        let leftover = try OwnedChild()
        let identity = try #require(ProcessIdentity.of(pid: leftover.pid))
        let directory = makeStoreDirectory()
        let first = try ShellState(preferredDirectory: directory)
        try first.processLedger.record(
            key: CrashReapFixture.recordKey, child: identity, owner: CrashReapFixture.deadOwner)

        let second = try ShellState(preferredDirectory: directory)
        second.reapLeftovers()

        #expect(second.processLedger.recordedKeys().isEmpty)
        _ = leftover.finish()
    }

    @Test("making a store reaps nothing until the caller asks")
    func makingAStoreKillsNothing() throws {
        let leftover = try OwnedChild()
        let identity = try #require(ProcessIdentity.of(pid: leftover.pid))
        let directory = makeStoreDirectory()
        let first = try ShellState(preferredDirectory: directory)
        try first.processLedger.record(
            key: CrashReapFixture.recordKey, child: identity, owner: CrashReapFixture.deadOwner)

        _ = try ShellState(preferredDirectory: directory)

        #expect(leftover.finish() == .exited(0))
    }

    @Test("a store that a ShellStore makes reaps the leftover once")
    func shellStoreReapsLeftover() throws {
        let leftover = try OwnedChild()
        let identity = try #require(ProcessIdentity.of(pid: leftover.pid))
        let directory = makeStoreDirectory()
        let first = try ShellState(preferredDirectory: directory)
        try first.processLedger.record(
            key: CrashReapFixture.recordKey, child: identity, owner: CrashReapFixture.deadOwner)

        _ = try ShellStore(storeDirectory: directory)

        #expect(leftover.finish() == .signaled(SIGKILL))
    }

    @Test("a new store removes a record that does not decode, and kills nothing")
    func removesUndecodableRecord() throws {
        let bystander = try OwnedChild()
        let directory = makeStoreDirectory()
        let first = try ShellState(preferredDirectory: directory)
        let ledgerDirectory = first.processLedger.directory
        try FileManager.default.createDirectory(at: ledgerDirectory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(
            to: ledgerDirectory.appendingPathComponent(CrashReapFixture.recordKey)
                .appendingPathExtension("json"))

        let second = try ShellState(preferredDirectory: directory)
        second.reapLeftovers()

        #expect(second.processLedger.recordedKeys().isEmpty)
        #expect(bystander.finish() == .exited(0))
    }

    // MARK: - The record of a live command

    @Test("a registered process has a record with the key of its command")
    func recordStartsWithProcess() async throws {
        let child = try OwnedChild()
        let state = try ShellState(preferredDirectory: makeStoreDirectory())
        let noSignal = ProcessGroupKill(pid: child.pid, signal: { _ in })

        await state.registerProcess(commandID: CrashReapFixture.recordKey, group: noSignal)

        #expect(state.processLedger.recordedKeys() == [CrashReapFixture.recordKey])
        _ = child.finish()
    }

    @Test("the end of a command removes its record")
    func recordEndsWithCommand() async throws {
        let child = try OwnedChild()
        let state = try ShellState(preferredDirectory: makeStoreDirectory())
        let noSignal = ProcessGroupKill(pid: child.pid, signal: { _ in })
        await state.registerProcess(commandID: CrashReapFixture.recordKey, group: noSignal)

        await state.completeCommand(commandID: CrashReapFixture.recordKey)

        #expect(state.processLedger.recordedKeys().isEmpty)
        _ = child.finish()
    }
}
