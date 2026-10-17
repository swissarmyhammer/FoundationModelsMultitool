import Foundation
import FoundationModelsRouter
import Synchronization

@testable import FoundationModelsMultitool

// MARK: - The one seam a gated harness has onto the run plane of a live session
//
// `ToolContext.current` is the ONLY route to a session's run plane. Router
// publishes no `backgroundRuns`, no `wait(completionToken:)` and no
// `cancel(completionToken:)` on `RoutedSession`; `RoutedSessionActor` and its
// `runPlane` property are internal to that package. So a
// scenario that has to read what a live session's shell run is doing needs a
// tool to hand it a context, and there is exactly one place a tool does that.
//
// `Execute` asks its sandbox to `preflight` from INSIDE its own call, before it
// spawns anything (`CommandSandbox.preflight`, whose own documentation names
// that verb as its caller). `ToolContext.current` there is the SHELL run's own
// context — its completion token, its session and its run plane. The root
// package's `RegisteredJournalOpTests` already reads the journal op through this
// same seam, with the same shape of probe.
//
// The probe keeps the context in `wrap`, and not in `preflight`. `wrap` runs in
// the same call and the same task, after `ShellState.startCommand` recorded the
// run and before the spawn, and it is the one step that sees the command line.
// Thus the event of a run carries the command that the run got, and a harness
// can examine the command before it waits on the output of the run.
//
// The seam is the shipped configuration and not a back door:
// `MultiTool.Builder.withShell(storeDirectory:sandbox:outputChunkStream:defaultWorkingDirectory:)` takes
// the sandbox a host configures, so a scenario that passes this probe is running
// the surface a host runs, with the confinement a host chose — here, none.

/// A `CommandSandbox` that confines nothing and keeps the ambient
/// ``FoundationModelsRouter/ToolContext`` of each `tools.shell.execute` run.
///
/// `wrap` gives the shell invocation back exactly as it came in, so a command
/// starts as it starts with no sandbox at all and the probe changes only what is
/// observed. That matters twice over here: a gated run must not depend on
/// `/usr/bin/sandbox-exec` being present, and a Seatbelt profile refusing the
/// scenario's command would end the answer instead of the run this suite grades.
///
/// A locked reference type rather than an actor, because `wrap` is a
/// SYNCHRONOUS requirement of `CommandSandbox`, which an actor answers only from
/// outside its own isolation. It is also the shape a runner needs: a
/// `ShellRunner` is a value and is copied, so a value probe would record into a
/// copy the caller never reads.
final class ShellRunContextProbe: CommandSandbox {

    /// One run that consulted this probe.
    private struct ObservedRun {
        /// The ambient context of the run.
        let context: ToolContext

        /// The command line of the run: the last argument that the shell got.
        let command: String?
    }

    /// Everything that `wrap` and the waiters change.
    private struct State {
        /// Each run that consulted this probe, in call order.
        var runs: [ObservedRun] = []

        /// Each wait of ``waitForFirstContext()`` that did not end, by id.
        var waiters: [Int: CheckedContinuation<ToolContext, any Error>] = [:]

        /// The id of each wait whose task was cancelled before the wait was
        /// recorded.
        var cancelled: Set<Int> = []

        /// The id that the next wait gets.
        var nextID = 0
    }

    /// What one call of ``waitForFirstContext()`` does next.
    private enum WaitStart {
        /// A context is there: the wait returns it at once.
        case ready(ToolContext)

        /// The task was cancelled before the wait was recorded.
        case cancelled

        /// The wait continues until a context comes or the task is cancelled.
        case waiting
    }

    /// The state of the probe.
    private let state = Mutex(State())

    /// The ambient context of each run that consulted this probe, in call order.
    ///
    /// A run that consulted the probe under no ambient context at all is not
    /// recorded: it has no completion token, so it names nothing on the run
    /// plane and there is nothing for a scenario to read it by.
    var observedContexts: [ToolContext] {
        state.withLock { $0.runs.map(\.context) }
    }

    /// The command line that the run `completionToken` got, or `nil` when no
    /// such run consulted this probe.
    ///
    /// The command is known when ``waitForFirstContext()`` returns the context
    /// of the run: the probe keeps both in the same step.
    ///
    /// - Parameter completionToken: The completion token of the run.
    /// - Returns: The command line of the run.
    func command(ofRun completionToken: String) -> String? {
        state.withLock { current in
            current.runs.first { $0.context.completionToken == completionToken }?.command
        }
    }

    /// Waits until a run consulted this probe, and answers the context of the
    /// first such run. Returns at once when one already did.
    ///
    /// This is the event that the model started a `tools.shell.execute` run,
    /// and it replaces a poll of ``observedContexts``.
    ///
    /// - Returns: The ambient context of the first run.
    /// - Throws: `CancellationError` when the task is cancelled before a run
    ///   consulted this probe.
    func waitForFirstContext() async throws -> ToolContext {
        let id = state.withLock { current -> Int in
            defer { current.nextID += 1 }
            return current.nextID
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ToolContext, any Error>) in
                let start = state.withLock { current -> WaitStart in
                    let wasCancelled = current.cancelled.remove(id) != nil
                    if let first = current.runs.first {
                        return .ready(first.context)
                    }
                    if wasCancelled {
                        return .cancelled
                    }
                    current.waiters[id] = continuation
                    return .waiting
                }
                switch start {
                case .ready(let context):
                    continuation.resume(returning: context)
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case .waiting:
                    break
                }
            }
        } onCancel: {
            let waiter = state.withLock { current -> CheckedContinuation<ToolContext, any Error>? in
                if let found = current.waiters.removeValue(forKey: id) {
                    return found
                }
                current.cancelled.insert(id)
                return nil
            }
            waiter?.resume(throwing: CancellationError())
        }
    }

    /// Keeps the ambient context and the command line of this run, ends each
    /// wait of ``waitForFirstContext()``, and gives back `shellPath` and
    /// `shellArguments` unchanged.
    ///
    /// The probe takes the default `preflight` of `CommandSandbox`, which does
    /// nothing: it proves nothing about the confinement.
    ///
    /// - Parameters:
    ///   - shellPath: The absolute path of the shell to run.
    ///   - shellArguments: The arguments of that shell. The last one is the
    ///     command line (`sh -c <command>`).
    ///   - workingDirectory: Not read — no confinement is applied.
    ///   - temporaryDirectory: Not read — no confinement is applied.
    /// - Returns: The shell invocation as it came in.
    func wrap(
        shellPath: String,
        shellArguments: [String],
        workingDirectory: String,
        temporaryDirectory: String
    ) -> SandboxedInvocation {
        if let context = ToolContext.current {
            record(ObservedRun(context: context, command: shellArguments.last))
        }
        return SandboxedInvocation(executable: shellPath, arguments: shellArguments)
    }

    /// Keeps `run`, and ends each wait of ``waitForFirstContext()`` with the
    /// context of the first run.
    ///
    /// - Parameter run: The run that consulted this probe.
    private func record(_ run: ObservedRun) {
        let (first, waiting) = state.withLock { current -> (ToolContext, [CheckedContinuation<ToolContext, any Error>]) in
            current.runs.append(run)
            defer { current.waiters.removeAll() }
            return (current.runs[0].context, Array(current.waiters.values))
        }
        for waiter in waiting {
            waiter.resume(returning: first)
        }
    }
}
