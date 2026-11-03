import Darwin
import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The rules of `ProcessLedger` that no store or server needs to show: an
/// owner that is unreadable writes no record, and a kill reaches the right
/// process when the child leads no group of its own.
///
/// Each test spawns its own children (`OwnedChild`). No test signals any other
/// process, and no test waits for a time.
@Suite("ProcessLedgerTests", .ownsTemporaryDirectories)
struct ProcessLedgerTests {

    /// The name prefix of the temporary directory of one test.
    private static let testDirectoryNamePrefix = "process-ledger-tests"

    /// The number of kills that one reap of one record makes.
    private static let oneKill = 1

    /// A ledger over a directory that the test owns.
    private func makeLedger() -> ProcessLedger {
        ProcessLedger(directory: CrashReapFixture.makeDirectory(prefix: Self.testDirectoryNamePrefix))
    }

    @Test("a record with an unreadable owner throws")
    func unreadableOwnerThrows() throws {
        let child = try OwnedChild()
        let identity = try #require(ProcessIdentity.of(pid: child.pid))
        let ledger = makeLedger()

        #expect(throws: ProcessLedger.RecordError.ownerUnreadable) {
            try ledger.record(key: CrashReapFixture.recordKey, child: identity, owner: nil)
        }
        _ = child.finish()
    }

    @Test("a record with an unreadable owner leaves no file")
    func unreadableOwnerLeavesNoFile() throws {
        let child = try OwnedChild()
        let identity = try #require(ProcessIdentity.of(pid: child.pid))
        let ledger = makeLedger()

        try? ledger.record(key: CrashReapFixture.recordKey, child: identity, owner: nil)

        #expect(ledger.recordedKeys().isEmpty)
        _ = child.finish()
    }

    @Test("recording a live process with an unreadable owner leaves no file")
    func recordProcessWithUnreadableOwnerLeavesNoFile() throws {
        let child = try OwnedChild()
        let ledger = makeLedger()

        ledger.recordProcess(key: CrashReapFixture.recordKey, pid: child.pid, owner: nil)

        #expect(ledger.recordedKeys().isEmpty)
        _ = child.finish()
    }

    @Test("recording a live process writes a record under the key")
    func recordProcessWritesRecord() throws {
        let child = try OwnedChild()
        let ledger = makeLedger()

        ledger.recordProcess(key: CrashReapFixture.recordKey, pid: child.pid)

        #expect(ledger.recordedKeys() == [CrashReapFixture.recordKey])
        _ = child.finish()
    }

    @Test("a reap kills a matching child that leads no group, and only that child")
    func killsMatchingChildWithoutOwnGroup() throws {
        let leftover = try OwnedChild(leadsGroup: false)
        let identity = try #require(ProcessIdentity.of(pid: leftover.pid))
        let ledger = makeLedger()
        try ledger.record(key: CrashReapFixture.recordKey, child: identity, owner: CrashReapFixture.deadOwner)

        let killed = ledger.reapLeftovers()

        #expect(killed == Self.oneKill)
        #expect(leftover.finish() == .signaled(SIGKILL))
    }
}
