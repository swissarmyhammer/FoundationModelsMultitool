import Testing

import FoundationModelsMultitool

/// Pins the sandbox seam as a host sees it.
///
/// This file imports `FoundationModelsMultitool` PLAINLY — it carries no
/// `@testable` — thus each name it uses must be genuinely public. A protocol, a
/// structure, an initializer, or a property that goes back to `internal` stops
/// this file from building, and that is the point of the plain import.
///
/// Nothing here starts a command. What is under test is the shape of the
/// exchange: a host writes a conformer of its own, that conformer builds the
/// value the requirement gives back, and the host reads the value.
@Suite("Sandbox seam surface")
struct SandboxSurfaceTests {

    /// The shell each test wraps.
    private static let shellPath = "/bin/sh"

    /// The arguments of that shell.
    private static let shellArguments = ["-c", "echo hi"]

    /// The working directory each test gives. It is already symlink-resolved,
    /// as the protocol requires of each caller.
    private static let workingDirectory = "/private/tmp/a"

    /// The temporary directory each test gives, symlink-resolved for the same
    /// reason.
    private static let temporaryDirectory = "/private/tmp/t"

    /// The value `RearrangingSandbox` gives back for the constants above.
    private static let rearrangedInvocation = SandboxedInvocation(
        executable: RearrangingSandbox.executable,
        arguments: [workingDirectory, shellPath] + shellArguments)

    /// Wraps the constants above with `sandbox`.
    ///
    /// The parameter is an existential, thus each call goes over the witness
    /// table: `wrap` is a requirement of the protocol, and a host reaches it
    /// through the protocol and not through a concrete type.
    ///
    /// - Parameter sandbox: The sandbox to wrap with.
    /// - Returns: The spawn decoration that `sandbox` gives back.
    /// - Throws: What `sandbox` throws.
    private func invocation(from sandbox: any CommandSandbox) throws -> SandboxedInvocation {
        try sandbox.wrap(
            shellPath: Self.shellPath,
            shellArguments: Self.shellArguments,
            workingDirectory: Self.workingDirectory,
            temporaryDirectory: Self.temporaryDirectory)
    }

    /// Runs the preflight of `sandbox` over the constants above.
    ///
    /// The parameter is an existential for the reason `invocation(from:)`
    /// states: a `preflight` that dropped out of the protocol would make the
    /// call reach the empty default of the extension.
    ///
    /// - Parameter sandbox: The sandbox to prove.
    /// - Throws: What `sandbox` throws.
    private func preflight(_ sandbox: any CommandSandbox) async throws {
        try await sandbox.preflight(
            workingDirectory: Self.workingDirectory, temporaryDirectory: Self.temporaryDirectory)
    }

    @Test("a host outside the module conforms to CommandSandbox and builds the value it gives back")
    func outOfModuleConformerBuildsAnInvocation() throws {
        let invocation = try invocation(from: RearrangingSandbox())

        #expect(invocation == Self.rearrangedInvocation)
    }

    @Test("a host reads back the executable and the arguments of a spawn decoration")
    func invocationShowsItsFields() {
        let invocation = SandboxedInvocation(
            executable: Self.shellPath, arguments: Self.shellArguments)

        #expect(invocation.executable == Self.shellPath)
        #expect(invocation.arguments == Self.shellArguments)
    }

    @Test("a conformer that states no preflight gets a check that proves nothing")
    func inheritedPreflightProvesNothing() async throws {
        let sandbox = RearrangingSandbox()

        // `RearrangingSandbox` states no `preflight` of its own, thus this call
        // reaches the default in the protocol extension. The default proves
        // nothing, thus it passes and it changes nothing about the next `wrap`.
        try await preflight(sandbox)

        #expect(try invocation(from: sandbox) == Self.rearrangedInvocation)
    }

    @Test("a host states a preflight of its own, and a refusal reaches the caller")
    func hostPreflightRefusesAheadOfTheRun() async {
        await #expect(throws: ConfinementRefused.self) {
            try await preflight(RefusingSandbox())
        }
    }

    @Test("a refusal from wrap reaches the caller with the type the host gave it")
    func hostWrapRefusalReachesTheCaller() {
        // `wrap` is a throwing requirement, thus a host that cannot build the
        // confinement says so, and its own error type comes out of the module
        // unchanged.
        #expect(throws: ConfinementRefused.self) {
            try invocation(from: RefusingSandbox())
        }
    }
}

/// The refusal that `RefusingSandbox` throws.
///
/// A type of this file, and not a type of the module, because what the two
/// refusal tests pin is that the refusal of the HOST reaches the caller with
/// its own type.
private struct ConfinementRefused: Error, Equatable, Sendable {}

/// A `CommandSandbox` written outside the module — this file carries no
/// `@testable` — that rearranges the invocation it receives.
///
/// The value it gives back is deliberately different from its input: another
/// executable, and the working directory in front of the shell. Thus a test
/// tells the answer from the question.
///
/// It states no `preflight`, thus it also stands for the conformer that takes
/// the default of the protocol extension.
private struct RearrangingSandbox: CommandSandbox {

    /// The executable this sandbox names in place of the shell.
    static let executable = "/usr/bin/env"

    /// Gives back a rearranged invocation.
    ///
    /// - Parameters:
    ///   - shellPath: The absolute path of the shell to run.
    ///   - shellArguments: The arguments of that shell.
    ///   - workingDirectory: Put in front of the shell in the argument list.
    ///   - temporaryDirectory: Not used.
    /// - Returns: `executable`, and the rearranged argument list.
    func wrap(
        shellPath: String,
        shellArguments: [String],
        workingDirectory: String,
        temporaryDirectory: String
    ) -> SandboxedInvocation {
        SandboxedInvocation(
            executable: Self.executable, arguments: [workingDirectory, shellPath] + shellArguments)
    }
}

/// A `CommandSandbox` that refuses each command, and refuses it early.
///
/// It states a `preflight` of its own, thus it pins that `preflight` is a
/// requirement of the protocol and that a host can answer it.
private struct RefusingSandbox: CommandSandbox {

    /// Throws `ConfinementRefused` before any command starts.
    ///
    /// - Parameters:
    ///   - workingDirectory: Not used.
    ///   - temporaryDirectory: Not used.
    /// - Throws: `ConfinementRefused`, always.
    func preflight(workingDirectory: String, temporaryDirectory: String) async throws {
        throw ConfinementRefused()
    }

    /// Throws `ConfinementRefused`, because this sandbox builds no confinement.
    ///
    /// - Parameters:
    ///   - shellPath: Not used.
    ///   - shellArguments: Not used.
    ///   - workingDirectory: Not used.
    ///   - temporaryDirectory: Not used.
    /// - Returns: Nothing. The call always throws.
    /// - Throws: `ConfinementRefused`, always.
    func wrap(
        shellPath: String,
        shellArguments: [String],
        workingDirectory: String,
        temporaryDirectory: String
    ) throws -> SandboxedInvocation {
        throw ConfinementRefused()
    }
}
