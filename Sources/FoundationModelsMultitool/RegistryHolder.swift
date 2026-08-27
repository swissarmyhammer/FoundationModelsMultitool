// `MultiTool.RegistryHolder` — the reference box that holds the current
// `RegistryBundle` and the newest staged `Registry`.
//
// eventplan.md § "Consolidation of the siblings": "Then MultiTool swaps it in
// atomically at the next turn boundary — the same boundary where the outbox
// folds in events. Nothing changes below a snippet that runs. An in-flight
// run keeps the registry that it started with."
//
// `MultiTool` is a copyable struct, and `Mutex` is `~Copyable`, so the lock
// cannot be a stored property of the struct. The lock lives in this box, and
// the struct holds a reference to the box. A copy of the struct — a fork —
// copies the reference, so a fork and its parent swap together at the same
// tick.

import Synchronization

/// The half of a mounted `runCode` a refresher stages a rebuilt registry on.
///
/// `MultiTool.Registry.makeSessionToolsAndStaging(librarian:sampleGenerator:)`
/// vends one beside the tools it mounts. A staged registry is applied at the
/// next turn boundary, by `MultiTool.turnWillBegin()`.
public protocol RegistryStaging: Sendable {
    /// Stages `registry` as the next surface. Only the newest staged registry
    /// is kept: a second call before the tick replaces the first.
    ///
    /// - Parameter registry: The registry to swap in at the next tick.
    func stage(_ registry: MultiTool.Registry)
}

extension MultiTool {
    /// The reference box that holds the current bundle and the newest staged
    /// registry, shared by every copy of one `MultiTool` and by the
    /// `SearchToolsTool` mounted beside it.
    final class RegistryHolder: RegistryStaging {
        /// What the lock guards: the bundle every new run reads, and the
        /// registry the next tick swaps in, when one is staged.
        private struct State: Sendable {
            /// The bundle a run starting now reads.
            var current: RegistryBundle

            /// The newest staged registry, or `nil` when none is staged.
            var staged: Registry?
        }

        /// The guarded state. A `Mutex`, not an actor: every operation is a
        /// synchronous decision on a small value, and ``current`` is read at
        /// the top of a `runCode` call with nothing to await.
        private let state: Mutex<State>

        /// Creates a holder whose first bundle is `current`.
        ///
        /// - Parameter current: The bundle every run reads until a staged
        ///   registry is applied.
        init(current: RegistryBundle) {
            self.state = Mutex(State(current: current, staged: nil))
        }

        /// The bundle a run starting now reads. A run reads this one time,
        /// at its start, and keeps the value to its end.
        var current: RegistryBundle {
            state.withLock { $0.current }
        }

        /// Stages `registry` as the next surface, and drops any registry
        /// staged before it.
        ///
        /// - Parameter registry: The registry to swap in at the next tick.
        func stage(_ registry: Registry) {
            state.withLock { $0.staged = registry }
        }

        /// Moves the staged registry, when there is one, into the current
        /// bundle, built in the same shape as the bundle it replaces.
        ///
        /// The build runs under the lock, so a run that starts during the
        /// swap reads either the whole old bundle or the whole new one.
        func applyStaged() {
            state.withLock { state in
                guard let staged = state.staged else { return }
                state.staged = nil
                state.current = RegistryBundle(registry: staged, shape: state.current.shape)
            }
        }
    }
}
