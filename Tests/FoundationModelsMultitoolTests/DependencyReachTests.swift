import Foundation
import MCP
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

/// The name of the MCP client the reach test constructs, and the name the
/// test reads back from it.
private let mcpClientName = "reach-client"

/// The version string of the MCP client the reach test constructs.
private let mcpClientVersion = "0.0.1"

/// The name of the MCP tool the reach test constructs.
private let mcpToolName = "reach"

/// Reach test for the two packages the capabilities need — `Subprocess` for
/// the shell capability, and `MCP` for the MCP capability.
///
/// Each test calls one symbol of its package. A test that reads the text of
/// `Package.swift` shows only that the manifest holds a line. These tests show
/// that the module resolves, compiles and links.
///
/// The shell test starts `/bin/echo`, which is a local command of the
/// operating system. The MCP test constructs wire types and a client, and it
/// connects to nothing. Neither is an external system, so this suite stays a
/// unit test and needs no integration package.
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

    @Test("MCP.Tool and MCP.Client are reachable from the test target")
    func mcpTypesAreReachable() {
        let tool = MCP.Tool(
            name: mcpToolName,
            description: nil,
            inputSchema: .object(["type": .string("object")])
        )
        let client = MCP.Client(name: mcpClientName, version: mcpClientVersion)

        #expect(tool.name == mcpToolName)
        #expect(tool.inputSchema == .object(["type": .string("object")]))
        #expect(client.name == mcpClientName)
        #expect(client.version == mcpClientVersion)
    }
}
