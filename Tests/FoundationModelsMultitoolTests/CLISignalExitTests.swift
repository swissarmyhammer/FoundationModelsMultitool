import Foundation
import MCPTestServer
import Testing

@testable import MultitoolCLI

/// Covers a stop signal that reaches the built `multitool-cli` process.
///
/// The test starts the built binary as a child process, with
/// `OTEL_EXPORTER_OTLP_ENDPOINT` at an ``OTLPTestCollector`` on the loopback
/// interface. The run is a stub run that loads no model: one `--mcp` option
/// starts `mcp-test-server` in the `stall` mode, which never answers
/// `initialize`. Thus the run stays open in the connect of that server, before
/// the model resolution. The test sends the signal while the run is open. Then
/// it checks the exit code of the process and the spans that the collector got.
///
/// The batch span processor of swift-otel waits 5 seconds before it sends a
/// batch. The run is shorter, thus the run span reaches the collector only
/// through the flush of the exit path.
@Suite("CLISignalExit")
struct CLISignalExitTests {
    /// The product name of the CLI executable, as `Package.swift` declares it.
    private static let cliExecutableName = "multitool-cli"

    /// The OTLP path of the trace export requests.
    private static let tracesPath = "/v1/traces"

    /// The variable that gives the OTLP protocol of the exporters.
    private static let protocolVariable = "OTEL_EXPORTER_OTLP_PROTOCOL"

    /// The protocol that ``OTLPTestCollector`` reads.
    private static let protocolValue = "http/protobuf"

    /// The value of `OTEL_SDK_DISABLED` that keeps the exporters on.
    private static let sdkEnabledValue = "false"

    /// The option of the CLI that starts one MCP server.
    private static let mcpOption = "--mcp"

    /// The name of the `--mcp` server of the stub run.
    private static let stallServerName = "stall"

    /// The program that finds a process by the text of its arguments.
    private static let processFinderPath = "/usr/bin/pgrep"

    /// The flag of ``processFinderPath`` that reads the full argument list.
    private static let fullArgumentsFlag = "-f"

    /// The longest time the test waits for the stub server to start, and then
    /// for the process to exit.
    private static let deadline: Duration = .seconds(30)

    /// The time between two checks of a wait.
    private static let pollInterval: Duration = .milliseconds(50)

    @Test(
        "a stop signal during an open run exports the run span and exits with 128 + the signal number",
        arguments: CLIStopSignal.allCases)
    func stopSignalExportsTheRunSpan(signal: CLIStopSignal) async throws {
        let collector = try await OTLPTestCollector.start()
        defer { collector.stop() }
        let marker = UUID().uuidString
        let process = try Self.makeCLIProcess(endpoint: collector.endpoint, marker: marker)

        try process.run()
        defer { Self.stopIfRunning(process) }
        let stubServer = try Self.stubServerPattern(marker: marker)
        try await Self.waitUntil("the stub server started") { Self.processExists(matching: stubServer) }
        kill(process.processIdentifier, signal.number)
        try await Self.waitUntil("the CLI exited") { !process.isRunning }

        #expect(process.terminationReason == .exit)
        #expect(process.terminationStatus == signal.exitCode)
        let spanName = Data(CLIExitPath.spanName.utf8)
        let traces = collector.bodies(at: Self.tracesPath)
        #expect(traces.contains { $0.range(of: spanName) != nil }, "trace requests: \(traces.count)")
    }

    // MARK: - Fixtures

    /// Makes the process of a stub run of the built CLI.
    ///
    /// - Parameters:
    ///   - endpoint: The OTLP endpoint of the collector.
    ///   - marker: A text that the arguments of the stub server carry, thus
    ///     the test can find that process.
    /// - Returns: The process, not started.
    /// - Throws: What `TestServerLocator` throws when the products directory
    ///   or the test server is not there.
    private static func makeCLIProcess(endpoint: String, marker: String) throws -> Process {
        let process = Process()
        process.executableURL = try TestServerLocator.productsDirectoryURL()
            .appendingPathComponent(cliExecutableName)
        process.arguments = [
            mcpOption, "\(stallServerName)=\(try TestServerLocator.executableURL().path)",
            ServerMode.flagName, ServerMode.stall.rawValue, marker,
        ]
        process.environment = ProcessInfo.processInfo.environment.merging([
            CLITelemetryBackend.endpointVariable: endpoint,
            CLITelemetryBackend.sdkDisabledVariable: sdkEnabledValue,
            protocolVariable: protocolValue,
        ]) { _, test in test }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

    /// The pattern that finds the stub server of one run, and no other
    /// process.
    ///
    /// The arguments of the CLI hold `marker` too. Thus the pattern starts at
    /// the path of the server, which is the first argument of the server and
    /// not of the CLI. Other suites start the same server, thus the pattern
    /// holds `marker` too.
    ///
    /// - Parameter marker: The text that the arguments of the stub server
    ///   carry.
    /// - Returns: An extended regular expression for ``processFinderPath``.
    /// - Throws: What `TestServerLocator.executableURL()` throws.
    private static func stubServerPattern(marker: String) throws -> String {
        let serverPath = try TestServerLocator.executableURL().path
        return "^\(NSRegularExpression.escapedPattern(for: serverPath)) .*\(marker)"
    }

    /// Sends the stop signal of `process` when it still runs, thus a test that
    /// fails leaves no process behind.
    ///
    /// - Parameter process: The CLI process.
    private static func stopIfRunning(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
    }

    /// Whether a process runs whose full argument list matches `pattern`.
    ///
    /// - Parameter pattern: An extended regular expression.
    /// - Returns: `true` when such a process runs.
    private static func processExists(matching pattern: String) -> Bool {
        let finder = Process()
        finder.executableURL = URL(fileURLWithPath: processFinderPath)
        finder.arguments = [fullArgumentsFlag, pattern]
        finder.standardOutput = FileHandle.nullDevice
        finder.standardError = FileHandle.nullDevice
        do {
            try finder.run()
        } catch {
            Issue.record("\(processFinderPath) did not start: \(error)")
            return false
        }
        finder.waitUntilExit()
        return finder.terminationStatus == 0
    }

    /// Waits until `condition` is true, for ``deadline`` at most.
    ///
    /// - Parameters:
    ///   - event: The event the wait is for. The error names it.
    ///   - condition: The check.
    /// - Throws: ``CLISignalExitTestsError/timedOut(_:)`` when the deadline
    ///   ends first, and `CancellationError` when the test is cancelled.
    private static func waitUntil(_ event: String, _ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let end = clock.now + deadline
        while !condition() {
            guard clock.now < end else { throw CLISignalExitTestsError.timedOut(event) }
            try await Task.sleep(for: pollInterval)
        }
    }
}

/// The errors of the fixtures of ``CLISignalExitTests``.
private enum CLISignalExitTestsError: Error {
    /// The wait for the named event ended at the deadline.
    case timedOut(String)
}
