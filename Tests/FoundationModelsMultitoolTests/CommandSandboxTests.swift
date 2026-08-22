import Testing

import FoundationModelsMultitool

/// Unit tests for the value semantics of `SandboxedInvocation` — the value that
/// `CommandSandbox.wrap` gives back.
///
/// This file imports `FoundationModelsMultitool` PLAINLY — it carries no
/// `@testable` — thus each name it uses must be genuinely public, as a host
/// sees it.
///
/// `SandboxedInvocation` is `Equatable`, and a caller compares one against
/// another to tell one spawn from another. Thus the comparison must read BOTH
/// stored properties. A comparison that read the executable alone would call
/// two different argument lists the same, and a comparison that read the
/// arguments alone would call a confined spawn and an unconfined spawn the
/// same. Each of the two mistakes hides the whole confinement.
@Suite("SandboxedInvocation value semantics")
struct CommandSandboxTests {

    /// The executable of the invocation each test compares against.
    private static let executable = "/bin/sh"

    /// The arguments of that invocation.
    private static let arguments = ["-c", "echo hi"]

    /// Another executable: the wrapper that a confined spawn starts.
    private static let otherExecutable = "/usr/bin/sandbox-exec"

    /// Another argument list, of the same length as `arguments`.
    private static let otherArguments = ["-c", "echo bye"]

    /// The invocation each test compares against.
    private static let invocation = SandboxedInvocation(
        executable: executable, arguments: arguments)

    @Test("one executable and one argument list make one invocation")
    func equalFieldsMakeEqualInvocations() {
        #expect(
            Self.invocation
                == SandboxedInvocation(executable: Self.executable, arguments: Self.arguments))
    }

    @Test("an invocation with other arguments is a different invocation")
    func otherArgumentsMakeADifferentInvocation() {
        #expect(
            Self.invocation
                != SandboxedInvocation(
                    executable: Self.executable, arguments: Self.otherArguments))
    }

    @Test("an invocation with another executable is a different invocation")
    func anotherExecutableMakesADifferentInvocation() {
        #expect(
            Self.invocation
                != SandboxedInvocation(
                    executable: Self.otherExecutable, arguments: Self.arguments))
    }
}
