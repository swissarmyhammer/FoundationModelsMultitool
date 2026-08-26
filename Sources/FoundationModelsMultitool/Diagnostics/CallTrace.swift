import Foundation
import os

/// A record of one call's entry and its exit, published to the unified log and
/// to Instruments, so a call that is entered and never left is visible as an
/// entry line with no matching exit line.
///
/// ## Why this exists
///
/// A suspended Swift `async` function occupies no OS thread. Its frame lives on
/// the heap, and the cooperative pool thread that was running it has moved on,
/// so `sample`, `spindump`, and a crash report all print stacks that belong to
/// something else entirely. Every thread that waits on a condition variable is
/// the *expected* picture of a suspended async program, and it names nothing.
/// That is why a hang inside an awaited call cannot be answered by sampling,
/// and why this package writes its own trail instead.
///
/// Each span writes one line before the call and one line after it, under a
/// single signpost id. The last unmatched entry in the log names the call that
/// was entered and never returned — which is the whole question a hang asks.
///
/// ## Where spans are placed
///
/// On the calls that can suspend for a long time and are not visible from
/// anywhere else: the two tools a session mounts (``MultiTool/call(arguments:)``
/// and ``SearchToolsTool/call(arguments:)``), the tool a model calls to block
/// (``WaitTool/call(arguments:)``), the inner `tools.*` dispatch
/// (`RunBinding.invoke(_:arguments:journalOp:)`), and the selection tier's own session
/// calls behind the `AgentSession` seam (``TracedAgentSession``). A span costs
/// two log writes, so it belongs on a call whose own cost is a model turn — not
/// on a hot loop.
///
/// ## Reading a trace
///
/// ```
/// log stream --predicate 'subsystem == "com.swissarmyhammer.multitool"' --style compact
/// ```
///
/// or, after the fact, `log show --last 10m --predicate '…'`. Each line reads
/// `enter <name> #<id> <detail>` or `exit <name> #<id> <outcome>`; `#<id>` is
/// the signpost id, so two concurrent calls of the same name stay apart.
struct CallTrace: Sendable {
    /// The unified-logging subsystem every span publishes under.
    ///
    /// Deliberately **not** `FoundationModelsMultitool`, the subsystem this
    /// package's diagnostic loggers already use (`MultiTool`,
    /// `JSCInterpreter`, `ToolAPIRenderer`). Those record what the code
    /// decided; these record only where control is. Keeping the two apart is
    /// what lets a single predicate print a complete call trace with nothing
    /// interleaved — and a trace a reader has to filter is a trace that hides
    /// the missing exit line.
    static let subsystem = "com.swissarmyhammer.multitool"

    /// What a span's detail prints for a field this call did not carry.
    ///
    /// Printed rather than omitted, and spelled one way everywhere: an omitted
    /// field reads as a truncated line, and a reader chasing a hang must never
    /// have to decide whether a short line means "no value" or "no log".
    static let absent = "none"

    /// The exit-line outcome of a span whose body returned.
    private static let returnedOutcome = "returned"

    /// Where this tracer's entry and exit lines are written.
    ///
    /// At `.notice`, which the unified log persists and streams by default —
    /// `.debug` would need `log config` to have been turned on before the run
    /// that hung, which is knowledge nobody has in advance.
    private let logger: Logger

    /// Where this tracer's intervals are emitted, for Instruments' own
    /// timeline. The same names and ids the log lines carry.
    private let signposter: OSSignposter

    /// Creates a tracer for one area of this package.
    ///
    /// - Parameter category: the unified-logging category naming that area, so
    ///   a stream can be narrowed to it. One category per call-site family.
    init(category: String) {
        logger = Logger(subsystem: Self.subsystem, category: category)
        signposter = OSSignposter(subsystem: Self.subsystem, category: category)
    }

    /// One span that has been entered and not yet left.
    ///
    /// Carries what closing it needs: `OSSignposter` matches an interval by its
    /// name as well as by its state token, and the exit line has to repeat the
    /// id its entry line printed.
    private struct Open {
        /// The span's name, repeated to `endInterval`.
        let name: StaticString

        /// The correlation both lines print, and the interval's own id.
        let id: OSSignpostID

        /// The token `endInterval` consumes to close the interval.
        let state: OSSignpostIntervalState
    }

    /// Records one asynchronous call as a span.
    ///
    /// Transparent by construction: `body`'s value comes back unchanged and
    /// `body`'s error is rethrown unchanged, so a traced call differs from the
    /// untraced one in nothing but its two log lines. Every span in this
    /// package sits on a production path, which is why that is a tested
    /// property (`CallTraceTests`) and not merely an intention.
    ///
    /// - Parameters:
    ///   - name: the span's name. A `StaticString` because the unified log
    ///     stores a signpost name by reference rather than copying it.
    ///   - detail: the call's own identity — the tool name, the completion
    ///     token, whatever tells two concurrent calls of this name apart.
    ///     Defaults to empty, for a span that is unique on its name alone.
    ///   - body: the call to record.
    /// - Returns: whatever `body` returned.
    /// - Throws: whatever `body` threw.
    func span<Result>(
        _ name: StaticString,
        detail: String = "",
        do body: () async throws -> Result
    ) async rethrows -> Result {
        let open = begin(name, detail: detail)
        do {
            let result = try await body()
            end(open, outcome: Self.returnedOutcome)
            return result
        } catch {
            end(open, outcome: "threw \(error)")
            throw error
        }
    }

    /// Records one synchronous call as a span.
    ///
    /// The asynchronous ``span(_:detail:do:)`` cannot serve a non-`async`
    /// caller: Swift has no `reasync`, so one body cannot be written for both
    /// contexts, and a synchronous caller cannot `await`. Overloading on
    /// `async` alone is well-defined — an `async` context prefers the
    /// asynchronous overload, and a synchronous context is the only place this
    /// one is viable — so both spans keep the one name a reader looks for.
    /// Everything the two share is already factored into `begin`/`end`; what
    /// repeats is the `do`/`catch` the language requires at each.
    ///
    /// It earns its place: a `RoutedLLM` session factory is synchronous and
    /// does real work — a grammar-constrained session compiles its grammar —
    /// so it can hold a thread, and a call that never returns from a
    /// synchronous factory looks identical, from outside, to one suspended in
    /// an `await`.
    ///
    /// - Parameters:
    ///   - name: the span's name. A `StaticString` because the unified log
    ///     stores a signpost name by reference rather than copying it.
    ///   - detail: the call's own identity. Defaults to empty.
    ///   - body: the call to record.
    /// - Returns: whatever `body` returned.
    /// - Throws: whatever `body` threw.
    func span<Result>(
        _ name: StaticString,
        detail: String = "",
        do body: () throws -> Result
    ) rethrows -> Result {
        let open = begin(name, detail: detail)
        do {
            let result = try body()
            end(open, outcome: Self.returnedOutcome)
            return result
        } catch {
            end(open, outcome: "threw \(error)")
            throw error
        }
    }

    /// Opens a span: begins the signpost interval and writes the entry line.
    ///
    /// - Parameters:
    ///   - name: the span's name.
    ///   - detail: the call's own identity.
    /// - Returns: what ``end(_:outcome:)`` needs to close it.
    private func begin(_ name: StaticString, detail: String) -> Open {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id, "\(detail, privacy: .public)")
        logger.notice(
            "enter \(name.description, privacy: .public) #\(id.rawValue, privacy: .public) \(detail, privacy: .public)"
        )
        return Open(name: name, id: id, state: state)
    }

    /// Closes a span: writes the exit line and ends the signpost interval.
    ///
    /// - Parameters:
    ///   - open: the span ``begin(_:detail:)`` opened.
    ///   - outcome: how the call ended — ``returnedOutcome``, or the error it
    ///     threw.
    private func end(_ open: Open, outcome: String) {
        logger.notice(
            "exit \(open.name.description, privacy: .public) #\(open.id.rawValue, privacy: .public) \(outcome, privacy: .public)"
        )
        signposter.endInterval(open.name, open.state, "\(outcome, privacy: .public)")
    }
}
