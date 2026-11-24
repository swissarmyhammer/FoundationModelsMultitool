// `TestRunFolder` — the one folder in the temporary directory that holds each
// test folder and test file of this process.
//
// The design is the same as `TestRunFolder` of FoundationModelsACPAgent. The
// helper stands in the `MultitoolTestSupport` product, thus the unit test
// target, the probe executables and the nested `IntegrationTests` package take
// the same helper.

import Darwin
import Foundation
import Synchronization

/// The folder of the test folders and test files of this process.
///
/// Each test folder and test file goes into the folder of this process, not
/// into the top of the temporary directory. Before this folder, each run of
/// the suite left folders such as `multitool-stub-<UUID>` at the top of
/// `$TMPDIR`, and they collected run after run.
///
/// - The process removes its folder when it exits (`atexit`).
/// - A process that stops before its exit leaves its folder. The first use in
///   a subsequent process removes each folder whose process does not run now.
public enum TestRunFolder {

    /// The name of the parent of the folders of each process.
    private static let parentName = "fmm-tests"

    /// The parent of the folders of each process:
    /// `<temporary directory>/fmm-tests`.
    private static let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent(parentName, isDirectory: true)

    /// The folder of this process: `<temporary directory>/fmm-tests/<pid>`.
    ///
    /// Use it in place of `FileManager.default.temporaryDirectory` to make a
    /// test folder or a test file. The URL keeps the spelling of the process
    /// temporary directory (`/var/...` on macOS).
    public static let temporary: URL = makeFolder()

    /// The folders that the removal at the exit removes.
    private static let folders = Mutex<[URL]>([])

    /// Registers the removal at the exit one time.
    private static let registerRemovalAtExit: Void = {
        atexit {
            for folder in TestRunFolder.folders.withLock({ $0 }) {
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }()

    /// Makes the folder of this process in ``parent``, removes the folders of
    /// the processes that do not run now, and registers the removal at the
    /// exit.
    ///
    /// - Returns: The folder.
    private static func makeFolder() -> URL {
        let folder = parent.appendingPathComponent(String(getpid()), isDirectory: true)
        removeFoldersOfEndedProcesses(in: parent)
        try? FileManager.default.removeItem(at: folder)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folders.withLock { $0.append(folder) }
        registerRemovalAtExit
        return folder
    }

    /// Removes the folder of each process that does not run now.
    ///
    /// A folder whose name is not a process id stays. The folder of this
    /// process stays. The folder of a process that runs, but that this
    /// process cannot send a signal to (`EPERM`), stays.
    ///
    /// - Parameter parent: The parent of the folders of each process.
    static func removeFoldersOfEndedProcesses(in parent: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        for name in names {
            guard let pid = pid_t(name), pid > 0, pid != getpid() else { continue }
            if kill(pid, 0) != 0 && errno == ESRCH {
                try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
            }
        }
    }
}
