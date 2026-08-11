import Foundation
import FoundationModelsRouter
import os

/// One notice a snippet's `notify()` or `progress()` enqueued, together with
/// the `ToolContext` capability it is delivered through.
///
/// eventplan.md § "The capability contract" pairs the two snippet-level calls
/// with the two context-level ones: `notify()` with `ToolContext.post(_:)` and
/// `progress()` with `ToolContext.progress(_:)`. That pairing is the whole
/// difference between the cases — the payload is identical.
///
/// Both deliver a `.progress`-kind `OperationEvent`, because that is the only
/// non-terminal kind Router's `OperationEventKind` vocabulary has today (its
/// three cases are `progress`, `completed`, and `elicitation`). A distinct
/// notice kind, if one is ever wanted, lands there — not here.
enum SandboxNotice: Sendable {
    /// A `notify(detail)` call: delivered through ``ToolContext/post(_:)``.
    case notify(String)

    /// A `progress(detail)` call: delivered through
    /// ``ToolContext/progress(_:)``.
    case progress(String)

    /// Delivers this notice through `context`, which re-stamps it with the
    /// enclosing run's `tool`, `op`, and `completionToken` — so a snippet can
    /// never post under an identity that is not its own run's.
    ///
    /// - Parameter context: the ambient context captured for the enclosing
    ///   `runCode` invocation.
    func deliver(through context: ToolContext) async {
        switch self {
        case .notify(let detail):
            await context.post(
                OperationEvent(
                    tool: context.tool,
                    op: context.op,
                    correlationID: context.completionToken,
                    kind: .progress,
                    detail: detail
                )
            )
        case .progress(let detail):
            await context.progress(detail)
        }
    }
}

/// The per-invocation delivery chain behind a snippet's synchronous
/// `notify()`/`progress()` globals — eventplan.md § "Async JavaScript": these
/// calls "are synchronous… they enqueue and continue; the bridge flushes
/// them."
///
/// ## Why a chain rather than one `Task` each
///
/// `notify()`/`progress()` are `HostFunction`s, so their bodies are
/// synchronous and cannot await the `async` `ToolContext` capability they
/// deliver through. Starting an independent `Task` per call would deliver, but
/// out of order — a snippet loop's `progress("step 1")` could reach the sink
/// after `progress("step 2")`. Each enqueue therefore chains onto the previous
/// delivery's handle, exactly as `DetachingTool`'s own funnel serializes its
/// upstream deliveries: the snippet keeps running (nothing blocks the JS
/// thread), while the session observes the notices in the order the snippet
/// made them.
///
/// ## Why a flush
///
/// The chain's tail is still in flight when the snippet's own `return`
/// settles, so `MultiTool.call(arguments:)` awaits ``flush()`` before it
/// renders. Without it a run could hand its result back before its last
/// notice reached the session — and the session would see the terminal event
/// first.
///
/// `final class … Sendable` with an `OSAllocatedUnfairLock` (not an `actor`):
/// ``enqueue(_:)`` is called from the JS thread, which has no `await` to give.
final class SandboxNoticeOutbox: Sendable {
    /// The ambient context every notice is delivered through.
    private let context: ToolContext

    /// The tail of the FIFO delivery chain — `nil` until the first enqueue.
    private let latestDelivery = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    /// Creates an outbox delivering through one invocation's captured context.
    ///
    /// - Parameter context: the ambient context captured at the top of
    ///   `MultiTool.call(arguments:)`.
    init(context: ToolContext) {
        self.context = context
    }

    /// Enqueues `notice` behind every notice already enqueued, and returns
    /// immediately.
    ///
    /// - Parameter notice: the notice to deliver.
    func enqueue(_ notice: SandboxNotice) {
        let context = self.context
        latestDelivery.withLock { tail in
            let previous = tail
            tail = Task {
                await previous?.value
                await notice.deliver(through: context)
            }
        }
    }

    /// Awaits every enqueued notice's delivery — the bridge's flush, run once
    /// the snippet has finished.
    func flush() async {
        await latestDelivery.withLock { $0 }?.value
    }
}
