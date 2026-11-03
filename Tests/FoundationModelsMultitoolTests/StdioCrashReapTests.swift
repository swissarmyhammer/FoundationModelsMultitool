import Darwin
import FoundationModelsExtras
import Foundation
import Testing

@testable import FoundationModelsMultitool

/// A host that crashed leaves the stdio servers it spawned. A server that
/// exits on the end of its input leaves with the host, but a server is a
/// program of another author, and Multitool cannot make it do that. A new
/// `StdioServerProcess` over the same record directory kills the process group
/// of each leftover, and only that group: the pid AND the start time of the
/// record must match a live process.
///
/// Each test spawns its own children (`OwnedChild`). No test signals any other
/// process, and no test waits for a time.
@Suite("StdioCrashReapTests", .ownsTemporaryDirectories)
struct StdioCrashReapTests {

    /// Owns the temporary directories of this suite.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test.
    private static let testDirectoryNamePrefix = "stdio-crash-reap-tests"

    /// The server program of the tests. It reads its input and exits on the
    /// end of that input.
    private static let serverProgram = "/bin/cat"

    /// The server name of the tests.
    private static let serverName = "crash-reap-test"

    /// The key of the record that a test writes.
    private static let recordKey = "leftover"

    /// The offset, in seconds, that makes a start time differ from the real
    /// one. It stands for a pid that another process took.
    private static let otherStartOffset: Int64 = 1

    /// An owner that is not alive: the pid of this process with a start time
    /// that this process never had.
    private static var deadOwner: ProcessIdentity {
        ProcessIdentity(pid: ProcessIdentity.own.pid, startSeconds: 0, startMicroseconds: 0)
    }

    // MARK: - Helpers

    /// A record directory that this test owns.
    ///
    /// - Throws: When the directory does not prepare.
    private func makeRecordDirectory() throws -> URL {
        try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
    }

    /// Makes a server process over `directory`, with a private registry.
    ///
    /// - Parameter directory: The directory of the record files.
    /// - Throws: What `StdioServerProcess.init` throws.
    private func makeServer(recordDirectory directory: URL) throws -> StdioServerProcess {
        try StdioServerProcess(
            command: Self.serverProgram, name: Self.serverName,
            crashRecordDirectory: directory, registry: ProcessRegistry())
    }

    /// Writes a record for `child` as a crashed host would have left it.
    ///
    /// - Parameters:
    ///   - child: The identity the record holds.
    ///   - directory: The directory of the record files.
    /// - Throws: When the record does not write.
    private func leaveRecord(child: ProcessIdentity, in directory: URL) throws {
        try ProcessLedger(directory: directory)
            .record(key: Self.recordKey, child: child, owner: Self.deadOwner)
    }

    // MARK: - The reap

    @Test("a new server process kills the group of a leftover whose pid and start time match")
    func killsMatchingLeftover() throws {
        let leftover = try OwnedChild()
        let directory = try makeRecordDirectory()
        try leaveRecord(child: try #require(ProcessIdentity.of(pid: leftover.pid)), in: directory)

        _ = try makeServer(recordDirectory: directory)

        #expect(leftover.finish() == .signaled(SIGKILL))
    }

    @Test("a new server process spares a process that has the pid of the record and another start time")
    func sparesReusedPid() throws {
        let bystander = try OwnedChild()
        let directory = try makeRecordDirectory()
        var identity = try #require(ProcessIdentity.of(pid: bystander.pid))
        identity.startSeconds += Self.otherStartOffset
        try leaveRecord(child: identity, in: directory)

        _ = try makeServer(recordDirectory: directory)

        #expect(bystander.finish() == .exited(0))
    }

    // MARK: - The record of a live server

    @Test("a spawned server has a record")
    func recordStartsWithServer() async throws {
        let directory = try makeRecordDirectory()
        let server = try makeServer(recordDirectory: directory)
        _ = try await server.respawn()

        #expect(ProcessLedger(directory: directory).recordedKeys().count == 1)

        await server.shutdown()
    }

    @Test("the shutdown of a server removes its record")
    func recordEndsWithShutdown() async throws {
        let directory = try makeRecordDirectory()
        let server = try makeServer(recordDirectory: directory)
        _ = try await server.respawn()

        await server.shutdown()

        #expect(ProcessLedger(directory: directory).recordedKeys().isEmpty)
    }
}
