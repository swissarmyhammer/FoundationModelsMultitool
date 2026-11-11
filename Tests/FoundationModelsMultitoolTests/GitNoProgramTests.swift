// `GitNoProgramTests` — each git verb, the files glob and grep, and a snapshot
// list run with no `git` program (task `^b7jrvhc`).
//
// A test in this process can not change its own `PATH`: the suites run in
// parallel, and each one reads the same environment. Thus the test starts the
// `GitNoProgramProbe` executable as a child process, with an environment that
// holds no `git` program. The probe does each check in that environment, and
// gives exit status 0 only when each check passes.

import Foundation
import Subprocess
import System
import Testing

/// The test that runs the git verbs, the files glob and grep, and a snapshot
/// list in a child process that can not find a `git` program.
@Suite("GitNoProgramTests")
struct GitNoProgramTests {

    /// The product name of the probe executable, as `Package.swift` declares
    /// it.
    private static let probeExecutableName = "GitNoProgramProbe"

    /// The maximum number of bytes that the test reads from each output
    /// stream of the probe. The probe writes one short line for each check,
    /// thus this limit is much larger than the output.
    private static let outputLimit = 65_536

    /// The `PATH` of the probe: empty, thus `/usr/bin/env git` finds no
    /// program.
    private static let emptySearchPath = ""

    /// The `DEVELOPER_DIR` of the probe: a folder that does not exist, thus
    /// the `/usr/bin/git` shim finds no developer tools.
    private static let missingDeveloperFolder = "/nonexistent"

    /// The probe passes each check in an environment with an empty `PATH`
    /// and a bad `DEVELOPER_DIR`. `HOME` and `TMPDIR` come from this process:
    /// libgit2 can read `HOME` for its configuration, and the probe makes its
    /// folders below `TMPDIR`.
    @Test("each git verb, the glob, the grep, and a snapshot list pass with no git program")
    func eachCheckPassesWithNoGitProgram() async throws {
        let probe = try TestServerLocator.executableURL(named: Self.probeExecutableName)
        let parentEnvironment = ProcessInfo.processInfo.environment
        let home = try #require(parentEnvironment["HOME"])
        let temporaryFolder = try #require(parentEnvironment["TMPDIR"])

        let result = try await Subprocess.run(
            .path(FilePath(probe.path)),
            environment: .custom([
                "PATH": Self.emptySearchPath,
                "DEVELOPER_DIR": Self.missingDeveloperFolder,
                "HOME": home,
                "TMPDIR": temporaryFolder,
            ]),
            input: .none,
            output: .string(limit: Self.outputLimit),
            error: .string(limit: Self.outputLimit)
        )

        #expect(
            result.terminationStatus == .exited(0),
            """
            The probe failed (\(result.terminationStatus)).
            stdout:
            \(result.standardOutput ?? "")
            stderr:
            \(result.standardError ?? "")
            """)
    }
}
