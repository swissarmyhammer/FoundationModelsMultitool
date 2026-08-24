// `SeatbeltSandbox` — the `CommandSandbox` of macOS. It bounds where a command
// that starts can WRITE and where it can DELETE. It does that with a Seatbelt
// profile that the kernel applies, through `/usr/bin/sandbox-exec`, around the
// shell.
//
// The goal is narrow on purpose: bound where a command writes or deletes, thus
// the shell capability cannot break things. Nothing more.
//
// This layer is the ONLY gate. No layer above it examines the command text, and
// no layer above it refuses a command before it runs. Thus what the profile
// does not bound, nothing bounds:
//
// - Each read is free, everywhere.
// - The network is fully open.
//
// Read those two together, because a reader must not think this sandbox covers
// more than it does: a command can read each file the user can read, and it can
// send that file anywhere. Destruction is bounded. Reading and exfiltration are
// not. To change either one, change the profile — `profile(for:)` below — and
// no other place.
//
// Each shape decision below was measured against real `sandbox-exec` runs on
// Darwin 27.0.0 (2026-08-02). The reason for each one stands on the declaration
// it belongs to, thus the next maintainer does not learn it again by breaking
// the profile.

import Foundation

/// The `realpath(3)` of `path`, or `path` as it is when it cannot resolve —
/// most often because it does not exist yet.
///
/// **The one resolver of this module, and the one each caller must use** to
/// answer the path precondition of `CommandSandbox`. Seatbelt matches the path
/// of the vnode that the kernel resolved, and `realpath(3)` gives that path.
/// The resolver of Foundation runs the other way for this purpose:
/// `URL(fileURLWithPath: "/private/tmp").resolvingSymlinksInPath().path` gives
/// back `/tmp`, which is the form Seatbelt cannot match. Thus a second copy of
/// this step can name a different path than the confinement enforces, and
/// nothing reports the disagreement. There is one copy, and a test calls it as
/// the sandbox does.
///
/// - Parameter path: The path to resolve.
/// - Returns: The resolved path, or `path` unchanged.
func resolvedPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
}

/// A `CommandSandbox` that bounds each write and each delete to a fixed set of
/// root directories, with a macOS Seatbelt profile that
/// `/usr/bin/sandbox-exec` applies.
///
/// The profile is a STATIC template (`profile(for:)`). The one thing that
/// changes with the configuration is the COUNT of the `(subpath (param "…"))`
/// grants on its single `file-write*` line. A path value never appears in
/// profile text. It travels only as a `-D NAME=value` parameter, and the
/// profile names that parameter. That is what makes a hostile path value
/// harmless: `ROOT0=/tmp") (allow default) (deny file-write* (subpath
/// "/nonexistent` was measured NOT to open the policy, because the value is
/// never read as profile source.
///
/// What follows from that is a hard invariant: **the count of the `ROOTi` and
/// `EXTRA_Wi` references in the profile must agree exactly with the count of
/// the `-D` pairs.** A `param` that the profile names and that no `-D` supplies
/// is a compilation failure — exit 65, `sandbox-exec: invalid data type of path
/// filter; expected pattern, got boolean`. Thus `profile(for:)` and `wrap` make
/// both sides from the same `Options`, BY COUNT, and they must stay that way.
///
/// **Each path must arrive with each symbolic link resolved**, as the
/// precondition on `CommandSandbox` states. Seatbelt matches the path of the
/// vnode that the kernel resolved, and its `subpath` match resolves no symbolic
/// link, thus a grant for `/tmp/x` never matches a kernel that sees
/// `/private/tmp/x`. `wrap` resolves no path a second time, and that is on
/// purpose: resolution belongs to the caller, one time, with `resolvedPath`,
/// before the path arrives here.
///
/// **A host that is itself in the App Sandbox cannot get more confinement, and
/// that fails closed.** To put Seatbelt inside an App Sandbox does not work in
/// general — the wrapper cannot apply a second profile — and the answer of this
/// package is to let that failure stand: `preflight` runs its canary before any
/// command starts, the canary fails, `profileRejected` comes out, and the
/// command does not run. Not unconfined, not with a warning, and not skipped. A
/// host that asked for confinement and cannot have it gets an error, and never
/// a command that quietly ran outside the sandbox it configured.
public struct SeatbeltSandbox: CommandSandbox {

    /// The write confinement: which directories a confined command can write
    /// to, and delete within.
    ///
    /// This is configuration the host supplies, and it is fixed when the
    /// `SeatbeltSandbox` value is made. A `workingDirectory` of one call never
    /// widens it — see `wrap`.
    ///
    /// There is deliberately no set of extra read paths, and no control of the
    /// network. Each read is free everywhere, thus there is nothing to let
    /// back in, and the network is always open. To add either one would go
    /// against the settled design: this is not a read policy, and it is not a
    /// network policy.
    public struct Options: Sendable, Equatable {

        /// The whole set of directories that get write and delete access — the
        /// roots of the whole session, and not the working directory of the
        /// current call alone.
        ///
        /// Plural on purpose: one session can legitimately cover several
        /// approved directories, such as several git worktrees or a workspace
        /// of several repositories. Each of them is writable at the same time,
        /// and an operation that crosses from one root to another is included.
        /// Measured: `cp rootA/w.txt rootB/copied.txt` succeeds, while a write
        /// into a neighbouring directory that no root covers fails with
        /// `Operation not permitted`.
        ///
        /// Each entry becomes one `ROOTi` grant, AND one directory that the
        /// working directory of a call can sit inside.
        public let writableRoots: [String]

        /// Extra write grants beyond the root set, for one file or one
        /// directory a host needs writable without a grant of a whole root.
        ///
        /// Each one becomes an `EXTRA_W0`, `EXTRA_W1`, … parameter on the same
        /// `file-write*` line. They do NOT widen containment: a working
        /// directory must still sit inside `writableRoots`.
        public let extraWritePaths: [String]

        /// Makes a write confinement.
        ///
        /// Each entry of each list goes through `resolvedPath` here, because
        /// Seatbelt matches the path the kernel resolved, and because
        /// containment compares a working directory against these roots.
        /// Without that step a host that configures `/tmp/repo` — a symbolic
        /// link to `/private/tmp/repo` — has each command refused as "outside
        /// the configured roots", because the caller resolves the working
        /// directory while the root stayed unresolved. An entry that does not
        /// exist yet stays as it is: `realpath` cannot resolve it, and to drop
        /// it would quietly make the grant smaller.
        ///
        /// - Parameters:
        ///   - writableRoots: The directories to give write and delete access
        ///     to. An empty list means the working directory of THIS process,
        ///     which is read here, at construction, thus the granted set can
        ///     never move with a later `chdir`. `getcwd(3)` already gives back
        ///     a path with each symbolic link resolved, thus it answers the
        ///     path precondition of `CommandSandbox` as it is.
        ///   - extraWritePaths: Extra write grants beyond the root set.
        public init(writableRoots: [String] = [], extraWritePaths: [String] = []) {
            let roots =
                writableRoots.isEmpty
                ? [FileManager.default.currentDirectoryPath] : writableRoots
            self.writableRoots = roots.map(resolvedPath)
            self.extraWritePaths = extraWritePaths.map(resolvedPath)
        }
    }

    /// The write confinement this sandbox applies.
    public let options: Options

    /// The wrapper binary to start.
    ///
    /// It can be set, thus a test points it at a path that does not exist and
    /// watches the sandbox fail closed. A production value never changes it.
    /// It stays out of the public initializer for that same reason: a host
    /// configures WHERE a write can land, and not which binary applies that.
    var executablePath: String = "/usr/bin/sandbox-exec"

    /// Profile text to send in place of the text of `profile(for:)`, or `nil`
    /// — the default — to send the profile that this sandbox makes.
    ///
    /// It can be set, thus a test gives `sandbox-exec` a profile it refuses to
    /// compile and watches the typed refusal come back. A production value
    /// never sets it. It covers `preflight` and `wrap` alike, exactly so that
    /// the canary can never prove a profile that is not the profile a command
    /// runs under.
    var profileOverride: String?

    /// How `preflight` starts its canary.
    ///
    /// It can be set, thus a test counts the canary spawns, or answers with a
    /// failure it wrote, and it needs no child process. A production value
    /// never changes it.
    var canarySpawn: CanarySpawn = liveCanarySpawn

    /// The latch that keeps a canary that passed from running again.
    ///
    /// A reference type, thus each copy of this structure shares one gate and
    /// the canary costs one spawn for each sandbox a host builds, and not one
    /// for each copy. See `CanaryGate` for why that cannot be a `Mutex` stored
    /// here, and for exactly what a latch covers and does not cover.
    let canaryGate = CanaryGate()

    /// Makes a Seatbelt sandbox that bounds each write to the roots of
    /// `options`.
    ///
    /// Written out, and not left to the compiler, because a memberwise
    /// initializer that the compiler makes is `internal` also on a public
    /// type, thus a host could not build one — and because that initializer
    /// would also show `executablePath`.
    ///
    /// - Parameter options: The write confinement to apply. The default is
    ///   `Options()`, which is the working directory of this process as the
    ///   single writable root.
    public init(options: Options = Options()) {
        self.options = options
    }

    // MARK: - The names of the profile parameters

    /// The name prefix of the grants of `writableRoots`: `ROOT0`, `ROOT1`, …
    private static let rootParameterPrefix = "ROOT"

    /// The name of the parameter that carries the temporary directory of one
    /// call.
    private static let temporaryDirectoryParameter = "TMPDIR"

    /// The name prefix of the grants of `extraWritePaths`: `EXTRA_W0`, …
    private static let extraWriteParameterPrefix = "EXTRA_W"

    /// The wrapper option that carries one `NAME=value` parameter.
    private static let parameterOption = "-D"

    /// The wrapper option that carries the profile text.
    private static let profileOption = "-p"

    // MARK: - The profile

    /// The whole profile text for `options`: the static template, and one
    /// `(subpath (param "…"))` grant for each write target.
    ///
    /// Each read is free and the network is always open. The one thing this
    /// profile bounds is writing and deleting. These rules are the whole gate,
    /// thus this is the place to change what a command can read, and the place
    /// to change what a command can reach on the network.
    ///
    /// The rule set is small, and no line of it is arbitrary. Each one carries
    /// its load, and each one was proved by running the profile:
    ///
    /// - `(deny default)` on its own cannot even start the shell:
    ///   `sandbox-exec -p '(version 1)(deny default)' /bin/sh -c 'echo hi'`
    ///   fails with `execvp() of '/bin/sh' failed: Operation not permitted`,
    ///   exit 71. The `process-fork`, `process-exec*`, `sysctl-read`,
    ///   `mach-lookup` and `signal` allowances are the least that lets
    ///   `/bin/sh` start and make children.
    /// - `(allow file-read*)` is unconditional **by design**, and there is no
    ///   `deny file-read*` line of any kind. Reads that nothing bounds are
    ///   what let git and the other tools that read dotfiles work, with no
    ///   exception written for each tool. It is recorded here thus nobody
    ///   tries read confinement again without reason: an earlier experiment
    ///   with a strict list of readable directories (`/usr`, `/bin`,
    ///   `/System`, …) made `/bin/sh` stop at the start of `dyld` — `SIGABRT`,
    ///   exit 134.
    /// - `/dev/null` needs a grant of its own, or a plain `cmd >/dev/null`
    ///   fails with "/dev/null: Operation not permitted".
    /// - **`file-write*` covers deletion.** `rm` on a file that already exists
    ///   outside each granted root ends with 1 and `Operation not permitted`,
    ///   and the file stays; `rm` inside a granted root succeeds. No rule
    ///   about unlinking is necessary.
    /// - `(allow network*)` and `(allow system-socket)` are unconditional:
    ///   `curl` to a public host gives 200 inside the sandbox. Beside the free
    ///   reads above, that is what a reader must weigh: a command can read each
    ///   file the user can read, and it can send that file anywhere. Nothing
    ///   above this profile bounds either half. Destruction is bounded, and
    ///   reading and exfiltration are not.
    ///
    /// - Parameter options: The write confinement to render.
    /// - Returns: The profile source to give to `sandbox-exec -p`.
    static func profile(for options: Options) -> String {
        let writeGrants =
            (options.writableRoots.indices.map { "\(rootParameterPrefix)\($0)" }
            + [temporaryDirectoryParameter]
            + options.extraWritePaths.indices.map { "\(extraWriteParameterPrefix)\($0)" })
            .map { "(subpath (param \"\($0)\"))" }
            .joined(separator: " ")

        return """
            (version 1)
            (deny default)
            (allow process-fork)
            (allow process-exec*)
            (allow sysctl-read)
            (allow mach-lookup)
            (allow signal (target same-sandbox))
            (allow file-read*)
            (allow file-write-data (literal "/dev/null") (literal "/dev/zero"))
            (allow file-write* \(writeGrants))
            (allow network*)
            (allow system-socket)
            """
    }

    // MARK: - Wrapping

    /// Gives back the `sandbox-exec` invocation that runs
    /// `shellPath shellArguments` bounded to the writable roots of `options`.
    ///
    /// Two checks run before any argument is built, and both fail closed. A
    /// confinement that cannot be built is an error, and never a run with no
    /// confinement at all:
    ///
    /// 1. `workingDirectory` must sit inside at least one configured root.
    ///    That closes a real hole, and it does not merely say the grant again:
    ///    the value comes from a parameter that the MODEL writes, and no layer
    ///    above this one examines it. If the working directory of one call
    ///    could add grants, a model that chose `/` would give itself the whole
    ///    file system. Thus the check proves that the directory of the call
    ///    sits inside the root set that is already configured, and it never
    ///    adds it. The granted set is exactly `options.writableRoots`.
    /// 2. `executablePath` must be a file that can run.
    ///
    /// - Parameters:
    ///   - shellPath: The absolute path of the shell to run.
    ///   - shellArguments: The arguments of that shell, for example
    ///     `["-c", command]`.
    ///   - workingDirectory: The absolute directory the command runs in, with
    ///     each symbolic link resolved. It must sit inside one of
    ///     `options.writableRoots`.
    ///   - temporaryDirectory: The absolute temporary directory to grant
    ///     writes under, with each symbolic link resolved, in addition to the
    ///     roots.
    /// - Returns: `/usr/bin/sandbox-exec`, and its argument list: the `-D`
    ///   parameter pairs — the roots in order, then `TMPDIR`, then each
    ///   `EXTRA_W*` — then `-p` and the profile, and then the shell invocation
    ///   at the end.
    /// - Throws: `SeatbeltSandboxError.workingDirectoryOutsideRoots` when the
    ///   working directory sits inside no configured root, or
    ///   `SeatbeltSandboxError.sandboxExecMissing` when the wrapper binary
    ///   cannot run.
    public func wrap(
        shellPath: String,
        shellArguments: [String],
        workingDirectory: String,
        temporaryDirectory: String
    ) throws -> SandboxedInvocation {
        try validateConfinable(workingDirectory: workingDirectory)

        return SandboxedInvocation(
            executable: executablePath,
            arguments: wrapperArguments(temporaryDirectory: temporaryDirectory) + [shellPath]
                + shellArguments)
    }

    /// The argument list of the wrapper itself: each `-D` parameter pair, then
    /// `-p` and the profile. That is everything up to, and not including, the
    /// command that gets confined.
    ///
    /// The one builder that `wrap` and `preflight` both go through, thus the
    /// canary cannot prove a profile, or a set of `-D` pairs, that is not the
    /// one a command runs under. That is what makes the canary say something
    /// about the count invariant that the doc comment of this type states: a
    /// `param` that the profile names with no `-D` to supply it fails
    /// compilation the same way for `/usr/bin/true` and for `/bin/sh`.
    ///
    /// - Parameter temporaryDirectory: The absolute temporary directory to
    ///   grant writes under, with each symbolic link resolved, in addition to
    ///   the roots.
    /// - Returns: The `-D` pairs — the roots in order, then `TMPDIR`, then
    ///   each `EXTRA_W*` — and then `-p` and the profile text.
    private func wrapperArguments(temporaryDirectory: String) -> [String] {
        var arguments: [String] = []
        for (index, root) in options.writableRoots.enumerated() {
            arguments += [
                Self.parameterOption, "\(Self.rootParameterPrefix)\(index)=\(root)",
            ]
        }
        arguments += [
            Self.parameterOption,
            "\(Self.temporaryDirectoryParameter)=\(temporaryDirectory)",
        ]
        for (index, path) in options.extraWritePaths.enumerated() {
            arguments += [
                Self.parameterOption, "\(Self.extraWriteParameterPrefix)\(index)=\(path)",
            ]
        }
        return arguments + [Self.profileOption, profileOverride ?? Self.profile(for: options)]
    }

    /// Proves that confinement can be built for `workingDirectory` at all, and
    /// throws when it cannot.
    ///
    /// The two checks that `wrap` states, put in one place thus `preflight`
    /// applies exactly the same ones — and in the same order, thus a caller
    /// gets the same error from either way in — before it pays for a canary.
    ///
    /// - Parameter workingDirectory: The absolute directory the command runs
    ///   in, with each symbolic link resolved.
    /// - Throws: `SeatbeltSandboxError.workingDirectoryOutsideRoots` when the
    ///   working directory sits inside no configured root, or
    ///   `SeatbeltSandboxError.sandboxExecMissing` when the wrapper binary
    ///   cannot run.
    private func validateConfinable(workingDirectory: String) throws {
        guard options.writableRoots.contains(where: { Self.path(workingDirectory, isInside: $0) })
        else {
            throw SeatbeltSandboxError.workingDirectoryOutsideRoots(
                path: workingDirectory, roots: options.writableRoots)
        }
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw SeatbeltSandboxError.sandboxExecMissing
        }
    }

    // MARK: - The preflight

    /// The program the canary confines. It does nothing and it ends with 0,
    /// thus the exit code of the canary reports on the profile and on nothing
    /// else.
    private static let canaryCommand = "/usr/bin/true"

    /// The exit code of a canary that passed.
    private static let canaryPassExitCode: Int32 = 0

    /// Proves that this sandbox can confine a command, and throws when it
    /// cannot — before any command starts.
    ///
    /// It runs the real wrapper, with the real profile and the real `-D`
    /// pairs, against `/usr/bin/true`. An exit code of zero means
    /// `sandbox-exec` compiled the profile and applied it. Any other value
    /// means it did not, and the exit code and the standard error say why —
    /// see the table on `SeatbeltSandboxError`.
    ///
    /// **Why this is necessary at all.** The shell capability reports the
    /// termination status of the COMMAND, thus a profile that `sandbox-exec`
    /// refuses at spawn time — exit 65 — cannot be told, after the fact, from
    /// a command that ended with 65 for reasons of its own. The answer is not
    /// to guess from exit codes afterwards. The answer is to take the
    /// ambiguity away beforehand: once the canary has passed, the profile is
    /// known to compile, and the only thing that changes for each command is
    /// the VALUES of the `-D` paths, which cannot break compilation. A value
    /// is never read as profile source — see the doc comment of this type.
    ///
    /// **What this deliberately does not cover.** A command that runs under a
    /// canary that passed and then meets `Operation not permitted` — a write
    /// outside the granted roots, for example — is an ordinary command result,
    /// reported as its own exit code and its own standard error. Nothing in
    /// this layer reads an exit code after the canary, thus nothing here can
    /// take one for a sandbox failure.
    ///
    /// The canary costs one spawn for each sandbox that a host builds, and for
    /// the copies of it, and not one for each command: `canaryGate` latches on
    /// the first pass, and each copy of this structure shares it. See
    /// `CanaryGate` for exactly what a latch covers and does not cover.
    ///
    /// - Parameters:
    ///   - workingDirectory: The absolute directory the command runs in, with
    ///     each symbolic link resolved. It is checked exactly as `wrap` checks
    ///     it.
    ///   - temporaryDirectory: The absolute temporary directory the command
    ///     can use, with each symbolic link resolved.
    /// - Throws: `SeatbeltSandboxError.workingDirectoryOutsideRoots` or
    ///   `SeatbeltSandboxError.sandboxExecMissing` when confinement cannot be
    ///   built at all — both come before any canary starts — or
    ///   `SeatbeltSandboxError.profileRejected`, which carries the exit code of
    ///   the canary and its standard error.
    ///
    ///   It can also let through, unchanged and with no type of this module,
    ///   whatever the canary SPAWN itself throws: `Subprocess` failing to start
    ///   the wrapper at all — the binary taken away between the check above and
    ///   the spawn, or a fork that failed — or canary standard error past the
    ///   capture limit. Those are deliberately not folded into a
    ///   `SeatbeltSandboxError`: they are the spawn-race class that this
    ///   package already accepts as a stop rather than as a corrective
    ///   message, they cannot happen in practice on a host whose wrapper binary
    ///   is there, and to give each one a case would make the enumeration claim
    ///   a completeness it does not have.
    ///
    ///   A caller must read each one of them the same way: **do not run the
    ///   command.** There is no way from a preflight that failed to a spawn
    ///   with no confinement, and no failure of any kind latches the gate.
    public func preflight(workingDirectory: String, temporaryDirectory: String) async throws {
        try validateConfinable(workingDirectory: workingDirectory)

        try await canaryGate.passOnce {
            let canaryArguments =
                wrapperArguments(temporaryDirectory: temporaryDirectory) + [Self.canaryCommand]
            let result = try await canarySpawn(executablePath, canaryArguments)
            guard result.exitCode == Self.canaryPassExitCode else {
                throw SeatbeltSandboxError.profileRejected(
                    exitCode: result.exitCode, stderr: result.stderr)
            }
        }
    }

    // MARK: - Containment

    /// Whether `path` is `root` itself, or a directory below it.
    ///
    /// Containment is decided on whole path components, and never on the
    /// prefix of a text: `/private/tmpevil` and `/private/tmp-evil` are not
    /// under `/private/tmp`, though both share its text.
    ///
    /// Both sides must also be absolute, and free of `.` and `..` components.
    /// A relative path is refused because its components can match those of a
    /// root while it names an altogether different directory. A traversal
    /// component is refused because `/granted/root/../../etc` carries the
    /// components of a contained path while it resolves outside the grant. The
    /// precondition on `CommandSandbox` already makes each caller give paths
    /// that `realpath(3)` resolved, and such a path has neither, thus to refuse
    /// them here costs a correct caller nothing and it keeps this boundary from
    /// resting on the care of the layer above.
    ///
    /// - Parameters:
    ///   - path: The absolute, resolved path to test.
    ///   - root: The absolute, resolved directory it must sit inside.
    /// - Returns: `true` when `path` is `root` or sits below it.
    private static func path(_ path: String, isInside root: String) -> Bool {
        guard let pathComponents = normalizedComponents(of: path),
            let rootComponents = normalizedComponents(of: root)
        else {
            return false
        }
        return pathComponents.starts(with: rootComponents)
    }

    /// The path components of an absolute `path` that carries no traversal, or
    /// `nil` when `path` is neither.
    ///
    /// An empty component — from a separator at the end, or from two
    /// separators together — is dropped, thus `/private/tmp/a/` and
    /// `/private/tmp//a` break down the same way as `/private/tmp/a`.
    ///
    /// - Parameter path: The path to break down.
    /// - Returns: The components that are not empty, in order, or `nil` when
    ///   `path` is relative or carries a `.` or `..` component.
    private static func normalizedComponents(of path: String) -> [Substring]? {
        guard path.hasPrefix("/") else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        return components
    }
}

/// A failure to build or to apply Seatbelt confinement for a command.
///
/// Each case means the same thing to a caller: the command must not run. This
/// sandbox never falls back to a spawn with no confinement.
///
/// These are the failures this layer DIAGNOSES, and not each failure it can
/// raise: `SeatbeltSandbox.preflight` also lets through a spawn failure from
/// the canary itself, unchanged and with no type of this module — see its
/// `- Throws:` clause for which ones, and why they keep their own type. That
/// one carries the same instruction as these: the command must not run.
///
/// `profileRejected` carries the exit code of `sandbox-exec` itself. Those
/// codes were measured against `/usr/bin/sandbox-exec` on Darwin 27.0.0
/// (2026-08-04):
///
/// | Failure | Exit | Standard error |
/// |---|---|---|
/// | a syntax error in the profile | 65 | `sandbox-exec: syntax error: expecting ')'` |
/// | a `param` the profile names with no `-D` to supply it | 65 | `sandbox-exec: invalid data type of path filter; expected pattern, got boolean` |
/// | the profile refuses to run the target | 71 | `sandbox-exec: execvp() of '/bin/sh' failed: Operation not permitted` |
/// | wrong usage, such as two `-p` options | 64 | the usage text |
/// | the profile compiles and the command runs | the code of the command | the text of the command |
///
/// The last row is the whole problem: the shell capability reports the
/// termination status of the COMMAND, thus a wrapper failure that reaches a
/// real spawn cannot be told from a command that ended with the same code. That
/// is fixed by making it impossible to reach — `SeatbeltSandbox.preflight`
/// proves the profile compiles before any command starts — and never by sorting
/// exit codes after the fact.
///
/// Out of scope on purpose, for that same reason: a command that runs under a
/// healthy sandbox and is then refused inside it — `Operation not permitted` on
/// a write outside the granted roots — is an ordinary command result, and not a
/// case of this error.
public enum SeatbeltSandboxError: Error, Equatable, Sendable {

    /// The wrapper binary that `SeatbeltSandbox.executablePath` names is
    /// absent, or it cannot run, thus confinement cannot be applied at all.
    case sandboxExecMissing

    /// The working directory of one call sits inside no configured writable
    /// root. It names the directory, and the roots it was checked against.
    ///
    /// The working directory arrives from a parameter that the model writes,
    /// thus it is checked against the roots the host configured, and it is not
    /// trusted to name its own sandbox: to honour it would let a request for
    /// `/` widen the grant to the whole file system.
    case workingDirectoryOutsideRoots(path: String, roots: [String])

    /// `sandbox-exec` refused the profile. It carries the exit code it refused
    /// with — see the table above — and the standard error it explained itself
    /// with.
    ///
    /// Only `SeatbeltSandbox.preflight` raises it, and only from the canary,
    /// thus the exit code it carries is always the code of the WRAPPER, and
    /// never the code of a confined command, which nothing in this layer sorts.
    ///
    /// The standard error travels whole, and it is not made shorter, because it
    /// is the one text that separates two failures that share an exit code: 65
    /// covers both a profile that is malformed and a `param` with no `-D` to
    /// supply it.
    case profileRejected(exitCode: Int32, stderr: String)
}
