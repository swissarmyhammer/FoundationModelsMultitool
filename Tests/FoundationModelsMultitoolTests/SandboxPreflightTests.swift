import Synchronization
import Testing

@testable import FoundationModelsMultitool

/// Unit tests for the canary machinery of the sandbox preflight, and for the
/// identity sandbox.
///
/// Each name here is module-internal, thus this file imports with `@testable`.
/// That import boundary is also why the identity sandbox stands here and not
/// beside the public seam tests: `UnconfinedSandbox` is `internal`, and
/// `SandboxSurfaceTests` imports the module plainly to prove the public names
/// are public.
///
/// Four properties are pinned. That the identity sandbox gives the invocation
/// back unchanged and reads neither directory, thus a capability that is built
/// with no sandbox confines nothing. That a canary runs one time for each gate,
/// also when the callers overlap, because the gate holds the run itself and not
/// a flag. That a canary that failed does not latch, thus a configuration that
/// becomes healthy is picked up. And that the live spawn reports the exit code
/// and the standard error of the wrapper, a wrapper that a signal killed
/// included.
@Suite("Sandbox canary preflight")
struct SandboxPreflightTests {

    /// The shell each identity test wraps.
    private static let shellPath = "/bin/sh"

    /// The arguments of that shell.
    private static let shellArguments = ["-c", "echo hi"]

    /// The working directory the identity tests give.
    private static let workingDirectory = "/private/tmp/a"

    /// The temporary directory the identity tests give.
    private static let temporaryDirectory = "/private/tmp/t"

    /// A second working directory, thus one test can show that the identity
    /// sandbox answers the same for two different pairs.
    private static let otherWorkingDirectory = "/private/tmp/b"

    /// A second temporary directory, for the same reason.
    private static let otherTemporaryDirectory = "/private/tmp/u"

    /// The number of callers that reach one gate together in the overlap test.
    private static let overlappingCallerCount = 16

    /// How long the stand-in canary takes in the overlap test.
    ///
    /// A canary that answers at once lets the first caller finish before the
    /// second one starts, thus a gate that cannot hold concurrent callers
    /// together would pass by luck.
    private static let overlappingCanaryDuration = Duration.milliseconds(50)

    /// The wrapper that the two passing live-spawn tests run: it ends at once,
    /// with exit code 0 and no standard error.
    private static let trueExecutable = "/usr/bin/true"

    /// The exit code of a command that failed on its own account.
    private static let failedCommandExitCode: Int32 = 3

    /// The word the failing wrapper writes to standard error.
    private static let failedCommandMessage = "canary-stderr"

    /// The exit code of a wrapper that `SIGKILL` stopped: 128 plus 9, which is
    /// the convention of the shell.
    private static let killedWrapperExitCode: Int32 = 137

    /// Wraps the shell constants above with the identity sandbox.
    ///
    /// - Parameters:
    ///   - workingDirectory: The working directory to give.
    ///   - temporaryDirectory: The temporary directory to give.
    /// - Returns: The spawn decoration the identity sandbox gives back.
    private func unconfinedInvocation(
        workingDirectory: String, temporaryDirectory: String
    ) -> SandboxedInvocation {
        UnconfinedSandbox().wrap(
            shellPath: Self.shellPath,
            shellArguments: Self.shellArguments,
            workingDirectory: workingDirectory,
            temporaryDirectory: temporaryDirectory)
    }

    // MARK: - The identity sandbox

    @Test("the identity sandbox gives the shell invocation back unchanged")
    func unconfinedGivesTheInvocationBack() {
        let invocation = unconfinedInvocation(
            workingDirectory: Self.workingDirectory,
            temporaryDirectory: Self.temporaryDirectory)

        #expect(
            invocation
                == SandboxedInvocation(
                    executable: Self.shellPath, arguments: Self.shellArguments))
    }

    @Test("the identity sandbox pays no attention to the two directories")
    func unconfinedIgnoresBothDirectories() {
        // "Unconfined" means the two directories change nothing. A sandbox that
        // read either one would give two different answers here.
        let first = unconfinedInvocation(
            workingDirectory: Self.workingDirectory,
            temporaryDirectory: Self.temporaryDirectory)
        let second = unconfinedInvocation(
            workingDirectory: Self.otherWorkingDirectory,
            temporaryDirectory: Self.otherTemporaryDirectory)

        #expect(first == second)
    }

    // MARK: - The gate

    @Test("a second call on one gate runs no second canary")
    func canaryRunsOneTimeForEachGate() async throws {
        let counter = CanaryCounter()
        let gate = CanaryGate()

        try await gate.passOnce(counter.run)
        try await gate.passOnce(counter.run)

        #expect(counter.count == 1)
    }

    @Test("callers that overlap on a first call share one canary")
    func overlappingCallersShareOneCanary() async throws {
        // The property the gate holds a `Task` for, and not a `Bool`: a `Mutex`
        // cannot stay locked across the suspension of the canary, thus a latch
        // that reads and then starts would let each caller that arrives before
        // the first one ends start a canary of its own. Calls one after the
        // other cannot tell the two designs apart. This test can.
        let counter = CanaryCounter(taking: Self.overlappingCanaryDuration)
        let gate = CanaryGate()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<Self.overlappingCallerCount {
                group.addTask { try await gate.passOnce(counter.run) }
            }
            try await group.waitForAll()
        }

        #expect(counter.count == 1)
    }

    @Test("a canary that failed does not latch, thus a healthy call runs it again")
    func failedCanaryDoesNotLatch() async throws {
        // A failure that latched would poison a gate for the life of the
        // process. Worse, a bug that latched a FAILED run as a pass would let
        // each later command through with no check at all.
        let counter = CanaryCounter(answering: [.failure(CanaryFailure()), .success(())])
        let gate = CanaryGate()

        await #expect(throws: CanaryFailure()) {
            try await gate.passOnce(counter.run)
        }
        try await gate.passOnce(counter.run)

        #expect(counter.count == 2)
    }

    // MARK: - The live spawn

    @Test("the live spawn reports the exit code of a wrapper that ended by itself")
    func liveSpawnReportsAHealthyWrapper() async throws {
        let result = try await liveCanarySpawn(Self.trueExecutable, [])

        #expect(result == CanaryResult(exitCode: 0, stderr: ""))
    }

    @Test("the live spawn captures the standard error of a wrapper that failed")
    func liveSpawnCapturesStandardError() async throws {
        // The stderr of the wrapper is the one text that says WHY a canary
        // failed, thus a result that dropped it would leave the operator with
        // an exit code and nothing else.
        let result = try await liveCanarySpawn(
            Self.shellPath,
            [
                "-c",
                "echo \(Self.failedCommandMessage) >&2; exit \(Self.failedCommandExitCode)",
            ])

        #expect(result.exitCode == Self.failedCommandExitCode)
        #expect(result.stderr.contains(Self.failedCommandMessage))
    }

    @Test("the live spawn reports a wrapper that a signal stopped as 128 plus that signal")
    func liveSpawnReportsASignalledWrapper() async throws {
        // `SIGKILL` cannot be caught, thus the shell always ends by the signal
        // and never by an exit code of its own. The reported code must stay
        // apart from each code the wrapper itself can produce.
        let result = try await liveCanarySpawn(Self.shellPath, ["-c", "kill -9 $$"])

        #expect(result.exitCode == Self.killedWrapperExitCode)
    }
}

/// A canary spawn that could not be made at all — the stand-in for a failure to
/// start the wrapper.
private struct CanaryFailure: Error, Equatable, Sendable {}

/// A stand-in for the canary that counts how many times it ran and answers from
/// a script, thus a test measures the gate with no child process.
private final class CanaryCounter: Sendable {

    /// How many times this canary ran.
    private let calls = Mutex<Int>(0)

    /// What each successive run answers with. The last entry repeats when the
    /// script runs out, thus a script of one entry is a constant answer.
    private let script: [Result<Void, CanaryFailure>]

    /// How long each run takes before it answers, or `nil` to answer at once.
    private let duration: Duration?

    /// Makes a counter that answers from `script`, in order.
    ///
    /// - Parameters:
    ///   - script: The answers to give, one for each run, the last one
    ///     repeating. The default is a single canary that passes.
    ///   - duration: How long each run takes. The default is `nil` — at once.
    init(
        answering script: [Result<Void, CanaryFailure>] = [.success(())],
        taking duration: Duration? = nil
    ) {
        self.script = script
        self.duration = duration
    }

    /// How many runs this counter recorded.
    var count: Int {
        calls.withLock { $0 }
    }

    /// Runs the canary: records the call, waits, and answers from the script.
    ///
    /// - Throws: The `CanaryFailure` of this entry of the script.
    func run() async throws {
        let index = calls.withLock { recorded -> Int in
            recorded += 1
            return recorded - 1
        }
        if let duration {
            try? await Task.sleep(for: duration)
        }
        try script[min(index, script.count - 1)].get()
    }
}
