import Foundation
import FoundationModelsRouter
import Synchronization

@testable import FoundationModelsMultitool

// MARK: - The one seam a gated harness has onto the run plane of a live session
//
// `ToolContext.current` is the ONLY route to a session's run plane. Router
// publishes no `backgroundRuns`, no `wait(completionToken:)` and no
// `cancel(completionToken:)` on `RoutedSession`; `RoutedSessionActor` and its
// `runPlane` property are internal to that package. So a scenario that has to
// read what a live session's shell run is doing needs the context of that run.
//
// `ShellRunner.runWillSpawn` is the place a test reads it. The runner calls
// that hook in the task of the run, after `ShellState.startCommand` recorded
// the run and before the spawn, thus `ToolContext.current` there is the SHELL
// run's own context — its completion token, its session and its run plane —
// and the request carries the command line that the run got. The root
// package's `RegisteredJournalOpTests` reads the journal op through the same
// hook.
//
// The capability is the type a host registers: `ShellCapability(runner:)` is
// the initializer that `withShell(...)` reaches, and the runner differs from
// the runner of `withShell` only in the hook. Thus a scenario that uses this
// observer runs the surface a host runs.

/// Keeps the ambient ``FoundationModelsRouter/ToolContext`` and the command of
/// each `tools.shell.execute` run, from the hook a run calls before its spawn.
///
/// The hook changes nothing of the run, so a command starts as it starts with
/// no observer.
///
/// A locked reference type rather than an actor, because the hook is
/// SYNCHRONOUS. It is also the shape a runner needs: a `ShellRunner` is a
/// value and is copied, so a value observer would record into a copy the
/// caller never reads.
final class ShellRunContextObserver: Sendable {

    /// One run that reached its spawn.
    private struct ObservedRun {
        /// The ambient context of the run.
        let context: ToolContext

        /// The command line of the run: the command that went to `sh -c`.
        let command: String
    }

    /// Everything that the hook and the waiters change.
    private struct State {
        /// Each run that reached its spawn, in call order.
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

    /// The state of the observer.
    private let state = Mutex(State())

    /// The ambient context of each run that reached its spawn, in call order.
    ///
    /// A run that reached its spawn under no ambient context at all is not
    /// recorded: it has no completion token, so it names nothing on the run
    /// plane and there is nothing for a scenario to read it by.
    var observedContexts: [ToolContext] {
        state.withLock { $0.runs.map(\.context) }
    }

    /// The command line that the run `completionToken` got, or `nil` when no
    /// such run reached its spawn.
    ///
    /// The command is known when ``waitForFirstContext()`` returns the context
    /// of the run: the observer keeps both in the same step.
    ///
    /// - Parameter completionToken: The completion token of the run.
    /// - Returns: The command line of the run.
    func command(ofRun completionToken: String) -> String? {
        state.withLock { current in
            current.runs.first { $0.context.completionToken == completionToken }?.command
        }
    }

    /// Waits until a run reached its spawn, and answers the context of the
    /// first such run. Returns at once when one already did.
    ///
    /// This is the event that the model started a `tools.shell.execute` run,
    /// and it replaces a poll of ``observedContexts``.
    ///
    /// - Returns: The ambient context of the first run.
    /// - Throws: `CancellationError` when the task is cancelled before a run
    ///   reached its spawn.
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

    /// Makes the shell capability whose runner gives each run to this
    /// observer before it spawns the child.
    ///
    /// - Parameter storeDirectory: The directory the store of the capability
    ///   prepares in.
    /// - Returns: The capability.
    /// - Throws: What `ShellStore.init(storeDirectory:)` throws.
    func makeShellCapability(storeDirectory: URL) throws -> ShellCapability {
        var runner = ShellRunner(state: try ShellStore(storeDirectory: storeDirectory).state)
        runner.runWillSpawn = { [self] request in observe(request) }
        return ShellCapability(runner: runner)
    }

    /// Keeps the ambient context and the command line of the calling run, and
    /// ends each wait of ``waitForFirstContext()``.
    ///
    /// A run under no ambient context is not kept: it has no completion token
    /// on a run plane, so there is nothing for a scenario to read it by.
    ///
    /// - Parameter request: The request of the run.
    private func observe(_ request: ShellRunner.Request) {
        if let context = ToolContext.current {
            record(ObservedRun(context: context, command: request.command))
        }
    }

    /// Keeps `run`, and ends each wait of ``waitForFirstContext()`` with the
    /// context of the first run.
    ///
    /// - Parameter run: The run that reached its spawn.
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
