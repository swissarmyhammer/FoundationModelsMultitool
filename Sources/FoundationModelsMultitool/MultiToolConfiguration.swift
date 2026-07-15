import Foundation

/// plan.md M10 — "Limits tuned + configurable": the single knob set threaded
/// through `MultiTool` that bounds one `runCode` call's execution time and
/// rendered output size.
///
/// Every default here is the exact value each mechanism already used before
/// this configuration existed (`JSCInterpreter`'s own `timeLimit` default,
/// `ResultRendererLimits.default`) — passing `.default` (or omitting
/// `configuration` entirely) changes no behavior; only an explicitly
/// customized `MultiToolConfiguration` does.
///
/// The retired `MultiToolAgent` ReAct loop's own knobs (`maxAgentTurns`/
/// `maxRepairTurns`) were removed alongside it: on the current
/// `LanguageModelSession`-driven design, Apple's native tool-calling loop
/// owns turn budgeting, so only the `runCode`-sandbox limits remain.
///
/// This type deliberately wraps `ResultRendererLimits` (via `resultLimits`)
/// rather than re-declaring its own return/console cap logic — plan.md's
/// caps are `ResultRenderer`'s to enforce; this configuration only carries
/// the numbers `MultiTool` hands it.
public struct MultiToolConfiguration: Sendable, Equatable {
    /// Wall-clock ceiling, in seconds, a single `runCode` snippet may run
    /// before the interpreter's watchdog force-terminates it — threaded into
    /// `JSCInterpreter(timeLimit:)`. Clamped to at least `0` at `init`.
    public let executionTimeLimit: TimeInterval

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

    /// Generous defaults matching every mechanism's own pre-M10 default —
    /// see this type's documentation.
    public static let `default` = MultiToolConfiguration()

    /// Creates a hardening configuration, clamping every limit to its valid
    /// range (negative inputs never produce a limit that would crash or
    /// silently disable the corresponding bound).
    ///
    /// - Parameters:
    ///   - executionTimeLimit: wall-clock ceiling, in seconds, a single
    ///     `runCode` snippet may run. Defaults to `5.0`, matching
    ///     `JSCInterpreter`'s own default.
    ///   - returnValueCharacterLimit: maximum length, in characters, of a
    ///     snippet's serialized return value. Defaults to
    ///     `ResultRendererLimits.default.returnValueCharacterLimit`.
    ///   - consoleCharacterLimit: maximum length, in characters, of a
    ///     snippet's joined console output. Defaults to
    ///     `ResultRendererLimits.default.consoleCharacterLimit`.
    public init(
        executionTimeLimit: TimeInterval = 5.0,
        returnValueCharacterLimit: Int = ResultRendererLimits.default.returnValueCharacterLimit,
        consoleCharacterLimit: Int = ResultRendererLimits.default.consoleCharacterLimit
    ) {
        self.executionTimeLimit = max(0, executionTimeLimit)
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
