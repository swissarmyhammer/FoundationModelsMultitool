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

    /// The name prefix of the temporary directory of one test.
    private static let testDirectoryNamePrefix = "stdio-crash-reap-tests"

    /// The server program of the tests. It reads its input and exits on the
    /// end of that input.
    private static let serverProgram = "/bin/cat"

    /// The server name of the tests.
    private static let serverName = "crash-reap-test"

    // MARK: - Helpers

    /// A record directory that this test owns.
    private func makeRecordDirectory() -> URL {
        CrashReapFixture.makeDirectory(prefix: Self.testDirectoryNamePrefix)
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

    /// Writes a record for `child` as a crashed host would have left it, and
    /// then makes a new server process over the same directory.
    ///
    /// - Parameters:
    ///   - child: The identity the record holds for the child.
    ///   - owner: The host that wrote the record.
    /// - Throws: When the record does not write.
    private func openServerAfterCrash(child: ProcessIdentity, owner: ProcessIdentity) throws {
        let directory = makeRecordDirectory()
        try ProcessLedger(directory: directory)
            .record(key: CrashReapFixture.recordKey, child: child, owner: owner)
        _ = try makeServer(recordDirectory: directory)
    }

    // MARK: - The reap

    @Test("a new server process kills the group of a leftover whose pid and start time match")
    func killsMatchingLeftover() throws {
        try CrashReapFixture.expectMatchingLeftoverKilled(reapAfterCrash: openServerAfterCrash)
    }

    @Test("a new server process spares a process that has the pid of the record and another start time")
    func sparesReusedPid() throws {
        try CrashReapFixture.expectReusedPidSpared(reapAfterCrash: openServerAfterCrash)
    }

    // MARK: - The record of a live server

    @Test("a spawned server has a record")
    func recordStartsWithServer() async throws {
        let directory = makeRecordDirectory()
        let server = try makeServer(recordDirectory: directory)
        _ = try await server.respawn()

        #expect(ProcessLedger(directory: directory).recordedKeys().count == 1)

        await server.shutdown()
    }

    @Test("the shutdown of a server removes its record")
    func recordEndsWithShutdown() async throws {
        let directory = makeRecordDirectory()
        let server = try makeServer(recordDirectory: directory)
        _ = try await server.respawn()

        await server.shutdown()

        #expect(ProcessLedger(directory: directory).recordedKeys().isEmpty)
    }
}
