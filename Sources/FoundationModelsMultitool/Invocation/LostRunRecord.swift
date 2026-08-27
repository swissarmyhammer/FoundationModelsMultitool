import FoundationModelsRouter
import os

/// The first `LostRunError` an inner `tools.*` call of one `runCode`
/// invocation threw, kept so the invocation can throw it once the snippet
/// has finished.
///
/// **The gap this closes.** The JS bridge turns an error a `tools.*` call
/// throws into the rejection of the promise the snippet awaited, and the
/// reason is a string. A snippet that does not catch it fails with an
/// `InterpreterError`, which `MultiTool.call(arguments:)` renders as
/// repairable text; a snippet that catches it goes on. Either way the error
/// itself never leaves the sandbox, and the engine of Router settles the
/// `runCode` run from what `call(arguments:)` returned or threw. A transport
/// drop under an in-flight MCP request is a `LostRunError`, and eventplan.md
/// § "Phases" (the phase-4 note) says what it must reach: "the engine settles
/// the calling run as `.lost`." The inner run already settled that way. This
/// record is what carries the loss out to the outer run, so that run settles
/// as `.lost` too, and never as a success whose text says a tool failed.
///
/// **Why the first one.** One loss makes the outcome of the whole run
/// unknowable; a second changes nothing, so the first is kept and the rest
/// are not read.
///
/// A reference type guarded by `OSAllocatedUnfairLock`, rather than an
/// `actor`, for `ToolReturnLedger`'s reason: the recording side runs inside
/// `AsyncHostFunction` bodies the interpreter's promise pump starts on
/// whatever thread it likes, and the read is one synchronous decision.
final class LostRunRecord: Sendable {
    /// The first `LostRunError` recorded, or `nil` while none was.
    private let first = OSAllocatedUnfairLock<(any LostRunError)?>(initialState: nil)

    /// Runs one `tools.*` call and records the `LostRunError` it throws, if
    /// it throws one.
    ///
    /// - Parameter call: The `tools.*` binding to run.
    /// - Returns: What `call` returned, unchanged.
    /// - Throws: Whatever `call` throws, unchanged.
    func noting(_ call: () async throws -> InterpreterValue) async rethrows -> InterpreterValue {
        do {
            return try await call()
        } catch let lost as any LostRunError {
            first.withLock { recorded in
                if recorded == nil {
                    recorded = lost
                }
            }
            throw lost
        }
    }

    /// The first `LostRunError` an inner call threw, or `nil` when none did.
    var lostError: (any LostRunError)? {
        first.withLock { $0 }
    }
}
