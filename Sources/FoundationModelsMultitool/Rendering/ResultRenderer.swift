import Foundation

/// The size caps `ResultRenderer` enforces when it turns an `InterpreterResult`
/// into the text handed back to the model, so a fat tool result or noisy
/// console output can never flood the model's context.
///
/// Both caps count `Character`s — Swift's extended grapheme clusters, not raw
/// UTF-8 bytes or UTF-16 code units — so that truncation always cuts at a
/// `String.prefix(_:)` boundary. That boundary never splits a multi-byte UTF-8
/// sequence or a combined grapheme cluster, which a byte-offset cap could do to
/// a snippet's return value or console output. Both are arbitrary,
/// model/tool-derived text this renderer must never corrupt while it trims.
public struct ResultRendererLimits: Sendable, Equatable {
    /// Maximum length, in characters, the serialized `return` value may
    /// reach before `ResultRenderer` truncates it.
    public let returnValueCharacterLimit: Int

    /// Maximum length, in characters, the joined `console.log` output may reach
    /// before `ResultRenderer` truncates it. It is capped independently of
    /// ``returnValueCharacterLimit``, so a chatty snippet's logging can never
    /// crowd out its actual result.
    public let consoleCharacterLimit: Int

    /// The stock cap on the serialized return value — the answer the snippet
    /// was run for. Generous enough to carry an ordinary tool result whole,
    /// while a pathological result stays bounded.
    ///
    /// Twice ``defaultConsoleCharacterLimit``, because this is the value the
    /// model asked for and console output is only the trace of how the snippet
    /// reached it. When a snippet pushes on both caps at once, the answer keeps
    /// the larger share of the model's context.
    ///
    /// `internal`, not `public`: the value already reaches another module
    /// through ``default``, which is the spelling a host that overrides one cap
    /// and keeps the other wants anyway, so `public` here would add a second
    /// cross-module name for the same number.
    static let defaultReturnValueCharacterLimit = 4_000

    /// The stock cap on the joined `console.log` output — the trace of how the
    /// snippet reached its return value.
    ///
    /// Half of ``defaultReturnValueCharacterLimit``, and enforced separately,
    /// so a chatty snippet's logging is bounded on its own terms instead of
    /// competing for room with the result it logs about. `internal` for the
    /// same reason as its sibling.
    static let defaultConsoleCharacterLimit = 2_000

    /// The limits `ResultRenderer.render` enforces when the caller supplies
    /// none.
    public static let `default` = ResultRendererLimits(
        returnValueCharacterLimit: defaultReturnValueCharacterLimit,
        consoleCharacterLimit: defaultConsoleCharacterLimit
    )

    /// Creates a set of render limits, clamping either bound up to `0` if given
    /// a negative value.
    ///
    /// `capped(_:limit:label:)` feeds these limits straight into
    /// `String.prefix(_:)`, whose documented precondition is `maxLength >= 0`:
    /// it traps on a negative length rather than throwing. The clamp here keeps
    /// a stray negative configuration value from crashing a `runCode` turn, and
    /// matches this package's posture of degrading at a boundary rather than
    /// trapping (`ArgumentMarshaler` degrades a non-finite number to `null`).
    /// A clamped `0` limit still renders correctly: `capped` truncates to an
    /// empty prefix and appends its usual truncation note.
    public init(returnValueCharacterLimit: Int, consoleCharacterLimit: Int) {
        self.returnValueCharacterLimit = max(0, returnValueCharacterLimit)
        self.consoleCharacterLimit = max(0, consoleCharacterLimit)
    }
}

/// The action a repairable `runCode` error closes by naming — the last thing
/// the model reads before it decides what to do next.
///
/// The closing line is a directive, and the two failures it separates call for
/// opposite moves. A snippet that mis-called a real function, or guessed a name
/// the catalog can resolve to a near match, is worth fixing where it stands:
/// the model already holds real paths, and the error hands it the signature it
/// got wrong. A snippet that named nothing the catalog defines is not. The
/// model has no real path to repair toward, so an instruction to fix and re-run
/// invites another guess — the recorded `invented-path` → `thrash` loop (task
/// `tkrdwb8`). That case gets discovery named as the next action instead.
public enum RepairDirective: Sendable, Equatable {
    /// The snippet is worth fixing where it stands.
    case repairSnippet

    /// The snippet named nothing real, so the next move is discovery rather
    /// than another guess.
    case discoverFunctions

    /// The closing line this directive renders as.
    ///
    /// This is the only place the text is written. Both test targets read it
    /// here through `@testable import` instead of restating it, so a reword
    /// reaches every assertion and every synthetic transcript that expects it.
    /// `internal` is therefore the right access level: the text reaches the
    /// model through ``ResultRenderer/render(_:hint:directive:)``, so no other
    /// module needs to read it.
    var closingLine: String {
        switch self {
        case .repairSnippet:
            "Fix the snippet and call runCode again."
        case .discoverFunctions:
            "Call searchTools to get the real function names and signatures for this task, "
                + "then write the snippet against those paths."
        }
    }
}

extension InterpreterError.Kind {
    /// The summary a repairable error opens with — which kind of failure the
    /// underlying message describes.
    ///
    /// The only place the text is written, and `internal` for the reason
    /// ``RepairDirective/closingLine`` gives. `FoundationModelsMultitoolTests`
    /// reads it here through `@testable import` rather than restating it, so a
    /// reword reaches every assertion that expects it.
    /// `FoundationModelsMultitoolIntegrationTests` needs no reference of its
    /// own, because its synthetic transcripts render through
    /// ``ResultRenderer/render(_:hint:directive:)`` and pick up the reword with
    /// them.
    var repairableErrorSummary: String {
        switch self {
        case .exception: "The snippet failed"
        case .timeout: "The snippet timed out"
        }
    }
}

/// Turns the outcome of a `runCode` snippet — a successful `InterpreterResult`
/// or a thrown `InterpreterError` — into the text handed back to the model, per
/// plan.md's "Output: intermediates stay in the sandbox":
///
/// - the `return` value is JSON-serialized under
///   `ResultRendererLimits.returnValueCharacterLimit`, with a visible
///   truncation note appended when it is cut;
/// - captured `console.log` output is appended under its own, independent
///   `consoleCharacterLimit`;
/// - a failure renders as a **repairable error** — what kind of failure it was,
///   the exact underlying message, and the ``RepairDirective`` that names what
///   to do next. For a `ToolInvoker` validation failure that `JSCInterpreter
///   .install(hostFunction:into:)` wraps as a JS exception, that message is the
///   error's own field and constraint text, preserved through the round trip.
///
/// A clean run with no console output renders as the return value alone, with
/// no error scaffolding, so the common case stays the smallest possible payload
/// back to the model.
public enum ResultRenderer {
    /// The word a truncation note opens with.
    ///
    /// The only place it is written: ``capped(_:limit:label:)`` builds its note
    /// from it, and `FoundationModelsMultitoolTests` reads it here rather than
    /// restating it. That matters most for the expectations that assert a note
    /// is *absent* — a copy of the word in a test would go on satisfying
    /// `!output.contains(_:)` after a reword, and hold whether or not anything
    /// was truncated. `internal` is the right access level: the word reaches
    /// the model inside rendered text, so no other module needs to read it.
    static let truncationMarker = "truncated"

    /// Renders a successful `InterpreterResult` as the text handed back to the
    /// model.
    ///
    /// `result` carries the snippet's return value and its captured console
    /// lines. `limits` are the size caps to enforce, and default to
    /// `ResultRendererLimits.default`. `notice` is an in-band notice about the
    /// run itself — see ``ToolReturnLedger/uncarriedReturnNotice``.
    ///
    /// - Returns: the serialized, and possibly truncated, return value; then a
    ///   `Console output:` section when `result.consoleLines` is not empty;
    ///   then `notice` when there is one. It holds no error scaffolding.
    public static func render(
        _ result: InterpreterResult,
        limits: ResultRendererLimits = .default,
        notice: String? = nil
    ) -> String {
        let returnValueText = capped(
            serialize(result.returnValue),
            limit: limits.returnValueCharacterLimit,
            label: "return value"
        )
        // Last, for `RepairDirective.closingLine`'s reason: what to do next is
        // what the model reads immediately before deciding what to do next.
        let noticeSection = notice.map { "\n\n\($0)" } ?? ""
        guard !result.consoleLines.isEmpty else { return returnValueText + noticeSection }

        let consoleText = capped(
            result.consoleLines.joined(separator: "\n"),
            limit: limits.consoleCharacterLimit,
            label: "console output"
        )
        return "\(returnValueText)\n\nConsole output:\n\(consoleText)\(noticeSection)"
    }

    /// Renders a thrown `InterpreterError` as a repairable error: what kind of
    /// failure it was, the exact underlying message, an optional repair hint,
    /// and the action to take next.
    ///
    /// `error` is the failure `Interpreter.run` threw. `hint` — for example
    /// `UnknownToolHint`'s did-you-mean suggestions — is spliced between the
    /// failure and the closing directive, where the model reads it as part of
    /// the error it is about to fix. `directive` defaults to
    /// ``RepairDirective/repairSnippet``, which is right for every failure a
    /// snippet can be edited out of.
    ///
    /// - Returns: the repairable-error text handed back to the model.
    public static func render(
        _ error: InterpreterError,
        hint: String? = nil,
        directive: RepairDirective = .repairSnippet
    ) -> String {
        let hintSection = hint.map { "\($0)\n\n" } ?? ""
        return "\(error.kind.repairableErrorSummary): \(error.description)\n\n"
            + "\(hintSection)\(directive.closingLine)"
    }

    // MARK: - Serialization

    /// Serializes `value` to its canonical JSON text — the same shape the
    /// snippet's own `JSON.stringify` would produce, with object keys sorted
    /// for deterministic output.
    ///
    /// - Returns: the serialized JSON text, or the literal `"null"` if encoding
    ///   fails. That case is unreachable in practice, because every
    ///   `InterpreterValue` an `Interpreter` conformer produces is already
    ///   JSON-safe: `InterpreterValue.encode` degrades a non-finite `.number`
    ///   to `null` rather than throwing. The fallback is defensive, never a
    ///   trap.
    ///
    /// `internal` rather than `private`, since task `wnfzwxg`:
    /// `ToolReturnLedger` reads a scalar's text through this same function, so
    /// the text it compares against and the text the model reads cannot be
    /// spelled two ways. No other module needs it, so `public` would add a
    /// second cross-module name for one serialization.
    static func serialize(_ value: InterpreterValue) -> String {
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

    /// Truncates `text` to at most `limit` characters, and appends a visible
    /// truncation note that names `label` when it cuts. A no-op when `text` is
    /// already at or under `limit`. `label` says what `text` is, for the note —
    /// a caller passes `"return value"` or `"console output"`.
    ///
    /// Cuts with `String.prefix(_:)`, which counts `Character`s — always a safe
    /// boundary, for the reason ``ResultRendererLimits`` gives.
    private static func capped(_ text: String, limit: Int, label: String) -> String {
        let originalLength = text.count
        guard originalLength > limit else { return text }
        let truncated = String(text.prefix(limit))
        return "\(truncated)\n[\(Self.truncationMarker): \(label) is \(originalLength) characters, "
            + "exceeding the \(limit)-character cap; showing the first \(limit)]"
    }
}
