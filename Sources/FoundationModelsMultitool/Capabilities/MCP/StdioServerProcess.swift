// `StdioServerProcess` — this package owns the lifecycle of the subprocess a
// local (stdio) MCP server is. The sdk's `StdioTransport` only wraps two file
// descriptors and never spawns anything, so the spawn, the process group, the
// registry entry and the reap all stand here.
//
// A behavioral port of
// `../FoundationModelsMCP/Sources/FoundationModelsMCP/StdioServerProcess.swift`.
// eventplan.md § "Consolidation of the siblings" names this file as one piece
// of `Capabilities/MCP`.
//
// **Server subprocesses are infrastructure.** eventplan.md: "Server
// subprocesses are infrastructure. They have session lifetime, they are never
// runs, and they never get a `completionToken`." A spawned server is not a run
// on the run plane: no mailbox tracks it, no `status()` lists it, and no
// `cancel(completionToken)` reaches it. `shutdown()` and `respawn()` are the
// host's own calls, and they stay as they are.
//
// **The registry is the SHARED `ProcessRegistry` of `FoundationModelsExtras`.**
// The source of this port carried a `ProcessRegistry.swift` of its own; that
// file is not ported. This package holds no copy of the type — see the
// `extrasDependencyName` comment in `Package.swift` — so every spawned server
// registers into the same table `ShellRunner` registers each shell child into,
// and one `atexit` sweep stands behind all of them.
//
// **The same discipline as `ShellRunner`, with one divergence.** Spawn into the
// child's OWN process group, so a server's own children die with it; register
// the pid; and backstop everything with the `atexit` sweep and its stated
// limit (a normal exit only, never `SIGKILL` or a crash). `ShellRunner` spawns
// through `Subprocess.run(...)`, a structured call that blocks until its child
// exits and reaps it on the way out. A stdio server is not like that: it lives
// across an open-ended span of connect, reconnect and disconnect calls, with
// nothing structurally awaiting it the whole time. So this type spawns through
// raw `posix_spawn` — `POSIX_SPAWN_SETPGROUP` sets the group as part of the
// spawn — and owns the reap itself: every teardown path below calls both
// `killpg` and `waitpid`, never just one.
//
// **Four teardown triggers, one idempotent funnel.** Each one reaches
// `ProcessState.terminateCurrent()`, so a call to any of them, in any order,
// any number of times, is safe:
//
//   1. Explicit `shutdown()` — a host tears the server down on purpose.
//   2. Connection teardown — the vended transport's own `disconnect()`, which a
//      host's disconnect of the server built over it reaches, even when the
//      host never calls `shutdown()` directly.
//   3. The pre-spawn teardown of `respawn()` — each fresh spawn first tears
//      down whatever this instance fronted before, which is what reaps a
//      process that died on its own (the reconnect path after a mid-call
//      fault, where nothing calls `disconnect()` on the dead transport).
//   4. Owner teardown — `ProcessState.deinit`. The factory closure
//      `stdio.respawn` captures the shared class-backed state; once whatever
//      retains that closure is itself gone, with no other host-held reference
//      to the `StdioServerProcess` value, ARC drops the last strong reference
//      and `deinit` fires with no call from anyone.
//
// **`import Logging` names ONE type, and logs nothing.** The sdk's `Transport`
// protocol requires `var logger: Logging.Logger`, so the private transport
// below must name that type to conform. It hands on the logger of the inner
// `StdioTransport` and writes nothing of its own; this file logs through
// nothing else. The manifest still declares no `swift-log` product — see
// `mcpPackage` in `Package.swift`.

import Foundation
import FoundationModelsExtras
import Logging
import MCP
import Synchronization
import System

/// Spawns a local MCP server as a subprocess, in its own process group, and
/// vends a `StdioTransport` wired to its stdio pipes.
///
/// A value type over a small class-backed process state: copies of one
/// `StdioServerProcess` share the same live subprocess bookkeeping, so a host
/// can pass `stdio.respawn` around as a plain function value — its use as a
/// transport factory — and ``shutdown()`` and the vended transport's
/// `disconnect()` still see and act on whichever process is live.
///
/// Nothing else in this package constructs this type: to spawn a process is a
/// decision only a host makes, by constructing this type itself and handing
/// its ``respawn()`` method to the server as its transport factory. A host
/// that connects through a transport of its own never constructs this type, so
/// neither the registry nor its `atexit` sweep is touched on that path.
///
/// **One live subprocess per value, never pooled or shared.** Each value owns
/// at most one live child at a time (see ``respawn()``, which tears down what
/// it fronted before it spawns again), and a host that wants two sessions to
/// each have their own server constructs two values. To share one child across
/// sessions would couple their lifetimes and make "session close" ambiguous.
/// A host that wants pooling can layer it on top of this type.
public struct StdioServerProcess: Sendable {
    /// One environment variable to layer onto the inherited environment of
    /// the spawned subprocess — a list of pairs, not a dictionary, so an
    /// order and a repeat both keep their meaning (see ``env``).
    public struct EnvVariable: Sendable, Equatable, Hashable {
        /// The name of the variable.
        public var name: String

        /// The value of the variable.
        public var value: String

        /// Creates one environment variable entry.
        ///
        /// - Parameters:
        ///   - name: The name of the variable.
        ///   - value: The value of the variable.
        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    /// Errors thrown while a ``StdioServerProcess`` is constructed or spawned.
    public enum StdioServerProcessError: Error, CustomStringConvertible, Equatable {
        /// ``init(command:args:env:name:)`` was given a `command` that is not
        /// an absolute path.
        ///
        /// This package requires an absolute path and resolves nothing through
        /// `PATH`. A relative lookup would have to pick WHICH `PATH` — the
        /// spawning process's, a shell's, a host's configured one — and an
        /// absolute path removes the question. A caller that holds a bare
        /// command name resolves it itself before it constructs this type.
        case commandNotAbsolute(String)

        /// The stdin or the stdout pipe could not be created; carries the C
        /// `errno`.
        case pipeCreationFailed(errno: Int32)

        /// `posix_spawn` itself failed; carries the offending `command` path —
        /// which is what lets a host say WHICH server is misconfigured — and
        /// the error number `posix_spawn` returned directly (unlike most POSIX
        /// calls, it returns the number instead of setting `errno`).
        ///
        /// Conforms to `NonRetryableConnectError` (see the extension below):
        /// `command`, `args` and `env` never change between two ``respawn()``
        /// calls of one value, so a `command` that fails to spawn one time
        /// fails the same way every time after.
        case spawnFailed(command: String, errno: Int32)

        /// A human-readable description of this error.
        public var description: String {
            switch self {
            case .commandNotAbsolute(let command):
                return
                    "StdioServerProcess requires an absolute path to the executable; got \"\(command)\". Resolve it (e.g. against PATH) before constructing this type."
            case .pipeCreationFailed(let errno):
                return "StdioServerProcess failed to create a pipe: \(String(cString: strerror(errno)))"
            case .spawnFailed(let command, let errno):
                return
                    "StdioServerProcess failed to spawn \"\(command)\": \(String(cString: strerror(errno)))"
            }
        }
    }

    /// The absolute path to the server executable — see
    /// ``StdioServerProcessError/commandNotAbsolute(_:)`` for why it is
    /// required and not resolved through `PATH`.
    public let command: String

    /// The arguments passed to ``command`` on every spawn.
    public let args: [String]

    /// Environment variables layered onto the inherited environment of the
    /// spawned subprocess.
    ///
    /// **Augments, never replaces**, the parent environment: MCP servers
    /// commonly need inherited variables (`PATH`, `HOME`, a locale, the
    /// credential helpers a server shells out to) that an environment built
    /// from nothing would drop in silence. An entry here wins over an
    /// inherited variable of the same name; when ``env`` itself repeats a
    /// name, the later entry wins.
    public let env: [EnvVariable]

    /// The human-readable server name — the identity of the server a host
    /// builds over this process.
    public let name: String

    /// The shared, class-backed process bookkeeping every copy of this value
    /// (and every transport it vends) refers to — see the header of this file
    /// for the four teardown paths this one piece of state serves.
    private let state: ProcessState

    /// Creates a ``StdioServerProcess`` that will spawn `command` on demand.
    ///
    /// No process is spawned yet — a spawn happens only when ``respawn()`` is
    /// called, never at construction. Each spawned pid registers into
    /// `ProcessRegistry.global`.
    ///
    /// - Parameters:
    ///   - command: The absolute path to the server executable.
    ///   - args: Arguments passed to `command` on every spawn. None by default.
    ///   - env: Environment variables layered onto (never in place of) the
    ///     inherited environment of the spawned subprocess. None by default.
    ///   - name: The human-readable server name.
    /// - Throws: ``StdioServerProcessError/commandNotAbsolute(_:)`` when
    ///   `command` is not an absolute path.
    public init(
        command: String,
        args: [String] = [],
        env: [EnvVariable] = [],
        name: String
    ) throws {
        try self.init(command: command, args: args, env: env, name: name, registry: .global)
    }

    /// The same as ``init(command:args:env:name:)``, with the registry every
    /// spawned pid goes into as a parameter.
    ///
    /// A test gives a private `ProcessRegistry()` here, and never `.global` —
    /// see the doc comment of `ProcessRegistry.global` for the reason.
    ///
    /// - Parameters:
    ///   - command: The absolute path to the server executable.
    ///   - args: Arguments passed to `command` on every spawn.
    ///   - env: Environment variables layered onto the inherited environment.
    ///   - name: The human-readable server name.
    ///   - registry: The registry every spawned pid is registered into and
    ///     deregistered from.
    /// - Throws: ``StdioServerProcessError/commandNotAbsolute(_:)`` when
    ///   `command` is not an absolute path.
    init(
        command: String,
        args: [String] = [],
        env: [EnvVariable] = [],
        name: String,
        registry: ProcessRegistry
    ) throws {
        guard command.hasPrefix("/") else {
            throw StdioServerProcessError.commandNotAbsolute(command)
        }
        self.command = command
        self.args = args
        self.env = env
        self.name = name
        self.state = ProcessState(registry: registry)
    }

    /// The pid of whichever subprocess ``respawn()`` most recently spawned and
    /// no teardown path has since torn down, or `nil` when nothing is live.
    ///
    /// Package-internal: a test asserts teardown "by pid, not by inference"
    /// through it. A host never needs it to use ``respawn()`` and
    /// ``shutdown()`` correctly.
    var currentPid: pid_t? { state.pid }

    /// Spawns a fresh server subprocess in its own process group and vends a
    /// transport wired to its stdio pipes, wrapped so that its own
    /// `disconnect()` also tears the subprocess down (teardown path 2 in the
    /// header of this file).
    ///
    /// Tears down (group-kills and reaps) whatever this value fronted before
    /// it spawns the new one (teardown path 3) — a no-op when nothing was
    /// recorded, and otherwise what reaps a process that died on its own
    /// between the last spawn and this one.
    ///
    /// The signature matches the transport factory a server connects through
    /// (`@Sendable () async throws -> any Transport`), so `stdio.respawn` goes
    /// to the server directly: to reconnect a stdio server is to respawn it,
    /// and this is what does that.
    ///
    /// - Returns: A `Transport` wired to the freshly spawned subprocess.
    /// - Throws: ``StdioServerProcessError/pipeCreationFailed(errno:)`` when a
    ///   pipe cannot be created, or
    ///   ``StdioServerProcessError/spawnFailed(command:errno:)`` when
    ///   `posix_spawn` itself fails. `spawnFailed` reports `isNonRetryable`
    ///   `true`, so a server that connects through this method fails at once
    ///   on a `command` that will never spawn; `pipeCreationFailed` still
    ///   takes the normal retry schedule.
    public func respawn() async throws -> any Transport {
        state.terminateCurrent()
        let spawned = try Self.spawn(command: command, args: args, env: env)
        state.recordSpawn(spawned.pid)
        return StdioServerTransport(inner: spawned.transport, state: state, pid: spawned.pid)
    }

    /// Group-terminates and reaps whatever subprocess this value fronts
    /// (teardown path 1) — a no-op when nothing is live.
    ///
    /// A host calls this once it is done with the server for good, beside or
    /// in place of a disconnect of the server built over it, so the
    /// subprocess goes away promptly instead of waiting for connection
    /// teardown or owner teardown to catch it.
    public func shutdown() async {
        state.terminateCurrent()
    }

    // MARK: - Spawning

    /// One freshly spawned subprocess and the transport wired to it.
    private struct Spawned {
        /// The pid of the subprocess (equal to its process-group id).
        let pid: pid_t
        /// The transport wired to its stdio pipes.
        let transport: StdioTransport
    }

    /// The fd of the child that becomes its standard input.
    private static let childStdinFd: Int32 = 0

    /// The fd of the child that becomes its standard output.
    private static let childStdoutFd: Int32 = 1

    /// The fd of the child that is its standard error, redirected to
    /// `/dev/null` by `spawnChild` — `spawnChild` wires fd 0 and fd 1 by
    /// parameter, and this names the third.
    private static let childStderrFd: Int32 = 2

    /// The path the standard error of the child goes to.
    private static let childStderrPath = "/dev/null"

    /// Spawns `command` with `args` in its own process group, pipes its
    /// stdin and stdout, and returns the pid plus a `StdioTransport` over
    /// those pipes.
    ///
    /// Raw `posix_spawn`, and not `Foundation.Process` (which exposes no
    /// public way to put a child in its own group before it execs), so that
    /// `POSIX_SPAWN_SETPGROUP` sets the group atomically as part of the spawn
    /// — no race against a fast-forking child, which a `setpgid` from the
    /// parent after the fact would have. The stderr of the child goes to
    /// `/dev/null`.
    ///
    /// - Parameters:
    ///   - command: The absolute path to the executable.
    ///   - args: The arguments to pass.
    ///   - env: The environment variables to layer onto the inherited
    ///     environment (see ``env`` for the augment-not-replace decision).
    /// - Returns: The spawned pid and its wired-up transport.
    /// - Throws: ``StdioServerProcessError/pipeCreationFailed(errno:)`` when a
    ///   pipe cannot be created, or
    ///   ``StdioServerProcessError/spawnFailed(command:errno:)`` when
    ///   `posix_spawn` itself fails.
    private static func spawn(
        command: String, args: [String], env: [EnvVariable]
    ) throws -> Spawned {
        let (stdinReadFd, stdinWriteFd) = try createPipe()
        // The parent keeps this fd open for the life of the connection to
        // write requests to the child. If the child dies while this fd is
        // open, a later write hits a pipe with no reader, and the default
        // POSIX disposition for that is `SIGPIPE`, which terminates the WHOLE
        // host process. `F_SETNOSIGPIPE` makes a write to this one fd fail
        // with `EPIPE` instead, which `StdioTransport.send(_:)` turns into an
        // ordinary thrown error. Scoped to this fd, and not a process-wide
        // `signal(SIGPIPE, SIG_IGN)`, so the host's own sockets and pipes keep
        // whatever disposition they rely on.
        _ = fcntl(stdinWriteFd, F_SETNOSIGPIPE, 1)

        let (stdoutReadFd, stdoutWriteFd): (Int32, Int32)
        do {
            (stdoutReadFd, stdoutWriteFd) = try createPipe()
        } catch {
            closeAll([stdinReadFd, stdinWriteFd])
            throw error
        }

        let pid: pid_t
        do {
            pid = try spawnChild(
                command: command, args: args, env: env,
                childStdin: stdinReadFd, childStdout: stdoutWriteFd,
                parentSideFdsToClose: [stdinWriteFd, stdoutReadFd])
        } catch {
            // `spawnChild` failed before any child inherited these fds
            // (`posix_spawn_file_actions` takes effect only inside a spawned
            // child), so all four fds this call created are still ours to
            // close — each one would otherwise leak on every failed attempt.
            closeAll([stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd])
            throw error
        }

        // The parent's copies of the child's ends: `posix_spawn_file_actions`
        // closes fds inside the child only, never in this process, so these
        // must close here or every spawn leaks two fds.
        closeAll([stdinReadFd, stdoutWriteFd])

        let transport = StdioTransport(
            input: FileDescriptor(rawValue: stdoutReadFd),
            output: FileDescriptor(rawValue: stdinWriteFd)
        )
        return Spawned(pid: pid, transport: transport)
    }

    /// Closes each fd of `fds` in this process.
    ///
    /// - Parameter fds: The fds to close.
    private static func closeAll(_ fds: [Int32]) {
        for fd in fds {
            close(fd)
        }
    }

    /// Creates a pipe, and returns its read end and its write end.
    ///
    /// `spawn` needs this twice (one time for stdin, one time for stdout), so
    /// the `pipe(_:)` call and its error translation stand here one time.
    ///
    /// - Returns: The `(readFd, writeFd)` pair `pipe(_:)` produced.
    /// - Throws: ``StdioServerProcessError/pipeCreationFailed(errno:)`` when
    ///   `pipe(_:)` fails.
    private static func createPipe() throws -> (readFd: Int32, writeFd: Int32) {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else {
            throw StdioServerProcessError.pipeCreationFailed(errno: errno)
        }
        return (fds[0], fds[1])
    }

    /// Performs the `posix_spawn` call: wires `childStdin` and `childStdout`
    /// onto fd 0 and fd 1 of the child, sends fd 2 to `/dev/null`, and puts
    /// the child in its own process group.
    ///
    /// - Parameters:
    ///   - command: The absolute path to the executable.
    ///   - args: The arguments to pass.
    ///   - env: The environment variables to layer onto the inherited environment.
    ///   - childStdin: The fd (the read end of the stdin pipe) that becomes fd 0 of the child.
    ///   - childStdout: The fd (the write end of the stdout pipe) that becomes fd 1 of the child.
    ///   - parentSideFdsToClose: The parent's own ends of the pipes, closed in
    ///     the child only — the caller still closes its own copies afterward,
    ///     because `posix_spawn_file_actions` never touches the fd table of the
    ///     calling process.
    /// - Returns: The spawned pid.
    /// - Throws: ``StdioServerProcessError/spawnFailed(command:errno:)`` when
    ///   `posix_spawn` fails.
    private static func spawnChild(
        command: String, args: [String], env: [EnvVariable],
        childStdin: Int32, childStdout: Int32, parentSideFdsToClose: [Int32]
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_adddup2(&fileActions, childStdin, childStdinFd)
        posix_spawn_file_actions_adddup2(&fileActions, childStdout, childStdoutFd)
        posix_spawn_file_actions_addopen(&fileActions, childStderrFd, childStderrPath, O_WRONLY, 0)
        // Close every pipe fd this parent owns inside the post-fork image of
        // the child — it inherited copies of all four, and only the two dup2
        // targets above may stay live.
        for fd in [childStdin, childStdout] + parentSideFdsToClose {
            posix_spawn_file_actions_addclose(&fileActions, fd)
        }

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)

        let argv: [UnsafeMutablePointer<CChar>?] = ([command] + args).map { strdup($0) } + [nil]
        defer { Self.freePointers(argv) }

        let environment = Self.buildEnvironment(augmentingWith: env)
        defer { Self.freePointers(environment) }

        var pid: pid_t = 0
        let spawnResult = posix_spawn(&pid, command, &fileActions, &attr, argv, environment)
        guard spawnResult == 0 else {
            throw StdioServerProcessError.spawnFailed(command: command, errno: spawnResult)
        }
        return pid
    }

    /// Builds a null-terminated `"KEY=VALUE"` environment array: the inherited
    /// environment of this process (`environ`) with `overrides` on top, the
    /// later entry winning on a name collision — the mechanics behind the
    /// augment-not-replace contract of ``env``.
    ///
    /// - Parameter overrides: The variables to layer onto the inherited
    ///   environment.
    /// - Returns: A null-terminated array of `strdup`'d `"KEY=VALUE"` C
    ///   strings; the caller must `free` each non-nil entry once `posix_spawn`
    ///   returns.
    private static func buildEnvironment(
        augmentingWith overrides: [EnvVariable]
    ) -> [UnsafeMutablePointer<CChar>?] {
        var merged: [String: String] = [:]
        var order: [String] = []
        var index = 0
        while let entry = environ[index] {
            defer { index += 1 }
            let pair = String(cString: entry)
            guard let separator = pair.firstIndex(of: "=") else { continue }
            let key = String(pair[pair.startIndex..<separator])
            let value = String(pair[pair.index(after: separator)...])
            if merged.updateValue(value, forKey: key) == nil {
                order.append(key)
            }
        }
        for variable in overrides {
            if merged.updateValue(variable.value, forKey: variable.name) == nil {
                order.append(variable.name)
            }
        }
        return order.map { strdup("\($0)=\(merged[$0] ?? "")") } + [nil]
    }

    /// Frees every non-nil `strdup`'d C string in `pointers` — the cleanup the
    /// `argv` and `environment` `defer` blocks of `spawnChild` share.
    ///
    /// - Parameter pointers: The pointers to free; `nil` entries (the null
    ///   terminator) are skipped.
    private static func freePointers(_ pointers: [UnsafeMutablePointer<CChar>?]) {
        for case let pointer? in pointers {
            free(pointer)
        }
    }
}

/// `commandNotAbsolute` and `spawnFailed` are permanent configuration
/// failures, not flaky connections: a bad `command` path never spawns, however
/// often it is retried. `pipeCreationFailed` is left out on purpose — a pipe
/// fails on fd exhaustion in THIS process (`EMFILE`, `ENFILE`), which is
/// plausibly transient, unlike a `command` that will never exist.
extension StdioServerProcess.StdioServerProcessError: NonRetryableConnectError {
    /// Whether this error is a permanent configuration failure
    /// (``commandNotAbsolute(_:)`` and ``spawnFailed(command:errno:)``) or a
    /// transient, retryable condition (``pipeCreationFailed(errno:)``).
    public var isNonRetryable: Bool {
        switch self {
        case .commandNotAbsolute, .spawnFailed:
            return true
        case .pipeCreationFailed:
            return false
        }
    }
}

/// The shared, class-backed bookkeeping behind one `StdioServerProcess` (and
/// every `StdioServerTransport` it vends): which pid, if any, is live, and the
/// `ProcessRegistry` it is registered into.
///
/// A plain `final class` and not an actor, for the reason `ProcessRegistry`
/// itself gives: `deinit` cannot `await`, so the state it touches (a
/// `Mutex`-guarded optional pid) must be reachable without one.
private final class ProcessState: Sendable {
    /// The live pid, or `nil` when nothing is fronted.
    private let currentPid = Mutex<pid_t?>(nil)

    /// The registry every recorded pid is registered into and deregistered
    /// from.
    private let registry: ProcessRegistry

    /// Creates process-state bookkeeping backed by `registry`.
    ///
    /// - Parameter registry: The registry every spawned pid is registered
    ///   into and deregistered from.
    init(registry: ProcessRegistry) {
        self.registry = registry
    }

    /// The live pid, or `nil` when nothing is fronted.
    var pid: pid_t? { currentPid.withLock { $0 } }

    /// Records `pid` as the live subprocess and registers it — called once a
    /// fresh spawn has already torn down whatever THIS `respawn()` call
    /// fronted before.
    ///
    /// That pre-spawn teardown cannot rule out a SECOND `respawn()` call on the
    /// same value running at the same time: two racing calls can each pass
    /// their own `terminateCurrent()` and each spawn a real child before
    /// either records it here. A plain overwrite of `currentPid` would orphan
    /// the pid recorded first — still in the registry, so the `atexit` sweep
    /// would reach it, but unreachable by every teardown path of this type.
    /// The race is real: a server races a connect attempt against a timeout,
    /// and an abandoned attempt's factory call is not cancelled, so it can
    /// still be spawning when a retry's call runs beside it.
    ///
    /// So this swaps and evicts atomically: whichever call runs second finds
    /// the first pid still in `currentPid` and tears THAT one down before it
    /// returns, so at most one live, registered pid survives any interleaving.
    ///
    /// - Parameter pid: The freshly spawned pid to record.
    func recordSpawn(_ pid: pid_t) {
        let evicted = currentPid.withLock { current -> pid_t? in
            let previous = current
            current = pid
            return previous
        }
        registry.register(pid)
        if let evicted {
            killReapAndDeregister(evicted)
        }
    }

    /// Group-kills and reaps whatever pid is recorded, then deregisters it. A
    /// no-op when nothing is recorded.
    ///
    /// Idempotent by construction (the "take and clear" inside the lock), so
    /// each of the four teardown triggers may call this safely, in any order,
    /// any number of times, with no double kill and no double reap: `killpg`
    /// on a dead group is a harmless `ESRCH`, and `waitpid` runs exactly one
    /// time per pid, when this method took it out of `currentPid`.
    func terminateCurrent() {
        guard let pid = currentPid.withLock({ let recorded = $0; $0 = nil; return recorded }) else {
            return
        }
        killReapAndDeregister(pid)
    }

    /// Group-kills and reaps `pid`, but only when `pid` is still the recorded
    /// one — a no-op, with `currentPid` untouched, when a DIFFERENT pid is
    /// current, whether because `pid` was evicted by a fresher spawn or was
    /// never current at all.
    ///
    /// Exists for one caller, `StdioServerTransport.dispose()`: a transport
    /// whose own spawn lost the race (its pid evicted, killed and reaped by a
    /// fresher spawn's own `recordSpawn`) must have its `dispose()` be a safe
    /// no-op, and never reach for whatever pid is current NOW — which can be
    /// that fresher, wanted spawn. `terminateCurrent()` cannot express that:
    /// it only knows "whatever is current", never "whether the pid a caller
    /// has in mind is still that".
    ///
    /// - Parameter pid: The pid to terminate, only when `currentPid` holds it.
    func terminateIfCurrent(pid: pid_t) {
        let matched = currentPid.withLock { current -> Bool in
            guard current == pid else { return false }
            current = nil
            return true
        }
        guard matched else { return }
        killReapAndDeregister(pid)
    }

    /// Group-kills and reaps `pid` unconditionally, then deregisters it — the
    /// OS-level teardown sequence that `recordSpawn`, `terminateCurrent()` and
    /// `terminateIfCurrent(pid:)` share, so it stands in one place.
    ///
    /// The caller has already decided `pid` must go; this does the kill, the
    /// reap and the deregister, and none of the `currentPid` bookkeeping that
    /// decides WHICH pid that is.
    ///
    /// - Parameter pid: The pid to group-kill, reap, and deregister.
    private func killReapAndDeregister(_ pid: pid_t) {
        _ = killpg(pid, SIGKILL)
        var status: Int32 = 0
        _ = waitpid(pid, &status, 0)
        registry.deregister(pid)
    }

    /// Owner teardown (path 4 in the header of this file): once nothing
    /// retains this state, ARC runs this synchronously — the same idempotent
    /// teardown every other trigger uses, so it is safe even after an explicit
    /// `shutdown()` already ran.
    deinit {
        terminateCurrent()
    }
}

/// Wraps a real `StdioTransport` so that a disconnect of it also tears down
/// the subprocess it is wired to (teardown path 2 in the header of this file)
/// — the path a host's disconnect of the server built over this transport
/// reaches, without a call to `StdioServerProcess.shutdown()`.
private actor StdioServerTransport: Transport, DisposableTransport {
    /// The real transport this actor delegates every protocol operation to.
    private let inner: StdioTransport

    /// The shared process bookkeeping this transport's `disconnect()` tears
    /// down.
    private let state: ProcessState

    /// The pid of the specific subprocess `respawn()` spawned to produce THIS
    /// transport — captured at construction, never re-derived from
    /// `state.currentPid` later.
    ///
    /// This is what lets `dispose()` tell "my own spawn" from "whatever
    /// `state` holds now": see `ProcessState.terminateIfCurrent(pid:)`.
    private let pid: pid_t

    /// The logger of this transport — the one of `inner`, handed on, so log
    /// output carries the same label an unwrapped `StdioTransport` gives. This
    /// file writes nothing through it; the `Transport` protocol requires the
    /// property, and that is the whole reason it is here.
    nonisolated let logger: Logging.Logger

    /// The receive stream of `inner`, cached by `connect()` — `receive()` is
    /// not `async` in the protocol, so it cannot fetch the stream of `inner`
    /// on demand and returns what `connect()` cached here instead.
    private var cachedReceiveStream: AsyncThrowingStream<Data, Swift.Error>?

    /// Wraps `inner`, tying its lifetime to `state`.
    ///
    /// - Parameters:
    ///   - inner: The real transport to delegate to.
    ///   - state: The shared process bookkeeping to tear down on `disconnect()`.
    ///   - pid: The pid of the subprocess spawned for this transport.
    init(inner: StdioTransport, state: ProcessState, pid: pid_t) {
        self.inner = inner
        self.state = state
        self.pid = pid
        self.logger = inner.logger
    }

    /// Delegates to `inner`, and caches its receive stream for `receive()`.
    func connect() async throws {
        try await inner.connect()
        cachedReceiveStream = await inner.receive()
    }

    /// Delegates to `inner`, then group-kills and reaps the subprocess this
    /// transport is wired to.
    func disconnect() async {
        await inner.disconnect()
        state.terminateCurrent()
    }

    /// Delegates to `inner`.
    func send(_ data: Data) async throws {
        try await inner.send(data)
    }

    /// The `DisposableTransport` conformance: group-kills and reaps the
    /// subprocess this transport is wired to, given that `connect()` never
    /// ran on this instance — but only when that subprocess (`pid`) is still
    /// the one `state` holds as current.
    ///
    /// A `respawn()` that lost the race against a newer connect attempt has
    /// already spawned a real child by the time it returns, and nothing else
    /// would tear it down. This calls `terminateIfCurrent(pid:)` — a compare
    /// and clear on this transport's own `pid` — and not the unconditional
    /// `terminateCurrent()`: a fresher concurrent `respawn()` can already have
    /// evicted this pid and installed its own, wanted pid as current, and
    /// "whatever is current now" would then kill that live process in place of
    /// the dead one this instance owns.
    func dispose() async {
        state.terminateIfCurrent(pid: pid)
    }

    /// The receive stream of `inner`, cached by the most recent `connect()` —
    /// or a finished empty stream when no `connect()` ran yet.
    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        guard let cachedReceiveStream else {
            return AsyncThrowingStream { $0.finish() }
        }
        return cachedReceiveStream
    }
}
