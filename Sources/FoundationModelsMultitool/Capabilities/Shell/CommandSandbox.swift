// `CommandSandbox` — the seam between "what a command can touch" and "what
// process starts".
//
// On macOS, confinement puts the child in a Seatbelt profile that the kernel
// applies, through `/usr/bin/sandbox-exec`. That binary carries a deprecation
// notice in the manual pages of Apple, and Apple gives no public replacement.
// Thus this package makes no promise about `sandbox-exec`: **the abstraction is
// the promise, and the binary is not.** Each caller above this protocol reads
// one sentence only — "here is the shell I want to run; give me back the
// executable and the arguments to start". A new mechanism from the operating
// system goes in behind that sentence, and no caller changes shape.
//
// Nothing in this file knows the Seatbelt Profile Language, the `-D`
// parameters, or how a profile compiles. Those come with the confining
// implementation. What stands here is the shape of the exchange
// (`SandboxedInvocation`), the contract each implementation must obey
// (`CommandSandbox`), and the meaning of "no confinement at all"
// (`UnconfinedSandbox`).
//
// `CommandSandbox` and `SandboxedInvocation` are public, and narrowly so: they
// are the surface a host configures. Whether a session is confined — and to
// which directories — is the decision of the host, and not the decision of this
// package. Thus a capability that is built with no sandbox confines nothing.
//
// `UnconfinedSandbox` stays internal. "No confinement" is the absent sandbox at
// the opt-in, thus no code outside this module needs the identity value.

/// The decoration of one spawn: the executable to start, and the full argument
/// list to start it with, as `CommandSandbox.wrap` gives them back.
///
/// This is the WHOLE shape of the spawn, and not a set of extra arguments to
/// splice in, because confinement replaces the executable. A run with no
/// confinement starts `/bin/sh` with `["-c", command]`. A confined run starts
/// the wrapper binary with its own parameters, then the profile, and then that
/// same shell invocation at the end of the argument list. A caller applies the
/// result as it is, and it needs no knowledge of which of the two it received.
///
/// The value carries no environment, no working directory, and no platform
/// options. Those belong to the caller, and confinement does not change them.
/// A wrapper starts its target in place — the same process identifier — thus
/// the teardown of the process group, the registry of processes, and the detach
/// behavior all stay as they are.
public struct SandboxedInvocation: Sendable, Equatable {

    /// The absolute path of the executable to start: the shell itself when
    /// there is no confinement, and the wrapper binary when there is.
    public let executable: String

    /// The full argument list to start `executable` with, argv[0] excluded.
    ///
    /// For a run with no confinement this is the arguments of the shell as they
    /// came in, for example `["-c", command]`. For a confined run it is the
    /// arguments of the wrapper, and then that same shell invocation at the
    /// end.
    public let arguments: [String]

    /// Makes a spawn decoration.
    ///
    /// Written out, and not left to the compiler, because a memberwise
    /// initializer that the compiler makes is `internal` also on a public type.
    /// A `CommandSandbox` written outside this module would then name a type it
    /// cannot build.
    ///
    /// - Parameters:
    ///   - executable: The absolute path of the executable to start.
    ///   - arguments: The full argument list to start it with, argv[0]
    ///     excluded.
    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

/// Decorates a shell invocation with the confinement an implementation applies,
/// and gives back the executable and the arguments to start.
///
/// An implementation is a value, and not a session: `wrap` starts no process.
/// It builds a description and it gives that description back. Thus the
/// decision about confinement is testable with no command, and the spawn itself
/// stays in the one place that already owns it.
///
/// **Precondition on each path: each directory a caller gives to `wrap` must
/// already have each symbolic link resolved.** A caller puts each path through
/// `realpath(3)` or `URL.resolvingSymlinksInPath()` BEFORE it calls `wrap`.
/// This protocol resolves no path, and an implementation can use each path as
/// it came in. The requirement is not a matter of style: Seatbelt matches the
/// path of the vnode that the kernel resolved, and its subpath match resolves
/// no symbolic link. Measured: a profile that is granted the raw `$TMPDIR`
/// (`/var/folders/…/T`) REFUSES a write below it with "Operation not
/// permitted", and the same profile that is granted the resolved
/// `/private/var/folders/…/T` allows that write. `/tmp` against `/private/tmp`
/// behaves the same way. A path that is not resolved thus makes a sandbox that
/// quietly grants less than it appears to grant, and the contract stands here,
/// on the abstraction, thus each implementation agrees.
public protocol CommandSandbox: Sendable {

    /// Proves that this sandbox can confine a command with these directories,
    /// and throws when it cannot. It runs before any command starts.
    ///
    /// The requirement is there because a confinement failure that a caller
    /// finds at spawn time is not recoverable in a form the model can read: a
    /// throw from `wrap` travels out through the body of the run, and each
    /// layer above erases it to a string. Thus the shell capability calls this
    /// ahead of the run, while the error of an implementation still has its
    /// type, and it makes readable text from the diagnosis.
    ///
    /// **What that text covers is narrow, and an implementor must plan for
    /// it.** The capability recognizes the error type of the confining
    /// implementation this package ships, and it gives corrective text for that
    /// type. A thrown value of any other type travels up, is erased, and stops
    /// the turn exactly as a throw at spawn time does. Thus a conformer written
    /// outside this module that wants its refusal to reach the model as
    /// readable text throws that same type, and a conformer that throws an
    /// error type of its own chooses the stop.
    ///
    /// An implementation with nothing to prove ahead of time — one whose `wrap`
    /// cannot fail, or whose failures are already cheap to reach — takes the
    /// default below, which does nothing, and it costs such a caller nothing.
    ///
    /// Each failure, with text or without it, means the same thing to a caller:
    /// **do not run the command.** There is no path from a preflight that
    /// failed to a spawn with no confinement.
    ///
    /// - Parameters:
    ///   - workingDirectory: The absolute directory the command will run in,
    ///     **with each symbolic link already resolved** — see the precondition
    ///     on this protocol.
    ///   - temporaryDirectory: The absolute temporary directory the command can
    ///     use, **with each symbolic link already resolved** — see the
    ///     precondition on this protocol.
    /// - Throws: When the confinement cannot be built or applied for these
    ///   inputs.
    func preflight(workingDirectory: String, temporaryDirectory: String) async throws

    /// Gives back the executable and the arguments to start, so that
    /// `shellPath shellArguments` runs under the confinement of this sandbox.
    ///
    /// - Parameters:
    ///   - shellPath: The absolute path of the shell to run, for example
    ///     `/bin/sh`.
    ///   - shellArguments: The arguments of that shell, for example
    ///     `["-c", command]`.
    ///   - workingDirectory: The absolute directory the command runs in,
    ///     **with each symbolic link already resolved** — see the precondition
    ///     on this protocol.
    ///   - temporaryDirectory: The absolute temporary directory the command can
    ///     use, **with each symbolic link already resolved** — see the
    ///     precondition on this protocol.
    /// - Returns: The spawn decoration to apply, as it is, to the configuration
    ///   of the child.
    /// - Throws: When the confinement cannot be built for these inputs.
    func wrap(
        shellPath: String,
        shellArguments: [String],
        workingDirectory: String,
        temporaryDirectory: String
    ) throws -> SandboxedInvocation
}

extension CommandSandbox {

    /// Proves nothing, because there is nothing to prove ahead of time.
    ///
    /// This is the default an implementation takes when it states no
    /// `preflight` of its own. A sandbox whose `wrap` cannot fail has no
    /// configuration that a check could find broken before a command runs, thus
    /// the honest preflight is the empty one. The default also keeps the
    /// requirement from breaking the source of a conformer written outside this
    /// module, and it keeps `UnconfinedSandbox` — whose whole purpose is to be
    /// the same as no sandbox at all — free of a check it would always pass.
    ///
    /// - Parameters:
    ///   - workingDirectory: Not read — nothing is proved.
    ///   - temporaryDirectory: Not read — nothing is proved.
    public func preflight(workingDirectory: String, temporaryDirectory: String) async throws {}
}

/// The identity `CommandSandbox`: no confinement at all.
///
/// `wrap` gives back the shell invocation exactly as it came in, and it reads
/// neither directory. That is what "unconfined" means, said as a value and not
/// as an absent one. It is the meaning the other implementations stand against,
/// and the seam tests exercise it.
///
/// It rebuilds, byte for byte, the spawn a runner with no sandbox makes. Thus a
/// runner that goes through this implementation behaves as it did before: the
/// seam carries the load, and no behavior a caller can see changes.
struct UnconfinedSandbox: CommandSandbox {

    /// Gives back `shellPath` and `shellArguments` unchanged.
    ///
    /// - Parameters:
    ///   - shellPath: The absolute path of the shell to run.
    ///   - shellArguments: The arguments of that shell.
    ///   - workingDirectory: Not read — no confinement is applied.
    ///   - temporaryDirectory: Not read — no confinement is applied.
    /// - Returns: `SandboxedInvocation(executable: shellPath, arguments:
    ///   shellArguments)`.
    func wrap(
        shellPath: String,
        shellArguments: [String],
        workingDirectory: String,
        temporaryDirectory: String
    ) -> SandboxedInvocation {
        SandboxedInvocation(executable: shellPath, arguments: shellArguments)
    }
}
