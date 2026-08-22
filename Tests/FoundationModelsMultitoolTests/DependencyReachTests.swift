import Foundation
import Subprocess
import System
import Testing
import Yams

/// The maximum number of bytes this suite reads from a child process.
///
/// `Subprocess` needs a limit for a collected output. The child writes one
/// short word, so a small limit is sufficient.
private let echoOutputLimit = 4096

/// The path of the command the `Subprocess` test starts.
///
/// The test names the absolute path, because the test must not depend on the
/// `PATH` of the machine that runs it.
private let echoExecutablePath = "/bin/echo"

/// The word the child process writes, and the word the test compares with.
private let echoedWord = "reach"

/// Reach tests for the two packages the shell capability needs — `Subprocess`
/// and `Yams`.
///
/// Each test calls one symbol of one package. A test that reads the text of
/// `Package.swift` shows only that the manifest holds a line. These tests show
/// that the modules resolve, compile and link.
///
/// The `Subprocess` test starts `/bin/echo`, which is a local command of the
/// operating system. It is not an external system, so this test stays a unit
/// test and needs no integration package.
@Suite("DependencyReachTests")
struct DependencyReachTests {
    /// A small configuration record, of the shape the shell policy files use.
    private struct ShellRule: Decodable {
        let command: String
        let allowed: Bool
    }

    @Test("Yams decodes a small YAML document")
    func yamsDecodesASmallDocument() throws {
        let document = """
            command: echo
            allowed: true
            """

        let rule = try YAMLDecoder().decode(ShellRule.self, from: document)

        #expect(rule.command == "echo")
        #expect(rule.allowed)
    }

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
