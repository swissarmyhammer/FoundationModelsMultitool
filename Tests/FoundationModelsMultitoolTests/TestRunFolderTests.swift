// `TestRunFolderTests` — the folder of the test run stands in the folder of
// this process, and the first use removes the folders of the processes that
// do not run.

import Darwin
import Foundation
import Testing

@testable import MultitoolTestSupport

/// Tests for ``TestRunFolder``.
@Suite("TestRunFolderTests")
struct TestRunFolderTests {

    /// The temporary directories of each test, removed when the test ends.
    private let scratch = TestScratch()

    /// A process id that no process can have: it is more than `PID_MAX`
    /// (99999) of Darwin. Thus `kill(pid, 0)` always fails with `ESRCH`.
    private static let endedProcessID: pid_t = 999_999

    /// The process id of `launchd`. It always runs, and a process of a user
    /// cannot send it a signal. Thus `kill(pid, 0)` fails with `EPERM`, not
    /// with `ESRCH`.
    private static let runningProcessID: pid_t = 1

    /// Makes a parent folder that holds one folder named `processID`.
    ///
    /// - Parameter processID: The process id that names the folder.
    /// - Returns: The folder of the process id.
    /// - Throws: When a folder does not create.
    private func makeFolder(ofProcess processID: pid_t) throws -> URL {
        let parent = try scratch.makeDirectory(prefix: "TestRunFolderTests")
        let folder = parent.appendingPathComponent(String(processID), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test("the folder of the run is <temporary directory>/fmm-tests/<pid>")
    func theFolderOfTheRunIsNamedForThisProcess() {
        let expected = FileManager.default.temporaryDirectory
            .appendingPathComponent("fmm-tests", isDirectory: true)
            .appendingPathComponent(String(getpid()), isDirectory: true)
        #expect(TestRunFolder.temporary.path == expected.path)
    }

    @Test("the folder of the run exists after the first use")
    func theFolderOfTheRunExists() {
        #expect(FileManager.default.fileExists(atPath: TestRunFolder.temporary.path))
    }

    @Test("the folder of a process that does not run is removed")
    func theFolderOfAnEndedProcessIsRemoved() throws {
        let folder = try makeFolder(ofProcess: Self.endedProcessID)
        TestRunFolder.removeFoldersOfEndedProcesses(in: folder.deletingLastPathComponent())
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test("the folder of a process that runs stays")
    func theFolderOfARunningProcessStays() throws {
        let folder = try makeFolder(ofProcess: Self.runningProcessID)
        TestRunFolder.removeFoldersOfEndedProcesses(in: folder.deletingLastPathComponent())
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }
}
