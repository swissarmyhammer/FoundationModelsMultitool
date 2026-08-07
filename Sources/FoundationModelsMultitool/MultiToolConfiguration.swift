import Foundation
import FoundationModelsRouter

/// plan.md M10 — "Limits tuned + configurable": the single knob set threaded
/// through `MultiTool` that bounds one `runCode` call's execution time and
/// rendered output size, plus how many of those calls may be live at once.
///
/// This type deliberately wraps `ResultRendererLimits` (via `resultLimits`)
/// rather than re-declaring its own return/console cap logic — plan.md's
/// caps are `ResultRenderer`'s to enforce; this configuration only carries
/// the numbers `MultiTool` hands it.
///
/// The retired `MultiToolAgent` ReAct loop's own knobs (`maxAgentTurns`/
/// `maxRepairTurns`) were removed alongside it: on the current
/// `LanguageModelSession`-driven design, Apple's native tool-calling loop
/// owns turn budgeting, so only the `runCode`-sandbox limits remain.
public struct MultiToolConfiguration: Sendable, Equatable {
    /// Wall-clock ceiling, in seconds, on a single `runCode` snippet's own
    /// work: both the default for the envelope's `timeout` and the hard cap
    /// that no envelope can raise (see
    /// `MultiTool.elevationClocks(from:)`). Clamped to at least `0` at
    /// `init`.
    ///
    /// ## Why this is the work clock, and never the wait clock
    ///
    /// A `runCode` call runs under two clocks (eventplan.md § "Consolidation
    /// of the siblings"): `waitSeconds`, how long the call blocks before it
    /// elevates, and `timeout`, how long the work itself may run. Elevation
    /// exists precisely to keep a suspended JSC context alive past
    /// `waitSeconds` — so this limit, which arms the watchdog of every
    /// sandbox `MultiTool.init` runs (`Interpreter.withTimeLimit(_:)`),
    /// must never be a second clock racing the first. It was: this default and
    /// `ElevationConfiguration.defaultWaitSeconds` were both 5 seconds, so
    /// the watchdog force-terminated a snippet at the exact instant its run
    /// elevated. The default is now the engine's own stock work clock,
    /// `ElevationConfiguration.defaultTimeoutSeconds`, taken from that one
    /// definition so the two can never drift apart again.
    ///
    /// The per-call `timeout` an envelope carries is enforced by the
    /// elevation engine — which resets it on every progress event and
    /// reaches the interpreter through the same cancellation path a
    /// cancelled `Task` does — and is clamped to this ceiling.
    ///
    /// The clamp bounds the two clocks' *starting* values; it does not make
    /// this one the looser of the two forever. The engine's clock resets on
    /// progress. This one does not: it arms the `WatchdogState` of whatever
    /// sandbox `MultiTool.init` runs, which measures from sandbox creation,
    /// and neither progress nor parking on `elicit()` moves that reference
    /// point (`runStart` is a `let`; `rearm()` re-arms the poll interval, not
    /// the deadline). So a snippet that keeps resetting the engine's clock is
    /// force-terminated here instead, at this ceiling. That is deliberate —
    /// it is the absolute cap on one snippet, and the reason a suspended
    /// context cannot be kept alive indefinitely by reporting progress.
    ///
    /// The arming covers every sandbox, not only the one `MultiTool.init`
    /// builds for itself: an `interpreter:` a caller hands it is re-armed
    /// with this ceiling too (`Interpreter.withTimeLimit(_:)`). So injecting
    /// an interpreter cannot put a second, different limit under a `runCode`
    /// call, and cannot reinstate the collision described above: a plain
    /// `JSCInterpreter()`, whose own stock limit is the 5 seconds that
    /// collision was made of, is armed from here like any other.
    public let executionTimeLimit: TimeInterval

    /// How many `runCode` snippets may be live at once before a further call
    /// is refused with a repairable in-band error. Clamped to at least `1` at
    /// `init`.
    ///
    /// A snippet stays live past its wait window only by elevating, so this
    /// is the cap on suspended JSC contexts (eventplan.md § "The constraint
    /// boundary, and the escape hatch"). Each one holds a real JS context and
    /// the thread its run occupies, so they are bounded rather than allowed
    /// to pile up: a model that has parked this many snippets has lost track
    /// of them, and is told to collect one — `status()`, `wait()`,
    /// `cancel()` — instead of starting another.
    public let liveContextLimit: Int

    /// Maximum length, in characters, a snippet's serialized return value
    /// may reach before `ResultRenderer` truncates it — see
    /// `ResultRendererLimits.returnValueCharacterLimit`. Clamped to at least
    /// `0` at `init`.
    public let returnValueCharacterLimit: Int

    /// Maximum length, in characters, a snippet's joined `console.log`
    /// output may reach before `ResultRenderer` truncates it — see
    /// `ResultRendererLimits.consoleCharacterLimit`. Clamped to at least `0`
    /// at `init`.
    public let consoleCharacterLimit: Int

    /// The stock number of live `runCode` contexts — see ``liveContextLimit``
    /// for why a handful, rather than an unbounded set, is the right shape.
    public static let defaultLiveContextLimit = 8

    /// Generous defaults: the engine's own stock work clock, a handful of
    /// live contexts, and each mechanism's own rendering default — see this
    /// type's properties.
    public static let `default` = MultiToolConfiguration()

    /// Creates a hardening configuration, clamping every limit to its valid
    /// range (out-of-range inputs never produce a limit that would crash or
    /// silently disable the corresponding bound).
    ///
    /// - Parameters:
    ///   - executionTimeLimit: wall-clock ceiling, in seconds, on a single
    ///     `runCode` snippet's work. Defaults to
    ///     `ElevationConfiguration.defaultTimeoutSeconds`, the elevation
    ///     engine's own stock work clock.
    ///   - liveContextLimit: how many `runCode` snippets may be live at once.
    ///     Defaults to ``defaultLiveContextLimit``.
    ///   - returnValueCharacterLimit: maximum length, in characters, of a
    ///     snippet's serialized return value. Defaults to
    ///     `ResultRendererLimits.default.returnValueCharacterLimit`.
    ///   - consoleCharacterLimit: maximum length, in characters, of a
    ///     snippet's joined console output. Defaults to
    ///     `ResultRendererLimits.default.consoleCharacterLimit`.
    public init(
        executionTimeLimit: TimeInterval = ElevationConfiguration.defaultTimeoutSeconds,
        liveContextLimit: Int = MultiToolConfiguration.defaultLiveContextLimit,
        returnValueCharacterLimit: Int = ResultRendererLimits.default.returnValueCharacterLimit,
        consoleCharacterLimit: Int = ResultRendererLimits.default.consoleCharacterLimit
    ) {
        self.executionTimeLimit = max(0, executionTimeLimit)
        self.liveContextLimit = max(1, liveContextLimit)
        self.returnValueCharacterLimit = max(0, returnValueCharacterLimit)
        self.consoleCharacterLimit = max(0, consoleCharacterLimit)
    }

    /// The `ResultRenderer` caps this configuration implies — wraps
    /// `returnValueCharacterLimit`/`consoleCharacterLimit` into a
    /// `ResultRendererLimits` rather than `ResultRenderer` needing to know
    /// about this type at all.
    public var resultLimits: ResultRendererLimits {
        ResultRendererLimits(
            returnValueCharacterLimit: returnValueCharacterLimit,
            consoleCharacterLimit: consoleCharacterLimit
        )
    }
}
