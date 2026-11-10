// `ToolModeBuilderTests` — the `ToolMode` of `MultiTool.Builder` (D128 (d),
// MT-15).
//
// The host sets the mode one time, when it makes the registry. In `sandboxed`
// mode the builder refuses the shell with a loud error, and the model never
// sees a shell. In `open` mode the builder registers each capability, as
// before. The shared check of FoundationModelsExtras runs first, so `open`
// mode in a sandboxed process fails at composition time.
//
// Each test gives a `.fixed(...)` probe. A `.live` probe reads the test
// process, and the result then changes with the machine.

import Foundation
import FoundationModelsExtras
import FoundationModelsHooks
import Testing

@testable import FoundationModelsMultitool

@Suite("ToolModeBuilder", .ownsTemporaryDirectories)
struct ToolModeBuilderTests {
    /// The probe of a process in the App Sandbox.
    private static let sandboxedProcess = SandboxProbe.fixed(true)

    /// The probe of a process out of the App Sandbox.
    private static let openProcess = SandboxProbe.fixed(false)

    /// The name of the temporary directories of this suite.
    private static let directoryName = "tool-mode-builder"

    /// The noun of the shell capability.
    private static let shellNoun = "shell"

    /// The error that `buildRegistry()` gives for the shell in `sandboxed`
    /// mode, as its kind and its name.
    private static let shellNotAvailable = (MultiToolBuilderError.Kind.notAvailable(mode: .sandboxed), shellNoun)

    /// A `sandboxed` builder in a sandboxed process, with each capability
    /// that works in the App Sandbox.
    private static func makeSandboxedBuilder() -> MultiTool.Builder {
        let root = TestSupport.makeTemporaryDirectory(named: directoryName)
        let snapshots = SnapshotStore(directory: TestSupport.makeTemporaryDirectory(named: directoryName))
        return MultiTool.Builder(mode: .sandboxed, sandboxProbe: sandboxedProcess)
            .withFiles(root: root)
            .withGit(root: root)
            .withEnvironment()
            .withWeb(configuration: .keyless)
            .withCapability(SnapshotsCapability(store: snapshots))
    }

    /// Adds the shell capability to `builder`, over a new temporary store.
    ///
    /// - Parameter builder: the builder to add the shell to.
    /// - Returns: `builder`, with the shell capability.
    private static func addShell(to builder: MultiTool.Builder) throws -> MultiTool.Builder {
        let store = TestSupport.makeTemporaryDirectory(named: directoryName)
        return try builder.withShell(
            storeDirectory: store.appendingPathComponent(".shell"),
            defaultWorkingDirectory: TestSupport.makeTemporaryDirectory(named: directoryName))
    }

    /// The nouns of `registry`, in sorted order.
    ///
    /// - Parameter registry: the registry to read.
    /// - Returns: the group of each entry, one time each.
    private static func nouns(of registry: MultiTool.Registry) -> [String] {
        Set(registry.surface.entries.compactMap(\.group)).sorted()
    }

    /// Runs `code` on a `sandboxed` registry that has each capability that
    /// works in the App Sandbox.
    ///
    /// - Parameter code: the `runCode` snippet to run.
    /// - Returns: the output of the snippet.
    private static func runSandboxed(_ code: String) async throws -> String {
        let registry = try makeSandboxedBuilder().buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    @Test("sandboxed mode registers files, git, environment, web and snapshots, and no shell")
    func sandboxedModeRegistersTheSandboxNouns() throws {
        let registry = try Self.makeSandboxedBuilder().buildRegistry()

        #expect(Self.nouns(of: registry) == ["environment", "files", "git", "snapshots", "web"])
    }

    @Test("sandboxed mode with withShell throws notAvailable for the shell")
    func sandboxedModeRefusesTheShell() throws {
        let builder = try Self.addShell(to: Self.makeSandboxedBuilder())

        let error = try #require(throws: MultiToolBuilderError.self) { try builder.buildRegistry() }

        #expect((error.kind, error.name) == Self.shellNotAvailable)
    }

    @Test("a rebuild in sandboxed mode with withShell throws notAvailable for the shell")
    func sandboxedRebuildRefusesTheShell() async throws {
        let source = try Self.addShell(to: Self.makeSandboxedBuilder()).registrySource

        let error = try await #require(throws: MultiToolBuilderError.self) { try await source.rebuildRegistry() }

        #expect((error.kind, error.name) == Self.shellNotAvailable)
    }

    @Test("open mode with withShell builds and has the shell noun")
    func openModeRegistersTheShell() throws {
        let builder = try Self.addShell(to: MultiTool.Builder(mode: .open, sandboxProbe: Self.openProcess))

        let registry = try builder.buildRegistry()

        #expect(Self.nouns(of: registry) == [Self.shellNoun])
    }

    @Test("open mode in a sandboxed process throws openModeInSandbox at buildRegistry")
    func openModeInSandboxFailsAtComposition() {
        let builder = MultiTool.Builder(mode: .open, sandboxProbe: Self.sandboxedProcess).withEnvironment()

        #expect(throws: ToolModeError.openModeInSandbox) { try builder.buildRegistry() }
    }

    @Test(
        "in sandboxed mode a shell alias gets the no such verb answer",
        arguments: ["terminal.runCommand", "bash.run"])
    func sandboxedShellAliasIsNoSuchVerb(path: String) async throws {
        let output = try await Self.runSandboxed(#"return await tools.\#(path)({ command: "echo hi" });"#)

        #expect(output.contains("tools.\(path) \(UnknownToolHint.missingPathPhrase)"), "output was: \(output)")
    }

    @Test("in sandboxed mode the runCode description has no shell text", arguments: [false, true])
    func sandboxedDescriptionNamesNoShell(isDirectMode: Bool) throws {
        let built = try Self.makeSandboxedBuilder().buildRegistry()
        let registry = isDirectMode ? built.directMode() : built

        let description = MultiTool(registry: registry).description

        #expect(!description.contains(Self.shellNoun), "description was: \(description)")
    }
}
