// `EnvironmentOperatingSystemTests` — the behavioral suite of the
// `tools.environment.os` verb.
//
// Two groups of tests stand here. The first group injects fixed facts through
// an `EnvironmentContext`, thus each result is equal to the injected facts on
// each machine. The second group reads the real host through the default
// context. Those tests assert only properties that each host has, and no fixed
// host value, thus they do not change from one machine to a different machine.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `tools.environment.os` verb (task `^dkt9h63`).
@Suite("EnvironmentOperatingSystemTests")
struct EnvironmentOperatingSystemTests {

    /// The injected facts. Each value is different from the real value of a
    /// host, thus a test sees if the verb reads the host instead of the
    /// context.
    private static let injected = OperatingSystemResult(
        name: "TestOS",
        version: "9.8.7",
        build: "Version 9.8.7 (Build 1A2b3)",
        architecture: "test64",
        hostName: "test-host.example",
        userName: "tester",
        homeDirectory: "/Users/tester",
        processorCount: 6,
        physicalMemoryBytes: 1_234_567_890,
        locale: "de_CH")

    /// The snippet that calls the verb with no argument and returns its
    /// result.
    private static let osSnippet = "return await tools.environment.os({});"

    /// The pattern of a `major.minor.patch` version. A `Regex` is not
    /// `Sendable`, thus each read makes a new value.
    private static var versionPattern: Regex<Substring> { /\d+\.\d+\.\d+/ }

    // MARK: - Injected facts

    /// With an injected context, the result is equal to the injected facts.
    @Test("with an injected context, the result is equal to the injected facts")
    func withAnInjectedContextTheResultIsEqualToTheInjectedFacts() async throws {
        let verb = OperatingSystem(context: EnvironmentContext(operatingSystem: { Self.injected }))

        let result = try await verb.call(arguments: OperatingSystemArguments())

        #expect(Facts(result) == Facts(Self.injected))
    }

    /// `tools.environment.os({})` renders in a snippet and gives each field of
    /// the injected facts.
    @Test("tools.environment.os({}) renders and gives each field")
    func theSnippetRendersAndGivesEachField() async throws {
        let registry = try MultiTool.Builder()
            .withEnvironment(context: EnvironmentContext(operatingSystem: { Self.injected }))
            .buildRegistry()

        let output = try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: Self.osSnippet))

        let facts = try RunOutput.decoded(Facts.self, from: output)
        #expect(facts == Facts(Self.injected), "the output was \(output)")
    }

    // MARK: - The default context

    /// The default context gives the name of the platform that the code was
    /// built for.
    @Test("the default context gives macOS as the name on macOS")
    func theDefaultContextGivesMacOSAsTheName() async throws {
        let result = try await Self.hostResult()

        #if os(macOS)
            #expect(result.name == "macOS")
        #else
            #expect(!result.name.isEmpty)
        #endif
    }

    /// The default context gives the version as `major.minor.patch`.
    @Test("the default context gives the version as major.minor.patch")
    func theDefaultContextGivesTheVersionAsMajorMinorPatch() async throws {
        let result = try await Self.hostResult()

        #expect(result.version.wholeMatch(of: Self.versionPattern) != nil, "the version was \(result.version)")
    }

    /// The default context gives a host name that is not empty.
    @Test("the default context gives a host name that is not empty")
    func theDefaultContextGivesAHostNameThatIsNotEmpty() async throws {
        let result = try await Self.hostResult()

        #expect(!result.hostName.isEmpty)
    }

    /// The default context gives a processor count and a memory size that
    /// are more than zero.
    @Test("the default context gives a processor count and a memory size that are more than zero")
    func theDefaultContextGivesCountsThatAreMoreThanZero() async throws {
        let result = try await Self.hostResult()

        #expect(result.processorCount > 0)
        #expect(result.physicalMemoryBytes > 0)
    }

    /// The default context reads each fact from its named source of the
    /// process.
    @Test("the default context reads each fact from the process")
    func theDefaultContextReadsEachFactFromTheProcess() async throws {
        let result = try await Self.hostResult()
        let process = ProcessInfo.processInfo

        #expect(result.build == process.operatingSystemVersionString)
        #expect(result.userName == NSUserName())
        #expect(result.homeDirectory == NSHomeDirectory())
        #expect(result.processorCount == process.activeProcessorCount)
        #expect(result.physicalMemoryBytes == Int(clamping: process.physicalMemory))
        #expect(result.locale == Locale.current.identifier)
    }

    /// The default context gives the architecture that the code was built
    /// for.
    @Test("the default context gives the architecture of the build")
    func theDefaultContextGivesTheArchitectureOfTheBuild() async throws {
        let result = try await Self.hostResult()

        #if arch(arm64)
            #expect(result.architecture == "arm64")
        #elseif arch(x86_64)
            #expect(result.architecture == "x86_64")
        #else
            #expect(!result.architecture.isEmpty)
        #endif
    }

    // MARK: - Helpers

    /// Calls the verb over the default context, which reads the real host.
    ///
    /// - Returns: The result of the verb.
    private static func hostResult() async throws -> OperatingSystemResult {
        try await OperatingSystem(context: EnvironmentContext()).call(arguments: OperatingSystemArguments())
    }
}

/// The facts of one result, in a form that `#expect` compares and that a
/// snippet output decodes into.
private struct Facts: Decodable, Equatable {

    /// The platform name.
    let name: String

    /// The version, as `major.minor.patch`.
    let version: String

    /// The text of the version and the build.
    let build: String

    /// The processor architecture.
    let architecture: String

    /// The name of the host.
    let hostName: String

    /// The name of the user.
    let userName: String

    /// The home folder of the user.
    let homeDirectory: String

    /// The number of active processors.
    let processorCount: Int

    /// The size of the physical memory, in bytes.
    let physicalMemoryBytes: Int

    /// The identifier of the locale.
    let locale: String

    /// Copies the facts of one result.
    ///
    /// - Parameter result: The result of the verb.
    init(_ result: OperatingSystemResult) {
        name = result.name
        version = result.version
        build = result.build
        architecture = result.architecture
        hostName = result.hostName
        userName = result.userName
        homeDirectory = result.homeDirectory
        processorCount = result.processorCount
        physicalMemoryBytes = result.physicalMemoryBytes
        locale = result.locale
    }
}
