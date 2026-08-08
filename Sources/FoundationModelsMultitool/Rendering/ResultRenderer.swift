import Foundation

/// The size caps `ResultRenderer` enforces when turning an `InterpreterResult`
/// into the text handed back to the model, so a fat tool result or noisy
/// console output can never flood the model's context (plan.md: "Output:
/// intermediates stay in the sandbox").
///
/// Both caps are counted in `Character`s — Swift's extended-grapheme-cluster
/// unit, not raw UTF-8 bytes or UTF-16 code units — precisely so truncation
/// can always cut at a `String.prefix` boundary. `String.prefix(_:)` counts
/// `Character`s and is guaranteed never to split a multi-byte UTF-8 sequence
/// or a combined grapheme cluster (e.g. an emoji built from multiple Unicode
/// scalars) in the middle, which a naive byte-offset cap could do to a
/// snippet's return value or console output — both are arbitrary,
/// model/tool-derived text this renderer must never corrupt while trimming.
public struct ResultRendererLimits: Sendable, Equatable {
    /// Maximum length, in characters, the serialized `return` value may
    /// reach before `ResultRenderer` truncates it.
    public let returnValueCharacterLimit: Int

    /// Maximum length, in characters, the joined `console.log` output may
    /// reach before `ResultRenderer` truncates it — capped independently of
    /// `returnValueCharacterLimit`, so a chatty snippet's logging can never
    /// crowd out its actual result.
    public let consoleCharacterLimit: Int

    /// The stock cap on the serialized return value — the answer the snippet
    /// was run for.
    ///
    /// Generous enough to carry an ordinary tool result whole, so the common
    /// case reaches the model with nothing cut, while a pathological result is
    /// still bounded. Twice ``defaultConsoleCharacterLimit``, because this is
    /// the value the model asked for and console output is only the trace of
    /// how the snippet reached it: when a snippet pushes on both caps at once,
    /// the answer keeps the larger share of the model's context.
    ///
    /// `internal` is the right access level, matching `RepairDirective
    /// .closingLine`: the value already reaches another module through
    /// ``default``, which is the spelling a host overriding one cap and keeping
    /// the other wants anyway, so `public` here would add a second
    /// cross-module name for the same number.
    static let defaultReturnValueCharacterLimit = 4_000

    /// The stock cap on the joined `console.log` output — the trace of how the
    /// snippet reached its return value.
    ///
    /// Half of ``defaultReturnValueCharacterLimit``, and enforced separately
    /// from it, so a chatty snippet's logging is bounded on its own terms
    /// instead of competing for room with the result it was logging about.
    /// `internal` for the same reason as its sibling.
    static let defaultConsoleCharacterLimit = 2_000

    /// The limits `ResultRenderer.render` enforces when the caller supplies
    /// none — see ``defaultReturnValueCharacterLimit`` and
    /// ``defaultConsoleCharacterLimit`` for how each one is sized.
    public static let `default` = ResultRendererLimits(
        returnValueCharacterLimit: defaultReturnValueCharacterLimit,
        consoleCharacterLimit: defaultConsoleCharacterLimit
    )

    /// Creates a set of render limits, clamping either bound up to `0` if
    /// given a negative value.
    ///
    /// `capped(_:limit:label:)` feeds these limits straight into
    /// `String.prefix(_:)`, whose documented precondition is `maxLength >=
    /// 0` — it traps, rather than throwing, for a negative length. Clamping
    /// here (instead of trusting every caller to pass a non-negative value)
    /// keeps a stray negative config value from crashing a `runCode` turn,
    /// matching this package's established posture of degrading gracefully
    /// at a boundary rather than trapping (e.g. `ArgumentMarshaler`
    /// degrading a non-finite number to `null` instead of throwing). A
    /// clamped `0` limit still renders correctly: `capped` truncates to an
    /// empty prefix and appends its usual truncation note.
    ///
    /// - Parameters:
    ///   - returnValueCharacterLimit: maximum length, in characters, of the
    ///     serialized return value before truncation. Negative values are
    ///     clamped to `0`.
    ///   - consoleCharacterLimit: maximum length, in characters, of the
    ///     joined console output before truncation. Negative values are
    ///     clamped to `0`.
    public init(returnValueCharacterLimit: Int, consoleCharacterLimit: Int) {
        self.returnValueCharacterLimit = max(0, returnValueCharacterLimit)
        self.consoleCharacterLimit = max(0, consoleCharacterLimit)
    }
}

/// The action a repairable `runCode` error closes by naming — the last thing
/// the model reads before it decides what to do next.
///
/// The closing line is a directive, not decoration, and the two failures it
/// has to separate call for opposite moves. A snippet that mis-called a real
/// function, or guessed a name the catalog could resolve to a near match, is
/// worth fixing where it stands: the model already holds real paths, and the
/// error hands it the signature it got wrong. A snippet that named nothing
/// the catalog defines is not — the model has no real path to repair toward,
/// so telling it to fix and re-run is an invitation to guess again, which is
/// the recorded `invented-path` → `thrash` loop (task `tkrdwb8`). That case
/// gets discovery named as the next action instead.
public enum RepairDirective: Sendable, Equatable {
    /// The snippet is worth fixing where it stands.
    case repairSnippet

    /// The snippet named nothing real, so the next move is discovery rather
    /// than another guess.
    case discoverFunctions

    /// The closing line this directive renders as.
    ///
    /// This is the only place the text is written. Both test targets read it
    /// here through `@testable import` instead of restating it, so rewording
    /// the line reaches every assertion that expects it and every synthetic
    /// transcript that stands in for a rendered error, and leaves no copy in
    /// a test to fall out of step with what the product emits. That is what
    /// keeps `internal` the right access level: the text reaches the model
    /// through ``ResultRenderer/render(_:hint:directive:)``, so no other
    /// module needs to read it, and widening it to `public` would add a
    /// second, cross-module contract for the same string.
    var closingLine: String {
        switch self {
        case .repairSnippet:
            "Fix the snippet and call runCode again."
        case .discoverFunctions:
            "Call findAPIs to get the real function names and signatures for this task, "
                + "then write the snippet against those paths."
        }
    }
}

/// Turns the outcome of a `runCode` snippet — either a successful
/// `InterpreterResult` or a thrown `InterpreterError` — into the text handed
/// back to the model, per plan.md's "Output: intermediates stay in the
/// sandbox":
///
/// - the `return` value is JSON-serialized under `ResultRendererLimits
///   .returnValueCharacterLimit`, with a visible truncation note appended
///   when it's cut;
/// - captured `console.log` output is appended under its own, independent
///   `consoleCharacterLimit`;
/// - a failure renders as a **repairable error** — what kind of failure it
///   was, the exact underlying message (which, for a `ToolInvoker`
///   validation failure wrapped as a JS exception by `JSCInterpreter
///   .install(hostFunction:into:)`, is that error's field/constraint text,
///   preserved verbatim through the round trip), and the ``RepairDirective``
///   naming what to do next.
///
/// A clean run (no console output) renders as the return value alone — no
/// error scaffolding — so the common case stays the smallest possible
/// payload back to the model.
public enum ResultRenderer {
    /// Renders a successful `InterpreterResult` as the text handed back to
    /// the model.
    ///
    /// - Parameters:
    ///   - result: the snippet's return value and captured console lines.
    ///   - limits: the size caps to enforce. Defaults to
    ///     `ResultRendererLimits.default`.
    /// - Returns: the serialized (possibly truncated) return value, followed
    ///   by a `Console output:` section when `result.consoleLines` is
    ///   non-empty. Contains no error scaffolding.
    public static func render(_ result: InterpreterResult, limits: ResultRendererLimits = .default) -> String {
        let returnValueText = capped(
            serialize(result.returnValue),
            limit: limits.returnValueCharacterLimit,
            label: "return value"
        )
        guard !result.consoleLines.isEmpty else { return returnValueText }

        let consoleText = capped(
            result.consoleLines.joined(separator: "\n"),
            limit: limits.consoleCharacterLimit,
            label: "console output"
        )
        return "\(returnValueText)\n\nConsole output:\n\(consoleText)"
    }

    /// Renders a thrown `InterpreterError` as a repairable error: what kind
    /// of failure it was, the exact underlying message, an optional repair
    /// hint, and the action to take next.
    ///
    /// - Parameters:
    ///   - error: the failure `Interpreter.run` threw.
    ///   - hint: optional repair guidance (e.g. `UnknownToolHint`'s
    ///     did-you-mean suggestions) spliced between the failure and the
    ///     closing directive, where the model reads it as part of the error
    ///     it is about to fix.
    ///   - directive: what the closing line tells the model to do next.
    ///     Defaults to ``RepairDirective/repairSnippet``, which is right for
    ///     every failure a snippet can be edited out of.
    /// - Returns: the repairable-error text handed back to the model.
    public static func render(
        _ error: InterpreterError,
        hint: String? = nil,
        directive: RepairDirective = .repairSnippet
    ) -> String {
        let summary: String =
            switch error.kind {
            case .exception: "The snippet failed"
            case .timeout: "The snippet timed out"
            }
        let hintSection = hint.map { "\($0)\n\n" } ?? ""
        return "\(summary): \(error.description)\n\n\(hintSection)\(directive.closingLine)"
    }

    // MARK: - Serialization

    /// Serializes `value` to its canonical JSON text — the same shape the
    /// snippet's own `JSON.stringify` would produce, with object keys sorted
    /// for deterministic output.
    ///
    /// - Parameter value: the JSON-shaped value to serialize.
    /// - Returns: the serialized JSON text, or the literal `"null"` in the
    ///   unreachable-in-practice case that encoding fails — every
    ///   `InterpreterValue` an `Interpreter` conformer produces is already
    ///   JSON-safe (`InterpreterValue.encode` degrades a non-finite
    ///   `.number` to `null` rather than throwing), so this fallback is
    ///   defensive, never a trap.
    ///
    private static func serialize(_ value: InterpreterValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard
            let data = try? encoder.encode(value),
            let text = String(data: data, encoding: .utf8)
        else {
            return "null"
        }
        return text
    }

    // MARK: - Truncation

    /// Truncates `text` to at most `limit` characters, appending a visible
    /// truncation note naming `label` when it's cut. A no-op (returns `text`
    /// unchanged) when `text` is already at or under `limit`.
    ///
    /// Cuts with `String.prefix(_:)`, which counts `Character`s (extended
    /// grapheme clusters) — always a safe boundary, never splitting a
    /// multi-byte UTF-8 sequence or a combined character in the middle (see
    /// `ResultRendererLimits`'s documentation).
    ///
    /// - Parameters:
    ///   - text: the text to cap.
    ///   - limit: the maximum length, in characters, to keep.
    ///   - label: what `text` is, for the truncation note (e.g. `"return
    ///     value"`, `"console output"`).
    /// - Returns: `text` unchanged if `text.count <= limit`; otherwise the
    ///   first `limit` characters of `text` followed by a truncation note.
    private static func capped(_ text: String, limit: Int, label: String) -> String {
        let originalLength = text.count
        guard originalLength > limit else { return text }
        let truncated = String(text.prefix(limit))
        return "\(truncated)\n[truncated: \(label) is \(originalLength) characters, "
            + "exceeding the \(limit)-character cap; showing the first \(limit)]"
    }
}
