import Foundation
import Subprocess
import System
import Testing

/// The maximum number of bytes this suite reads from a child process.
///
/// `Subprocess` needs a limit for a collected output. The child writes one
/// short word, so a small limit is sufficient.
private let echoOutputLimit = 4096

/// The path of the command the test starts.
///
/// The test names the absolute path, because the test must not depend on the
/// `PATH` of the machine that runs it.
private let echoExecutablePath = "/bin/echo"

/// The word the child process writes, and the word the test compares with.
private let echoedWord = "reach"

/// Reach test for the one package the shell capability needs — `Subprocess`.
///
/// The test calls one symbol of that package. A test that reads the text of
/// `Package.swift` shows only that the manifest holds a line. This test shows
/// that the module resolves, compiles and links.
///
/// It starts `/bin/echo`, which is a local command of the operating system. It
/// is not an external system, so this test stays a unit test and needs no
/// integration package.
@Suite("DependencyReachTests")
struct DependencyReachTests {
    @Test("Subprocess runs /bin/echo and collects what the child wrote")
    func subprocessRunsEcho() async throws {
        let result = try await Subprocess.run(
            .path(FilePath(echoExecutablePath)),
            arguments: Arguments([echoedWord]),
            input: .none,
            output: .string(limit: echoOutputLimit),
            error: .discarded
        )

        #expect(result.terminationStatus == .exited(0))
        #expect(result.standardOutput?.trimmingCharacters(in: .newlines) == echoedWord)
    }
}
