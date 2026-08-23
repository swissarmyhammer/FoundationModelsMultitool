// `ShellRunner` — starts one `sh -c {command}` child, writes its output into
// `ShellState`, and gives back how the child ended.
//
// The child goes into its OWN process group (`platformOptions.processGroupID =
// 0`, which swift-subprocess maps to `POSIX_SPAWN_SETPGROUP` and
// `posix_spawnattr_setpgroup(0)` on Darwin), thus the pid of the child is also
// the identifier of its process group. The time limit and the canceler each send
// `killpg(pid, SIGKILL)`, thus the whole tree dies and a grandchild that the
// command put in the background cannot stay alive. swift-subprocess reaps the
// direct child on each return path of its own `run(...)`. This file must only
// guarantee that the group dies on each exit path of the body, thus that reap
// can complete — see the `defer` inside the closure of the spawn.
//
// **This runner holds no race, no detach and no supervision.** eventplan.md
// § "Consolidation of the siblings" states that "consolidation is promotion, not
// construction", and that "Detach supervision moves to the shared engine". The
// `DetachingTool` engine of Router owns all three now: `run(_:)` is the run body
// that the mailbox parks, and `canceler(completionToken:)` is the canceler that
// the mailbox parks beside it. There is no `wait:` parameter here, there is no
// deadline race, and there is no supervisor.
//
// The canceler holds NO pid of its own. It reads the process group of the run
// from `ShellState.runningProcess(commandID:)` at the moment it runs. The store
// is the one home of that pid, thus the canceler can never signal a process
// group that the store already gave up.
//
// The record of the output is incremental, and it is not one write at the end.
// The two readers of the streams (standard output, standard error) each put
// their raw chunks into one shared `AsyncStream`, and ONE consumer task drains
// that stream in arrival order: it takes the lines that each chunk completes out
// of a private `OutputBuffer` and writes them with `ShellState.appendLines`
// before it looks at the next chunk. One consumer, and not two writers into the
// actor, is deliberate. An actor is reentrant across a suspension point, and the
// order of its mailbox across two callers is not a documented first-in-first-out
// order, thus two producers that each call `appendLines` could land their writes
// out of arrival order. One sequential consumer has no such race: it alone
// touches the buffer, and it alone calls `appendLines`, one call at a time.
//
// That same consumer is where the live view of a subscribed host is teed
// (`outputChunkStream`): each chunk that the consumer takes off the queue goes
// to `ShellOutputChunkStream` raw, before the line buffer sees it, and the one
// terminal marker of the run goes out from the `defer` of `run` — after the task
// group of the output ended, thus the marker can never pass a chunk, and on each
// exit path, thus it goes out exactly one time for each run. To offer a chunk
// never blocks (see the backpressure policy of that type), thus the tee cannot
// slow the consumer down and a host cannot starve it.

import Foundation
import FoundationModelsRouter
import Subprocess
import Synchronization
import System

/// Starts one shell command as an `sh -c` child, streams its output into the
/// shared `ShellState` log, and applies the time limit of the request.
struct ShellRunner {

    /// The cap on the captured output, in bytes (10 MiB), which the standard
    /// output and the standard error share.
    static let defaultMaxOutputSize = 10_485_760

    /// The exit code the runner reports when a run has none to report: a death
    /// by signal, a time limit, a cancel, or a spawn that never happened.
    static let absentExitCode = -1

    /// The absolute path of the shell each command runs under.
    private static let shellPath = "/bin/sh"

    /// The flag that makes the shell read the command from its next argument.
    private static let shellCommandFlag = "-c"

    /// The store this runner writes the record and the output of each run into.
    let state: ShellState

    /// The cap on the captured output, in bytes, which the standard output and
    /// the standard error share.
    ///
    /// It takes `defaultMaxOutputSize` by default. A test gives a small cap
    /// here, thus it can prove the truncation with no 10 MiB of output.
    var maxOutputSize: Int = ShellRunner.defaultMaxOutputSize

    /// The registry of process groups that each spawned child goes into for the
    /// length of its run, and that the teardown of the run takes it out of.
    ///
    /// It takes `ProcessRegistry.global` by default, thus a production run
    /// stands behind the `atexit` sweep of that registry. A test that must read
    /// or sweep the state of a registry gives a private `ProcessRegistry()` —
    /// see the doc comment of `ProcessRegistry.global` for the reason.
    var registry: ProcessRegistry = .global

    /// The live view of the output that each command of this runner tees its raw
    /// chunks into, or `nil` — the default where no host subscribed — to tee
    /// nothing.
    ///
    /// The tee happens inside `consume`, off the same one ordered queue that
    /// feeds the line buffer, thus a host that watches the stream can neither
    /// reorder the internal consumer nor starve it. See `ShellOutputChunkStream`
    /// for the backpressure policy, which never blocks and reports a gap, and
    /// which thus makes a slow host harmless to the child.
    var outputChunkStream: ShellOutputChunkStream?

    /// The confinement each command of this runner spawns under, or `nil` — the
    /// default — to start the shell directly, with no confinement.
    ///
    /// `nil` is deliberately not `UnconfinedSandbox`: the default path builds
    /// the same `/bin/sh -c command` configuration it always built, with no step
    /// of confinement in it at all, thus a host that opts in to nothing runs
    /// exactly the code it ran before. `UnconfinedSandbox` stays the meaning of
    /// "no confinement" for a caller that wants to state that choice as a value.
    ///
    /// A sandbox that is there decides the executable and the arguments of each
    /// spawn (see `configuration(for:)`), and `run` asks it INSIDE its own
    /// `do`/`catch`, thus a sandbox that cannot build the confinement finalizes
    /// the record and throws again instead of a quiet spawn with no confinement.
    var sandbox: (any CommandSandbox)?

    /// One request to run a command.
    struct Request: Sendable {

        /// The command line that goes to `sh -c`.
        var command: String

        /// The completion token of the run.
        ///
        /// The caller mints it with `SessionMailbox.makeCompletionToken()` and
        /// gives it here. It is the identifier of the record in `ShellState`, it
        /// is the `correlationID` of each event the run posts, and it is the
        /// token that `canceler(completionToken:)` takes. One string on two
        /// planes — see `ShellState.startCommand(_:commandID:)`.
        var completionToken: String

        /// The directory the command runs in, or `nil` to take the current
        /// directory of this process.
        var workingDirectory: String?

        /// The environment variables that stand on top of the environment this
        /// process gives the child.
        var environment: [String: String]

        /// The time limit on the wall clock, or `nil` for no limit.
        var timeout: Duration?

        /// Makes a request to run a command.
        ///
        /// - Parameters:
        ///   - command: The command line that goes to `sh -c`.
        ///   - completionToken: The completion token of the run.
        ///   - workingDirectory: The directory the command runs in, or `nil` to
        ///     take the current directory of this process.
        ///   - environment: The environment variables that stand on top of the
        ///     environment this process gives the child.
        ///   - timeout: The time limit on the wall clock, or `nil` for no limit.
        init(
            command: String,
            completionToken: String,
            workingDirectory: String? = nil,
            environment: [String: String] = [:],
            timeout: Duration? = nil
        ) {
            self.command = command
            self.completionToken = completionToken
            self.workingDirectory = workingDirectory
            self.environment = environment
            self.timeout = timeout
        }
    }

    /// How one run ended.
    ///
    /// It carries no identifier: the caller gave the completion token in the
    /// request, thus it already holds the one identifier of the run.
    struct Outcome: Sendable {

        /// The status the run ended in: `.completed` or `.timedOut`.
        ///
        /// A cancel never reaches this value. The canceler writes `.killed` into
        /// the record itself, and the finalize of the body then does nothing —
        /// see `canceler(completionToken:)`.
        var status: CommandStatus

        /// The exit code the child gave, or `absentExitCode` when the run has
        /// none to report.
        var exitCode: Int
    }

    /// Which child task of the task group of the output ended.
    private enum BodyEvent: Sendable {

        /// One reader of a stream reached the end of that stream.
        case streamFinished

        /// The consumer drained the queue and sealed the line buffer.
        case consumerFinished

        /// The timer of the time limit ended, either because the limit came or
        /// because the group cancelled the timer.
        case timerFinished
    }

    /// One raw chunk that a reader took from the standard output or the standard
    /// error of the child, with the stream it came from.
    ///
    /// The two readers put their chunks into one `AsyncStream`, thus `consume`
    /// takes the lines out and writes them strictly in arrival order — see the
    /// header of this file.
    private struct StreamChunk: Sendable {

        /// The stream the bytes came from.
        let stream: ShellOutputStream

        /// The raw bytes, exactly as the reader took them.
        let bytes: [UInt8]
    }

    // MARK: - The canceler

    /// The canceler of the run under `completionToken`: it kills the process
    /// group of the child and reports `.stopped`.
    ///
    /// This is the closure that `SessionMailbox.park(kind:)` takes beside the
    /// run body. It holds NO pid of its own. It reads the process group from
    /// `ShellState.runningProcess(commandID:)` at the moment it runs, thus the
    /// store stays the one home of that pid and a stale pid cannot reach a
    /// process group that the store already gave up.
    ///
    /// The order of the two steps is load bearing:
    ///
    /// 1. Read the pid. `completeCommand` drops the entry of the process group
    ///    as it finalizes a record, thus a read after the write finds nothing.
    /// 2. Write `.killed` with `completeIfRunning`, which is one hop of the
    ///    actor. The body still runs at this point, thus this write wins, and
    ///    the finalize of the body then finds a record that no longer runs and
    ///    does nothing.
    /// 3. Send `killpg(SIGKILL)`.
    ///
    /// The outcome is `.stopped`, and it is never `.cancelled`: `killpg` on the
    /// own process group of the child is authoritative, thus the work is
    /// certainly dead. The shared vocabulary keeps `.cancelled` for advisory
    /// cancellation, where the work can go on.
    ///
    /// A token that no command started under, and a run that already ended, each
    /// make a canceler that signals nothing and still reports `.stopped`.
    ///
    /// - Parameter completionToken: The completion token of the run to stop.
    /// - Returns: The canceler of that run.
    func canceler(completionToken: String) -> @Sendable () async -> OperationOutcome {
        let state = state
        return {
            let pid = await state.runningProcess(commandID: completionToken)
            await state.completeIfRunning(
                commandID: completionToken, status: .killed, exitCode: Self.absentExitCode)
            if let pid {
                _ = killpg(pid, SIGKILL)
            }
            return .stopped
        }
    }

    // MARK: - The run body

    /// Runs `request` to its end, and gives back how it ended.
    ///
    /// This is the whole body of one run: the spawn, the drain of the two
    /// streams, the teardown that kills the process group, and the finalize of
    /// the record. It is the body that `SessionMailbox.park(kind:)` takes, thus
    /// it takes no `wait:` of its own and it races no deadline.
    ///
    /// `state.completeIfRunning` runs on each path out of `Subprocess.run`, and
    /// not on the normal return alone. The `catch` finalizes and throws again
    /// for a spawn that never happened — a `workingDirectory` that is not there,
    /// or a `sandbox` that cannot build the confinement for this request —
    /// exactly as it does for a failure of the pipeline in the middle of a run,
    /// such as a throw from `state.appendLines`. Both report `.completed` with
    /// `absentExitCode`, the same pair a death by signal takes: neither one has
    /// an exit code to report, and neither one is a time limit or a cancel.
    /// Without that finalize the record that `startCommand` made would stay
    /// `.running` for ever, and the run plane would report a command that never
    /// existed.
    ///
    /// The `defer` below delivers the one terminal marker of the run to a
    /// subscribed host. This function runs exactly one time for each completion
    /// token, and the `defer` fires on each path out of it, thus "exactly one
    /// time" needs no bookkeeping. It also fires strictly after `Subprocess.run`
    /// returns, thus after the task group of the output ended, thus the marker
    /// can never pass a chunk.
    ///
    /// The limit on the length of the command and the limit on the length of an
    /// environment value are **not** examined again here. They belong to
    /// `ShellPolicy`, which the caller runs before this call. The runner takes
    /// input that is already examined, and the one cap it owns itself is
    /// `maxOutputSize`.
    ///
    /// - Parameter request: The command to run.
    /// - Returns: The status and the exit code of the run.
    /// - Throws: What `Subprocess.run` throws for a child that never started,
    ///   what `sandbox.wrap` throws for a confinement it cannot build, or what
    ///   the pipeline of the output throws in the middle of a run.
    func run(_ request: Request) async throws -> Outcome {
        let commandID = request.completionToken
        await state.startCommand(request.command, commandID: commandID)
        defer { outputChunkStream?.complete(commandID: commandID) }

        do {
            // Built INSIDE the `do`, and not above it, because `sandbox.wrap`
            // can throw — a wrapper binary that is not there, or a working
            // directory outside the roots of the confinement — and that throw
            // must reach the `catch` below.
            let configuration = try configuration(for: request)

            let result = try await Subprocess.run(
                configuration, input: .none, output: .sequence, error: .sequence
            ) { execution in
                let pid = execution.processIdentifier.value
                await state.registerProcess(commandID: commandID, pid: pid)
                registry.register(pid)
                // The teardown that each exit path of the body takes — a normal
                // end, a time limit, a cancel, or a thrown error. The kill of
                // the group makes each grandchild that the command put in the
                // background die, thus the reap of the library can complete. To
                // kill a group that is already dead gives a harmless `ESRCH`.
                // The deregister leaves the registry with nothing for a later
                // `sweep(_:)` to kill again.
                defer {
                    _ = killpg(pid, SIGKILL)
                    registry.deregister(pid)
                }

                return try await waitForCompletion(
                    stdout: execution.standardOutput,
                    stderr: execution.standardError,
                    commandID: commandID,
                    timeout: request.timeout,
                    pid: pid
                )
            }

            let outcome = finalizeResult(
                timedOut: result.closureResult, terminationStatus: result.terminationStatus)
            await state.completeIfRunning(
                commandID: commandID, status: outcome.status, exitCode: outcome.exitCode)
            return outcome
        } catch {
            await state.completeIfRunning(
                commandID: commandID, status: .completed, exitCode: Self.absentExitCode)
            throw error
        }
    }

    // MARK: - The configuration of the spawn

    /// The configuration to spawn for `request`, which `sandbox` decorates when
    /// this runner carries one.
    ///
    /// With no sandbox this is exactly the configuration the runner always
    /// built — `/bin/sh` with `["-c", command]` — and it reads nothing else,
    /// thus the path with no confinement carries no code of confinement at all.
    ///
    /// With a sandbox the executable and the arguments come from `wrap`, and
    /// nothing else changes. The environment, the working directory and the
    /// platform options stay exactly as they are, because a wrapper starts its
    /// target in place and keeps the pid it took. Thus the process group of the
    /// child, the entry in the registry and the teardown with `killpg` behave
    /// the same way with a wrapper in front of the shell and without one.
    ///
    /// - Parameter request: The command to spawn.
    /// - Returns: The configuration that goes to `Subprocess.run`.
    /// - Throws: What `sandbox.wrap` throws when it cannot build the
    ///   confinement. There is no fall back to a spawn with no confinement, thus
    ///   a caller must call this where that throw is finalized — see `run(_:)`.
    private func configuration(for request: Request) throws -> Configuration {
        var executable = Self.shellPath
        var arguments = [Self.shellCommandFlag, request.command]

        if let sandbox {
            let directories = Self.resolvedSandboxDirectories(request: request)
            let invocation = try sandbox.wrap(
                shellPath: executable,
                shellArguments: arguments,
                workingDirectory: directories.work,
                temporaryDirectory: directories.tmp
            )
            executable = invocation.executable
            arguments = invocation.arguments
        }

        return Configuration(
            executable: .path(FilePath(executable)),
            arguments: Arguments(arguments),
            environment: environment(overriding: request.environment),
            workingDirectory: request.workingDirectory.map { FilePath($0) },
            platformOptions: ownProcessGroupOptions()
        )
    }

    /// The working directory and the temporary directory to give a
    /// `CommandSandbox` for `request`, each one with its symbolic links
    /// resolved.
    ///
    /// To discharge the path precondition of `CommandSandbox` is the work of the
    /// runner: Seatbelt matches the path of the vnode that the kernel resolved,
    /// thus a grant that names `/tmp`, or a raw `$TMPDIR`, never matches the
    /// `/private/tmp` or the `/private/var/folders/…` the kernel sees, and the
    /// sandbox then refuses in silence what it appears to permit.
    ///
    /// The working directory falls back to the current directory of this
    /// process, which is what `Configuration` takes for a `workingDirectory` of
    /// `nil`, thus the sandbox learns the directory the command truly runs in.
    ///
    /// It is `static` because a test proves the resolution on its own, with no
    /// runner and no spawn.
    ///
    /// - Parameter request: The command whose directories to resolve.
    /// - Returns: The resolved working directory and temporary directory.
    static func resolvedSandboxDirectories(request: Request) -> (work: String, tmp: String) {
        (
            work: resolvedDirectory(
                path: request.workingDirectory ?? FileManager.default.currentDirectoryPath),
            tmp: resolvedDirectory(path: NSTemporaryDirectory())
        )
    }

    /// `path` with any trailing separator removed and each symbolic link
    /// component followed.
    ///
    /// The resolution itself is `resolvedPath`, the one resolver of this module.
    /// There is no second copy of that step here, on purpose: a copy can name a
    /// different path than the confinement enforces, and nothing reports the
    /// disagreement. What this member adds is the trailing separator, which
    /// `NSTemporaryDirectory()` carries and which a Seatbelt grant must not.
    ///
    /// A path that is not there has nothing to resolve, thus the input comes
    /// back as it came in, with the trailing separator still removed. That
    /// widens nothing in silence: the value goes on to a sandbox that either
    /// refuses it or grants exactly what it names, and the spawn of a working
    /// directory that is not there fails by itself.
    ///
    /// **This member is the one DIRECTORY resolver of the runner, and each
    /// caller must use it — a test included.** The two steps travel together:
    /// a caller that reaches past it to `resolvedPath` alone keeps a trailing
    /// separator the grant must not carry, and a caller that spells the trim
    /// again writes a second copy that can drift. It is `internal` rather than
    /// `private` for that reason, exactly as `resolvedSandboxDirectories` is
    /// `static`: a test states the contract by naming this member, and never by
    /// rebuilding it.
    ///
    /// The parameter carries a label because this is a semantic transformation
    /// and not a value-preserving conversion: it follows symbolic links and it
    /// removes a trailing separator, thus the value that comes back can name a
    /// different path than the value that went in.
    ///
    /// - Parameter path: The path to resolve.
    /// - Returns: The resolved path, or `path` itself when it does not resolve.
    static func resolvedDirectory(path: String) -> String {
        let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        return resolvedPath(trimmed)
    }

    /// The platform options that put the child in its own process group, thus
    /// the identifier of that group is the pid of the child and each `killpg`
    /// above reaches the tree of this command alone.
    ///
    /// - Returns: The platform options of the spawn.
    private func ownProcessGroupOptions() -> PlatformOptions {
        var options = PlatformOptions()
        options.processGroupID = 0
        return options
    }

    /// The environment of the child: the environment this process holds, with
    /// `overrides` on top of it — added, and not in place of it.
    ///
    /// - Parameter overrides: The variables the request states.
    /// - Returns: The environment that goes into the configuration.
    private func environment(overriding overrides: [String: String]) -> Environment {
        guard !overrides.isEmpty else { return .inherit }
        var updates: [Environment.Key: String?] = [:]
        for (key, value) in overrides {
            if let environmentKey = Environment.Key(rawValue: key) {
                updates[environmentKey] = value
            }
        }
        return Environment.inherit.updating(updates)
    }

    // MARK: - The drain of the output, and the time limit

    /// Runs the task group of the output of one child to its end.
    ///
    /// The two readers of the streams put their raw chunks into one shared
    /// `AsyncStream`, one consumer task takes the lines out and writes them with
    /// `state.appendLines` in arrival order (see the header of this file), and a
    /// timer that is there kills the process group of `pid` when the limit comes
    /// first. The call returns once the two streams reached their end and the
    /// consumer sealed the buffer. Only then does it cancel a timer that still
    /// waits, thus the end of the streams races the time limit.
    ///
    /// - Parameters:
    ///   - stdout: The standard output of the child.
    ///   - stderr: The standard error of the child.
    ///   - commandID: The completion token of the run.
    ///   - timeout: The time limit on the wall clock, or `nil` for no limit.
    ///   - pid: The pid of the child, which is the identifier of its process
    ///     group.
    /// - Returns: `true` when the time limit fired, and `false` otherwise.
    /// - Throws: What the pipeline of the output throws, above all a throw from
    ///   `state.appendLines`.
    private func waitForCompletion(
        stdout: SubprocessOutputSequence,
        stderr: SubprocessOutputSequence,
        commandID: String,
        timeout: Duration?,
        pid: pid_t
    ) async throws -> Bool {
        let timedOutFlag = Mutex<Bool>(false)
        let (chunkStream, chunkContinuation) = AsyncStream<StreamChunk>.makeStream()
        try await withThrowingTaskGroup(of: BodyEvent.self) { group in
            // The two output streams of the child, one reader task for each,
            // driven off this table instead of written out one time for each
            // stream: the tasks differ in the sequence they read and in the
            // stream they tag it with, and in nothing else. The length of the
            // table is also the count of ends the loop below waits for before it
            // closes the queue of chunks, thus a stream that is added here or
            // taken away here cannot fall out of step with that handshake.
            let readers: [(sequence: SubprocessOutputSequence, stream: ShellOutputStream)] = [
                (stdout, .stdout), (stderr, .stderr),
            ]
            for (sequence, stream) in readers {
                group.addTask {
                    await drain(sequence, from: stream, into: chunkContinuation)
                    return .streamFinished
                }
            }
            group.addTask {
                try await consume(chunkStream, commandID: commandID)
                return .consumerFinished
            }
            if let timeout {
                addTimeoutTask(to: &group, after: timeout, pid: pid) {
                    timedOutFlag.withLock { $0 = true }
                }
            }

            try await drainBodyEvents(
                group: &group, readerCount: readers.count, chunkContinuation: chunkContinuation)
        }

        return timedOutFlag.withLock { $0 }
    }

    /// Drains the task group of `waitForCompletion` until the two readers
    /// reached the end of their streams and the consumer ended, then cancels
    /// whatever is left — most often a timer that still waits.
    ///
    /// The end of the two streams ends the queue of chunks, thus the consumer
    /// can take the last chunks, seal the buffer and return. Only once the
    /// consumer ALSO ended is there nothing more to wait for. Only
    /// `.streamFinished` needs bookkeeping, through `handleStreamFinished`.
    /// `.consumerFinished` sets a flag, and `.timerFinished` needs nothing at
    /// all: the `switch` names all three because the enumeration holds three
    /// cases, and not because each one carries the same work.
    ///
    /// - Parameters:
    ///   - group: The task group of `waitForCompletion`.
    ///   - readerCount: How many reader tasks went into `group` — the count of
    ///     ends that `handleStreamFinished` waits for.
    ///   - chunkContinuation: The shared queue of chunks to finish once each
    ///     reader reached the end of its stream.
    /// - Throws: What a child task of the group throws.
    private func drainBodyEvents(
        group: inout ThrowingTaskGroup<BodyEvent, Error>,
        readerCount: Int,
        chunkContinuation: AsyncStream<StreamChunk>.Continuation
    ) async throws {
        var streamsDone = 0
        var consumerDone = false
        while let event = try await group.next() {
            switch event {
            case .streamFinished:
                handleStreamFinished(
                    streamsDone: &streamsDone, expecting: readerCount,
                    chunkContinuation: chunkContinuation)
            case .consumerFinished:
                consumerDone = true
            case .timerFinished:
                break
            }
            if streamsDone == readerCount, consumerDone {
                group.cancelAll()
                return
            }
        }
    }

    /// Handles one `.streamFinished` event.
    ///
    /// It counts the readers that reached the end of their stream and, once each
    /// one did, it finishes `chunkContinuation`, thus the consumer can take its
    /// last chunks and seal the buffer.
    ///
    /// - Parameters:
    ///   - streamsDone: The running count of readers that reached the end.
    ///   - expecting: How many readers there are — taken from the table that
    ///     started them, and not held as a constant here, because a count that
    ///     is too low leaves the consumer on a queue that never ends, and a
    ///     count that is too high seals the buffer while a reader still writes.
    ///   - chunkContinuation: The shared queue of chunks to finish at the end.
    private func handleStreamFinished(
        streamsDone: inout Int,
        expecting: Int,
        chunkContinuation: AsyncStream<StreamChunk>.Continuation
    ) {
        streamsDone += 1
        if streamsDone == expecting {
            chunkContinuation.finish()
        }
    }

    /// Adds the timer of the time limit to the task group of
    /// `waitForCompletion`: it waits for `timeout` and, when the group does not
    /// cancel it first, it kills the process group of `pid` and reports that the
    /// limit fired.
    ///
    /// It takes a closure instead of the flag itself: a `Mutex` cannot be
    /// copied, thus to give one here as a parameter would consume it, and the
    /// caller still reads it after the group ends. A closure that the call site
    /// captures, in the same scope as that later read, avoids the conflict of
    /// ownership.
    ///
    /// - Parameters:
    ///   - group: The task group of `waitForCompletion`.
    ///   - timeout: How long to wait before the kill of the process group.
    ///   - pid: The pid of the child, which is the identifier of its process
    ///     group.
    ///   - markTimedOut: What to call when the limit comes before the cancel.
    private func addTimeoutTask(
        to group: inout ThrowingTaskGroup<BodyEvent, Error>,
        after timeout: Duration,
        pid: pid_t,
        markTimedOut: @escaping @Sendable () -> Void
    ) {
        group.addTask {
            if (try? await Task.sleep(for: timeout)) != nil {
                markTimedOut()
                _ = killpg(pid, SIGKILL)
            }
            return .timerFinished
        }
    }

    /// Drains one output stream of the child to its end, and puts each raw chunk
    /// into `continuation` with the stream it came from.
    ///
    /// It keeps reading past the cap of the buffer, thus a child that writes
    /// much never blocks on a full pipe. The `OutputBuffer` of the consumer
    /// simply drops what goes past the cap.
    ///
    /// - Parameters:
    ///   - sequence: The output stream of the child to read.
    ///   - stream: The stream each chunk carries the tag of.
    ///   - continuation: The shared queue of chunks.
    private func drain(
        _ sequence: SubprocessOutputSequence,
        from stream: ShellOutputStream,
        into continuation: AsyncStream<StreamChunk>.Continuation
    ) async {
        do {
            for try await chunk in sequence {
                let bytes = chunk.withUnsafeBytes { Array($0) }
                guard !bytes.isEmpty else { continue }
                continuation.yield(StreamChunk(stream: stream, bytes: bytes))
            }
        } catch {
            // A read that the termination monitor of the library cancelled — an
            // inherited grandchild that holds the pipe, or the kill of the group
            // of this runner — arrives as a thrown error. Read it as the end of
            // the stream.
        }
    }

    /// Drains `stream` strictly in the order the readers wrote into it, and
    /// writes the lines that each chunk completes into the store before it looks
    /// at the next chunk.
    ///
    /// No other caller touches the buffer, and no other caller calls
    /// `appendLines`, thus nothing can reorder the writes — see the header of
    /// this file. Once `stream` ends, because each reader reached the end of its
    /// own stream, it seals the buffer with `OutputBuffer.finish()` and writes
    /// the part lines it still holds, and the marker of the truncation or the
    /// placeholder of the binary content.
    ///
    /// This is also the point of the tee for the live view of a subscribed host:
    /// each chunk goes to `outputChunkStream` BEFORE the line buffer sees it,
    /// because the live view exists to be prompt and to offer a chunk never
    /// blocks. The bytes go on untouched: no `OutputBuffer` stands on that path,
    /// thus no cap of `maxOutputSize`, no marker of truncation and no
    /// placeholder of binary content reach it. Those belong to the stored log,
    /// and not to a stream that keeps the bytes exactly as they came.
    ///
    /// - Parameters:
    ///   - stream: The shared queue of chunks.
    ///   - commandID: The completion token of the run.
    /// - Throws: What `state.appendLines` throws.
    private func consume(_ stream: AsyncStream<StreamChunk>, commandID: String) async throws {
        var buffer = OutputBuffer(maxSize: maxOutputSize)
        for await chunk in stream {
            outputChunkStream?.send(
                commandID: commandID, from: chunk.stream, bytes: chunk.bytes,
                maxSize: maxOutputSize)
            try await flush(chunk, into: &buffer, commandID: commandID)
        }

        let final = buffer.finish()
        guard !final.stdout.isEmpty || !final.stderr.isEmpty else { return }
        try await state.appendLines(
            commandID: commandID, stdout: final.stdout, stderr: final.stderr)
    }

    /// Puts one chunk into `buffer` and writes the lines that the chunk
    /// completes into the store.
    ///
    /// - Parameters:
    ///   - chunk: The chunk the consumer took off the queue.
    ///   - buffer: The private line buffer of this run.
    ///   - commandID: The completion token of the run.
    /// - Throws: What `state.appendLines` throws.
    private func flush(
        _ chunk: StreamChunk, into buffer: inout OutputBuffer, commandID: String
    ) async throws {
        let lines: [String]
        switch chunk.stream {
        case .stdout:
            buffer.appendStdout(chunk.bytes)
            lines = buffer.extractCompletedStdoutLines()
        case .stderr:
            buffer.appendStderr(chunk.bytes)
            lines = buffer.extractCompletedStderrLines()
        }
        guard !lines.isEmpty else { return }
        try await append(lines, from: chunk.stream, commandID: commandID)
    }

    /// Writes `lines` into the store under the stream they came from.
    ///
    /// - Parameters:
    ///   - lines: The lines that completed.
    ///   - stream: The stream they came from.
    ///   - commandID: The completion token of the run.
    /// - Throws: What `state.appendLines` throws.
    private func append(
        _ lines: [String], from stream: ShellOutputStream, commandID: String
    ) async throws {
        switch stream {
        case .stdout:
            try await state.appendLines(commandID: commandID, stdout: lines)
        case .stderr:
            try await state.appendLines(commandID: commandID, stderr: lines)
        }
    }

    // MARK: - The end of a run

    /// Turns the flag of the time limit and the termination status of a child
    /// into the outcome that `run` records and gives back.
    ///
    /// A time limit always reports `.timedOut` with `absentExitCode`, whatever
    /// way the process truly died — the `SIGKILL` of this runner killed it. A
    /// normal end reports the code the child gave, and a death by signal reports
    /// `absentExitCode`, and both are `.completed`.
    ///
    /// - Parameters:
    ///   - timedOut: Tells if the time limit fired.
    ///   - terminationStatus: How the child ended.
    /// - Returns: The status and the exit code of the run.
    private func finalizeResult(
        timedOut: Bool, terminationStatus: TerminationStatus
    ) -> Outcome {
        if timedOut {
            return Outcome(status: .timedOut, exitCode: Self.absentExitCode)
        }
        switch terminationStatus {
        case .exited(let code):
            return Outcome(status: .completed, exitCode: Int(code))
        case .signaled:
            return Outcome(status: .completed, exitCode: Self.absentExitCode)
        }
    }
}
