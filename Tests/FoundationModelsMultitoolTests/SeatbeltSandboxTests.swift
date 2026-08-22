import Foundation
import Synchronization
import Testing

@testable import FoundationModelsMultitool

/// Unit tests for `SeatbeltSandbox` — the `CommandSandbox` that bounds each
/// WRITE and each DELETE of a command that runs to a configured set of root
/// directories, with `/usr/bin/sandbox-exec`.
///
/// Two kinds of test stand here. Most read the argument list and the profile
/// text that `wrap` and `profile(for:)` make, and they start nothing. The
/// preflight tests start a canary, because a preflight IS a canary run; each
/// one ends in well under a second and it needs no system outside this host.
///
/// **The profile text is the confinement.** A change to that text is a change
/// to what a command can do. Thus one test holds the WHOLE profile for one
/// fixed configuration, byte for byte, and a change to any line of it turns
/// that test red. Whether the kernel then applies the profile it compiled is
/// the work of a spawn-and-probe suite on a real host, and not the work of
/// this file.
@Suite("SeatbeltSandbox")
struct SeatbeltSandboxTests {

    /// Owns the temporary directories the preflight tests make. Thus they go
    /// away when the test ends, and they do not collect in `$TMPDIR` run after
    /// run.
    private let scratch = TestScratch()

    /// The wrapper binary that a confined spawn starts.
    private static let wrapperExecutable = "/usr/bin/sandbox-exec"

    /// The program the canary confines. It does nothing and it ends with 0.
    private static let canaryCommand = "/usr/bin/true"

    /// The shell each test wraps.
    private static let shellPath = "/bin/sh"

    /// The arguments of that shell.
    private static let shellArguments = ["-c", "echo hi"]

    /// The shell invocation as it stands at the end of a wrapped argument
    /// list.
    private static let shellInvocation = [shellPath] + shellArguments

    /// The first writable root the value tests configure.
    ///
    /// It is absolute and it carries no traversal component, as the
    /// precondition on `CommandSandbox` demands of each caller.
    private static let firstRoot = "/private/tmp/a"

    /// A second writable root. Thus one test shows that the roots keep their
    /// order, and that each one gets a number of its own.
    private static let secondRoot = "/private/tmp/b"

    /// A third writable root, for the test that counts the grants.
    private static let thirdRoot = "/private/tmp/c"

    /// A directory under `secondRoot`, thus one test shows that a working
    /// directory below a root is granted.
    private static let directoryUnderSecondRoot = "/private/tmp/b/job"

    /// The temporary directory the value tests give.
    private static let temporaryDirectory = "/private/tmp/t"

    /// The first extra write path the value tests configure.
    private static let firstExtraWritePath = "/private/tmp/x"

    /// A second extra write path. Thus one test shows that each one gets a
    /// number of its own.
    private static let secondExtraWritePath = "/private/tmp/y"

    /// A path that shares the text of `firstRoot` but not its components.
    ///
    /// Containment is decided on whole components. Thus this path stands
    /// outside `firstRoot`, though `firstRoot` is a prefix of its text.
    private static let textualNeighbourOfFirstRoot = "/private/tmp/aevil"

    /// The root of the file system: the widest working directory a model can
    /// ask for, and the one that must be refused.
    private static let fileSystemRoot = "/"

    /// A path value that tries to close the S-expression of the profile and to
    /// add rules of its own.
    private static let hostilePath = "/private/tmp/evil\") (allow default) (\""

    /// The word that shows up in the profile text if `hostilePath` ever
    /// reaches it.
    private static let hostilePathMarker = "evil"

    /// The prefix of a write grant that names a root parameter.
    private static let rootGrantPrefix = "(subpath (param \"ROOT"

    /// The prefix of a write grant that names an extra write parameter.
    private static let extraWriteGrantPrefix = "(subpath (param \"EXTRA_W"

    /// The prefix of the one line of the profile that grants writing.
    private static let writeLinePrefix = "(allow file-write*"

    /// The wrapper option that carries the profile text.
    private static let profileOption = "-p"

    /// The exit code `sandbox-exec` refuses a profile it cannot compile with.
    private static let rejectedProfileExitCode: Int32 = 65

    /// The opening of each diagnostic `sandbox-exec` writes about itself.
    private static let wrapperDiagnosticPrefix = "sandbox-exec:"

    /// A profile that `sandbox-exec` cannot compile: the list never closes.
    private static let brokenProfile = "(version 1"

    /// A wrapper binary that no host has, thus a test can watch the sandbox
    /// fail closed.
    private static let absentWrapperExecutable = "/private/tmp/no-such-directory/sandbox-exec"

    /// How many canary spawns a gate that does not latch a failure pays for
    /// two calls that both failed.
    private static let unlatchedCanarySpawnCount = 2

    /// The number of writable roots the profile-grant count test configures.
    private static let countedRoots = [firstRoot, secondRoot, thirdRoot]

    /// The configuration whose profile one test holds byte for byte: one
    /// writable root, and one extra write path.
    private static let fixedOptions = SeatbeltSandbox.Options(
        writableRoots: [firstRoot], extraWritePaths: [firstExtraWritePath])

    /// The WHOLE profile text that `fixedOptions` must make, byte for byte.
    ///
    /// A path never appears in profile text — it travels as a `-D` value —
    /// thus this text depends on the COUNT of the roots and of the extra write
    /// paths, and on nothing else. It is therefore the same on each host, and
    /// it is safe to hold as a literal.
    ///
    /// Each line of it is load-bearing. `(deny default)` is the line that
    /// makes this a sandbox and not a wrapper that does nothing. The
    /// `process-fork`, `process-exec*`, `sysctl-read`, `mach-lookup` and
    /// `signal` allowances are the least that lets `/bin/sh` start and make
    /// children. `(allow file-read*)` is unconditional on purpose. `/dev/null`
    /// needs a grant of its own, or a plain `cmd >/dev/null` fails. And
    /// `file-write*` covers deletion, thus no rule about unlinking is
    /// necessary.
    private static let fixedProfile = """
        (version 1)
        (deny default)
        (allow process-fork)
        (allow process-exec*)
        (allow sysctl-read)
        (allow mach-lookup)
        (allow signal (target same-sandbox))
        (allow file-read*)
        (allow file-write-data (literal "/dev/null") (literal "/dev/zero"))
        (allow file-write* (subpath (param "ROOT0")) (subpath (param "TMPDIR")) (subpath (param "EXTRA_W0")))
        (allow network*)
        (allow system-socket)
        """

    /// Wraps the shell constants above with `sandbox`.
    ///
    /// - Parameters:
    ///   - sandbox: The sandbox to wrap with.
    ///   - workingDirectory: The directory the command runs in.
    ///   - temporaryDirectory: The temporary directory the command can use.
    /// - Returns: The spawn decoration that `sandbox` gives back.
    /// - Throws: What `sandbox` throws.
    private func invocation(
        from sandbox: SeatbeltSandbox,
        workingDirectory: String,
        temporaryDirectory: String
    ) throws -> SandboxedInvocation {
        try sandbox.wrap(
            shellPath: Self.shellPath,
            shellArguments: Self.shellArguments,
            workingDirectory: workingDirectory,
            temporaryDirectory: temporaryDirectory)
    }

    /// How many times `needle` stands in `text`, with no overlap.
    ///
    /// - Parameters:
    ///   - needle: The text to count.
    ///   - text: The text to count it in.
    /// - Returns: The number of times `needle` stands in `text`.
    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// The one line of `profile` that grants writing.
    ///
    /// - Parameter profile: The profile text to read.
    /// - Returns: That single line.
    /// - Throws: When the profile carries no such line.
    private func writeLine(of profile: String) throws -> String {
        let lines = profile.split(separator: "\n").filter {
            $0.hasPrefix(Self.writeLinePrefix)
        }
        #expect(lines.count == 1)
        return try String(#require(lines.first))
    }

    /// Makes a temporary directory that this test owns, with each symbolic
    /// link resolved by `realpath(3)`.
    ///
    /// `TestScratch` resolves with `URL.resolvingSymlinksInPath()`, and that
    /// resolver runs the OTHER way for this purpose: it gives back
    /// `/var/folders/…`, and `/var` is itself a symbolic link to
    /// `/private/var`. Seatbelt matches the path the kernel resolved, thus the
    /// precondition on `CommandSandbox` asks for the `realpath(3)` form. A
    /// test gives that form, exactly as a real caller does. Measured: a
    /// working directory in the `/var/folders/…` form is refused as outside
    /// the roots, because `Options` resolves each root with `realpath(3)`.
    ///
    /// - Parameter prefix: A short name that states the role of the directory.
    /// - Returns: The new directory, in the form Seatbelt can match.
    /// - Throws: When the directory does not make.
    private func makeResolvedDirectory(prefix: String) throws -> String {
        let made = try scratch.makeDirectory(prefix: prefix).path
        guard let resolved = realpath(made, nil) else { return made }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: - The profile text

    @Test("the profile of one fixed configuration is exactly this text")
    func theProfileOfAFixedConfigurationIsExact() {
        // The confinement IS this text. A change to any line of it changes
        // what a command that runs can do, thus the whole text is held here
        // and not one line of it at a time.
        #expect(SeatbeltSandbox.profile(for: Self.fixedOptions) == Self.fixedProfile)
    }

    @Test("each writable root makes one write grant, and it makes no read grant")
    func eachWritableRootMakesOneWriteGrant() throws {
        let profile = SeatbeltSandbox.profile(for: .init(writableRoots: Self.countedRoots))

        #expect(
            occurrences(of: Self.rootGrantPrefix, in: profile) == Self.countedRoots.count)
        #expect(
            occurrences(of: Self.rootGrantPrefix, in: try writeLine(of: profile))
                == Self.countedRoots.count)
    }

    @Test("each extra write path makes one profile parameter and one -D pair")
    func eachExtraWritePathMakesOneParameterAndOnePair() throws {
        let extraWritePaths = [Self.firstExtraWritePath, Self.secondExtraWritePath]
        let options = SeatbeltSandbox.Options(
            writableRoots: [Self.firstRoot], extraWritePaths: extraWritePaths)
        let profile = SeatbeltSandbox.profile(for: options)

        // The count of the `param` references in the profile and the count of
        // the `-D` pairs must agree exactly. A `param` the profile names and
        // no `-D` supplies makes `sandbox-exec` refuse the whole profile.
        #expect(
            occurrences(of: Self.extraWriteGrantPrefix, in: profile) == extraWritePaths.count)

        let invocation = try invocation(
            from: SeatbeltSandbox(options: options),
            workingDirectory: Self.firstRoot,
            temporaryDirectory: Self.temporaryDirectory)

        #expect(
            invocation.arguments == [
                "-D", "ROOT0=\(Self.firstRoot)",
                "-D", "TMPDIR=\(Self.temporaryDirectory)",
                "-D", "EXTRA_W0=\(Self.firstExtraWritePath)",
                "-D", "EXTRA_W1=\(Self.secondExtraWritePath)",
                Self.profileOption, profile,
            ] + Self.shellInvocation)
    }

    @Test("a path value never reaches the profile text")
    func aPathValueNeverReachesTheProfileText() throws {
        let sandbox = SeatbeltSandbox(options: .init(writableRoots: [Self.hostilePath]))

        let invocation = try invocation(
            from: sandbox,
            workingDirectory: Self.hostilePath,
            temporaryDirectory: Self.temporaryDirectory)

        // The value travels as a `-D` pair alone. The profile the wrapper
        // compiles carries the NAME of the parameter, thus a hostile value
        // cannot close an S-expression and add rules of its own.
        let profileIndex = try #require(
            invocation.arguments.firstIndex(of: Self.profileOption)) + 1
        #expect(!invocation.arguments[profileIndex].contains(Self.hostilePathMarker))
        #expect(invocation.arguments.contains("ROOT0=\(Self.hostilePath)"))
    }

    // MARK: - The argument list

    @Test("wrap makes the sandbox-exec argument list, with one -D pair for each root")
    func wrapMakesTheWrapperArgumentList() throws {
        let options = SeatbeltSandbox.Options(
            writableRoots: [Self.firstRoot, Self.secondRoot])

        let invocation = try invocation(
            from: SeatbeltSandbox(options: options),
            workingDirectory: Self.firstRoot,
            temporaryDirectory: Self.temporaryDirectory)

        #expect(invocation.executable == Self.wrapperExecutable)
        #expect(
            invocation.arguments == [
                "-D", "ROOT0=\(Self.firstRoot)",
                "-D", "ROOT1=\(Self.secondRoot)",
                "-D", "TMPDIR=\(Self.temporaryDirectory)",
                Self.profileOption, SeatbeltSandbox.profile(for: options),
            ] + Self.shellInvocation)
    }

    @Test("an empty root list falls back to the working directory of this process")
    func anEmptyRootListFallsBackToTheProcessDirectory() throws {
        let directory = FileManager.default.currentDirectoryPath
        #expect(SeatbeltSandbox.Options().writableRoots == [directory])

        let invocation = try invocation(
            from: SeatbeltSandbox(),
            workingDirectory: directory,
            temporaryDirectory: Self.temporaryDirectory)

        #expect(invocation.arguments.contains("ROOT0=\(directory)"))
    }

    // MARK: - Containment of the working directory

    @Test("a working directory under any configured root is granted")
    func aWorkingDirectoryUnderAnyRootIsGranted() throws {
        let sandbox = SeatbeltSandbox(
            options: .init(writableRoots: [Self.firstRoot, Self.secondRoot]))

        let invocation = try invocation(
            from: sandbox,
            workingDirectory: Self.directoryUnderSecondRoot,
            temporaryDirectory: Self.temporaryDirectory)

        #expect(invocation.executable == Self.wrapperExecutable)
    }

    @Test(
        "a working directory outside each configured root is refused",
        arguments: [fileSystemRoot, textualNeighbourOfFirstRoot])
    func aWorkingDirectoryOutsideEachRootIsRefused(workingDirectory: String) {
        // The working directory arrives from a parameter the model writes.
        // Thus a request for `/` must not widen the grant to the whole file
        // system, and a path that only shares the TEXT of a root is not under
        // that root.
        let roots = [Self.firstRoot, Self.secondRoot]
        let sandbox = SeatbeltSandbox(options: .init(writableRoots: roots))

        #expect(
            throws: SeatbeltSandboxError.workingDirectoryOutsideRoots(
                path: workingDirectory, roots: roots)
        ) {
            try invocation(
                from: sandbox,
                workingDirectory: workingDirectory,
                temporaryDirectory: Self.temporaryDirectory)
        }
    }

    @Test(
        "a working directory that leaves a root by traversal or by relativity is refused",
        arguments: [
            "/private/tmp/a/../../etc", "private/tmp/a", "/private/tmp/a/./../etc",
        ])
    func aWorkingDirectoryThatLeavesARootIsRefused(workingDirectory: String) {
        // Each of these carries the components of the granted root at its
        // front, thus a test on the components alone would let each one in
        // while it names a directory outside the grant.
        let roots = [Self.firstRoot]
        let sandbox = SeatbeltSandbox(options: .init(writableRoots: roots))

        #expect(
            throws: SeatbeltSandboxError.workingDirectoryOutsideRoots(
                path: workingDirectory, roots: roots)
        ) {
            try invocation(
                from: sandbox,
                workingDirectory: workingDirectory,
                temporaryDirectory: Self.temporaryDirectory)
        }
    }

    @Test("a wrapper binary that is absent is refused, and no command runs unconfined")
    func anAbsentWrapperBinaryIsRefused() {
        var sandbox = SeatbeltSandbox(options: .init(writableRoots: [Self.firstRoot]))
        sandbox.executablePath = Self.absentWrapperExecutable

        #expect(throws: SeatbeltSandboxError.sandboxExecMissing) {
            try invocation(
                from: sandbox,
                workingDirectory: Self.firstRoot,
                temporaryDirectory: Self.temporaryDirectory)
        }
    }

    // MARK: - The preflight

    @Test("a canary that the real wrapper passes latches the gate")
    func aCanaryTheRealWrapperPassesLatchesTheGate() async throws {
        // The first call runs the REAL wrapper on the REAL profile. It throws
        // when `sandbox-exec` refuses that profile, thus the call getting
        // through IS the proof that the profile compiles on this host. The
        // pass latches the gate, thus the second call runs no canary at all
        // and it never reaches the stand-in that always fails.
        let root = try makeResolvedDirectory(prefix: "seatbelt-canary-pass")
        var sandbox = SeatbeltSandbox(options: .init(writableRoots: [root]))

        try await sandbox.preflight(workingDirectory: root, temporaryDirectory: root)

        let counter = CanarySpawnCounter(answering: [.failure(CanarySpawnFailure())])
        sandbox.canarySpawn = counter.spawn
        try await sandbox.preflight(workingDirectory: root, temporaryDirectory: root)

        #expect(counter.count == 0)
    }

    @Test("a profile the wrapper refuses comes back with its exit code and its standard error")
    func aRefusedProfileComesBackWithItsExitCodeAndStandardError() async throws {
        let root = try makeResolvedDirectory(prefix: "seatbelt-canary-broken")
        var sandbox = SeatbeltSandbox(options: .init(writableRoots: [root]))
        sandbox.profileOverride = Self.brokenProfile

        let error = try #require(
            await #expect(throws: SeatbeltSandboxError.self) {
                try await sandbox.preflight(workingDirectory: root, temporaryDirectory: root)
            })

        guard case .profileRejected(let exitCode, let standardError) = error else {
            Issue.record("the sandbox reported \(error) and not a refused profile")
            return
        }
        #expect(exitCode == Self.rejectedProfileExitCode)
        #expect(standardError.contains(Self.wrapperDiagnosticPrefix))
    }

    @Test("the canary runs the argument list that wrap makes, with /usr/bin/true at its end")
    func theCanaryRunsTheArgumentListThatWrapMakes() async throws {
        let root = try makeResolvedDirectory(prefix: "seatbelt-canary-argv-root")
        let temporaryDirectory = try makeResolvedDirectory(prefix: "seatbelt-canary-argv-tmp")
        let counter = CanarySpawnCounter()
        var sandbox = SeatbeltSandbox(
            options: .init(
                writableRoots: [root], extraWritePaths: [Self.firstExtraWritePath]))
        sandbox.canarySpawn = counter.spawn

        try await sandbox.preflight(
            workingDirectory: root, temporaryDirectory: temporaryDirectory)

        // The canary must reproduce the argument list of the wrapper exactly,
        // or it proves a different profile than the one the command runs
        // under. That list is what `wrap` gives back with the shell at its end
        // taken away.
        let wrapped = try invocation(
            from: sandbox, workingDirectory: root, temporaryDirectory: temporaryDirectory)
        let wrapperArguments = wrapped.arguments.dropLast(Self.shellInvocation.count)

        #expect(
            counter.calls == [
                CanarySpawnCounter.Call(
                    executable: Self.wrapperExecutable,
                    arguments: Array(wrapperArguments) + [Self.canaryCommand])
            ])
    }

    @Test("a copy of the sandbox shares the gate of the value it came from")
    func aCopyOfTheSandboxSharesTheGate() async throws {
        // A capability copies the whole runner, the sandbox included, for each
        // session it connects to events. Thus a gate held by each copy on its
        // own would pay for one canary for each session, and not one for each
        // sandbox a host builds.
        let root = try makeResolvedDirectory(prefix: "seatbelt-canary-copy")
        let counter = CanarySpawnCounter()
        var sandbox = SeatbeltSandbox(options: .init(writableRoots: [root]))
        sandbox.canarySpawn = counter.spawn
        let copy = sandbox

        try await sandbox.preflight(workingDirectory: root, temporaryDirectory: root)
        try await copy.preflight(workingDirectory: root, temporaryDirectory: root)

        #expect(counter.count == 1)
    }

    @Test("a canary spawn that fails travels unchanged, and it latches nothing")
    func aCanarySpawnThatFailsTravelsUnchanged() async throws {
        // A failure to START the wrapper is a different thing from the wrapper
        // refusing the profile, and `preflight` says so: it travels with the
        // type it came with, and it is not dressed up as a
        // `SeatbeltSandboxError`. It must also fail closed both times.
        let root = try makeResolvedDirectory(prefix: "seatbelt-canary-spawn-failure")
        let counter = CanarySpawnCounter(answering: [.failure(CanarySpawnFailure())])
        var sandbox = SeatbeltSandbox(options: .init(writableRoots: [root]))
        sandbox.canarySpawn = counter.spawn

        await #expect(throws: CanarySpawnFailure()) {
            try await sandbox.preflight(workingDirectory: root, temporaryDirectory: root)
        }
        await #expect(throws: CanarySpawnFailure()) {
            try await sandbox.preflight(workingDirectory: root, temporaryDirectory: root)
        }

        #expect(counter.count == Self.unlatchedCanarySpawnCount)
    }

    @Test("a wrapper binary that is absent is refused before any canary starts")
    func anAbsentWrapperBinaryIsRefusedBeforeAnyCanary() async {
        let counter = CanarySpawnCounter()
        var sandbox = SeatbeltSandbox(options: .init(writableRoots: [Self.firstRoot]))
        sandbox.executablePath = Self.absentWrapperExecutable
        sandbox.canarySpawn = counter.spawn

        await #expect(throws: SeatbeltSandboxError.sandboxExecMissing) {
            try await sandbox.preflight(
                workingDirectory: Self.firstRoot,
                temporaryDirectory: Self.temporaryDirectory)
        }

        #expect(counter.count == 0)
    }

    @Test("a working directory outside each root is refused before any canary starts")
    func aWorkingDirectoryOutsideEachRootIsRefusedBeforeAnyCanary() async {
        let counter = CanarySpawnCounter()
        let roots = [Self.firstRoot]
        var sandbox = SeatbeltSandbox(options: .init(writableRoots: roots))
        sandbox.canarySpawn = counter.spawn

        await #expect(
            throws: SeatbeltSandboxError.workingDirectoryOutsideRoots(
                path: Self.secondRoot, roots: roots)
        ) {
            try await sandbox.preflight(
                workingDirectory: Self.secondRoot,
                temporaryDirectory: Self.temporaryDirectory)
        }

        #expect(counter.count == 0)
    }
}

/// A canary spawn that could not be made at all — the stand-in for a failure to
/// start the wrapper binary.
///
/// A type of this file, and not a case of `SeatbeltSandboxError`, because what
/// the test pins is that `preflight` lets such a failure travel AS IT IS,
/// rather than dressing it up as a failure this layer diagnoses.
private struct CanarySpawnFailure: Error, Equatable, Sendable {}

/// A stand-in for the canary spawn that records what it was asked to run and
/// answers from a script.
///
/// Thus a test counts the spawns and reads the argument list with no child
/// process at all.
///
/// A final class with a lock, because swift-testing runs the tests of one suite
/// together and thus the suite type is `Sendable`, and because `CanarySpawn` is
/// a `@Sendable` closure that must reach the same recording each time.
private final class CanarySpawnCounter: Sendable {

    /// One recorded spawn: the executable, and the argument list it received.
    struct Call: Sendable, Equatable {

        /// The executable the sandbox asked to start.
        let executable: String

        /// The argument list it asked to start that executable with.
        let arguments: [String]
    }

    /// Each spawn recorded so far, in the order it arrived.
    private let recorded = Mutex<[Call]>([])

    /// What each successive spawn answers with. The last entry repeats when
    /// the script runs out, thus a script of one entry is a constant answer.
    private let script: [Result<CanaryResult, CanarySpawnFailure>]

    /// Makes a counter that answers from `script`, in order.
    ///
    /// - Parameter script: The answers to give, one for each spawn, the last
    ///   one repeating. The default is a single canary that passes.
    init(
        answering script: [Result<CanaryResult, CanarySpawnFailure>] = [
            .success(CanaryResult(exitCode: 0, stderr: ""))
        ]
    ) {
        self.script = script
    }

    /// Each spawn recorded so far, in the order it arrived.
    var calls: [Call] { recorded.withLock { $0 } }

    /// How many spawns this counter recorded.
    var count: Int { recorded.withLock { $0.count } }

    /// The spawn to put on a `SeatbeltSandbox` in place of the live one.
    var spawn: CanarySpawn {
        { [self] executable, arguments in
            let index = recorded.withLock { calls -> Int in
                calls.append(Call(executable: executable, arguments: arguments))
                return calls.count - 1
            }
            return try script[min(index, script.count - 1)].get()
        }
    }
}
