import Foundation
import FoundationModels
import FoundationModelsRouter

/// plan.md Router integration option 1 ("Guided turns"): a `@Generable`
/// union of `{ findAPIs(task) | runCode(code) | final(text) }`, constrained
/// via Router guided generation (`respond(to:generating:)` / a
/// `.jsonSchema` grammar) so every agent turn is parseable by construction —
/// no repair turn needed for format errors (tool-arg errors still repair via
/// `ResultRenderer`).
///
/// **`@Generable` has no true sum type.** A Swift `enum` case with per-case
/// associated values does not itself become a discriminated-union
/// `GenerationSchema` in this SDK — confirmed against the compiled
/// `FoundationModels.swiftinterface` and this package's own
/// `ToolAPIRenderer` findings: `GenerationGuide.anyOf(_:)`, the mechanism
/// behind an "enum choice" schema element, is `where Value == String` only
/// (see `ToolAPIRenderer.enumUnion(_:)`'s documentation), so there is no
/// SDK path from a payload-carrying `enum` case to a schema at all. So this
/// type takes the shape plan.md's M4c task calls for instead: a flat struct
/// with a `kind` field (itself a payload-less `@Generable enum` — which
/// *is* supported, and encodes to a plain `{"type":"string","enum":[…]}`,
/// confirmed the same way) discriminating which of the three optional
/// payload fields (`task`/`code`/`text`) is populated.
///
/// `asAgentStep()` below is where the cross-field "only the field matching
/// `kind` is set" rule is actually enforced — xgrammar's JSON-schema subset
/// (no `$ref`/`allOf`/`format`, see `GuidedTurnFormat`'s documentation) has
/// no per-discriminant conditional-required construct to express that rule
/// in the grammar itself.
@Generable
public struct AgentTurn: Sendable, Equatable {
    /// Which action this turn takes — the discriminant `asAgentStep()`
    /// switches on to decide which of `task`/`code`/`text` must be set. See
    /// `AgentTurn`'s documentation for why this is a plain, payload-less
    /// enum rather than the union itself.
    @Generable
    public enum Kind: String, Sendable, Equatable {
        /// Search for relevant tool functions — plan.md's `findAPIs(task: string)`.
        case findAPIs
        /// Run a JavaScript snippet against `tools.*` — plan.md's `runCode(code: string)`.
        case runCode
        /// Call one *direct* tool with a schema-valid argument guarantee —
        /// plan.md's escape hatch, `callTool(name, args)`.
        case callTool
        /// Give the final answer to the user.
        case final
    }

    /// Which action this turn takes.
    @Guide(
        description: "which action this turn takes: \"findAPIs\" to search for tool functions, "
            + "\"runCode\" to run a JavaScript snippet, \"callTool\" to call a direct tool with a "
            + "schema-valid argument guarantee, or \"final\" to give the final answer."
    )
    public var kind: Kind

    /// The plain-language goal to search for, or (for `callTool`) a
    /// plain-language description of the arguments to use — set only when
    /// `kind` is `.findAPIs` or `.callTool`.
    @Guide(
        description: "for \"findAPIs\", the goal to search for, in plain language; for \"callTool\", a "
            + "plain-language description of the arguments to use — never the literal argument values "
            + "themselves. Set only when kind is \"findAPIs\" or \"callTool\"."
    )
    public var task: String?

    /// The JavaScript snippet to run against `tools.*` — set only when `kind` is `.runCode`.
    @Guide(description: "the JavaScript snippet to run against tools.*. Set only when kind is \"runCode\".")
    public var code: String?

    /// The exact name of the direct tool to call — set only when `kind` is `.callTool`.
    @Guide(description: "the exact name of the direct tool to call. Set only when kind is \"callTool\".")
    public var toolName: String?

    /// The final answer text — set only when `kind` is `.final`.
    @Guide(description: "the final answer text to give the user. Set only when kind is \"final\".")
    public var text: String?

    /// Creates a guided agent turn.
    ///
    /// Explicit for the same reason as this package's other public
    /// `@Generable` struct initializers (e.g. `ToolDescriptor.init`): a
    /// `public` struct's synthesized memberwise initializer is only
    /// `internal`-accessible.
    ///
    /// - Parameters:
    ///   - kind: which action this turn takes.
    ///   - task: the plain-language goal to search for, or (for `callTool`)
    ///     a plain-language description of the arguments to use. Defaults
    ///     to `nil`.
    ///   - code: the JavaScript snippet to run. Defaults to `nil`.
    ///   - toolName: the exact name of the direct tool to call. Defaults to
    ///     `nil`.
    ///   - text: the final answer text. Defaults to `nil`.
    public init(
        kind: Kind,
        task: String? = nil,
        code: String? = nil,
        toolName: String? = nil,
        text: String? = nil
    ) {
        self.kind = kind
        self.task = task
        self.code = code
        self.toolName = toolName
        self.text = text
    }

    /// Converts this decoded guided turn into the shared `AgentStep`
    /// `MultiToolAgent.respond(to:)` dispatches on.
    ///
    /// The grammar constrains `AgentTurn`'s JSON *shape* (which fields exist
    /// and their types), not the cross-field rule that only the field
    /// matching `kind` is populated — see this type's documentation. This
    /// method enforces that rule.
    ///
    /// - Returns: the corresponding `AgentStep`.
    /// - Throws: `TurnParseError` if the field matching `kind` is missing or
    ///   blank.
    func asAgentStep() throws -> AgentStep {
        switch kind {
        case .findAPIs:
            guard let task, Self.isNonBlank(task) else {
                throw TurnParseError(message: "A guided turn with kind \"\(kind.rawValue)\" must set a non-empty \"task\".")
            }
            return .findAPIs(task: task)

        case .runCode:
            guard let code, Self.isNonBlank(code) else {
                throw TurnParseError(message: "A guided turn with kind \"\(kind.rawValue)\" must set a non-empty \"code\".")
            }
            return .runCode(code: code)

        case .callTool:
            guard let toolName, Self.isNonBlank(toolName) else {
                throw TurnParseError(
                    message: "A guided turn with kind \"\(kind.rawValue)\" must set a non-empty \"toolName\"."
                )
            }
            guard let task, Self.isNonBlank(task) else {
                throw TurnParseError(
                    message: "A guided turn with kind \"\(kind.rawValue)\" must set a non-empty \"task\" describing "
                        + "the arguments to use."
                )
            }
            return .callTool(name: toolName, task: task)

        case .final:
            guard let text, Self.isNonBlank(text) else {
                throw TurnParseError(message: "A guided turn with kind \"\(kind.rawValue)\" must set a non-empty \"text\".")
            }
            return .final(text: text)
        }
    }

    /// Whether `value` has any non-whitespace content — the blank-check
    /// `asAgentStep()` applies uniformly to `task`/`code`/`text`, so a
    /// whitespace-only field (e.g. `"   "`) is rejected the same way a
    /// missing one is, for every kind alike (matching
    /// `TolerantParseTurnFormat`'s own always-trimmed field extraction).
    ///
    /// - Parameter value: the field value to check.
    /// - Returns: `true` if `value` contains at least one non-whitespace
    ///   character.
    private static func isNonBlank(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The derived JSON Schema source for `AgentTurn.generationSchema`,
    /// computed once and cached — the one source of truth `GuidedTurnFormat`
    /// constrains its session's grammar to, and the schema-subset fixture
    /// check in `GuidedTurnFormatTests` asserts stays within Router's
    /// xgrammar subset.
    ///
    /// `AgentTurn` is a fixed, compile-time `@Generable` type, so
    /// `JSONEncoder().encode(_:)` failing here would mean a broken invariant
    /// in this type's own definition, not a runtime condition — the same
    /// category `MultiTool.invokeBlocking`'s `preconditionFailure` documents
    /// for its own unreachable-in-practice branch.
    static let jsonSchemaSource: String = {
        do {
            let data = try JSONEncoder().encode(AgentTurn.generationSchema)
            return String(decoding: data, as: UTF8.self)
        } catch {
            preconditionFailure(
                "AgentTurn.jsonSchemaSource: JSONEncoder().encode(AgentTurn.generationSchema) failed (\(error)). "
                    + "AgentTurn is a fixed, compile-time @Generable type, so an encoding failure here indicates "
                    + "a broken invariant in this type's own definition, not a runtime condition."
            )
        }
    }()
}

/// plan.md Router integration option 1 ("Guided turns"): constrains every
/// turn to `AgentTurn`'s schema via Router guided generation, so each step
/// is parseable by construction — the M4c sibling to M4b's
/// `TolerantParseTurnFormat`.
///
/// Because `MultiToolAgent`'s loop (`respond(to:)`) is written entirely
/// against the `TurnFormat` protocol, this conformer plugs in without any
/// change to the loop itself: `MultiToolAgent`'s production initializer
/// reads `grammar` below to build the main session via
/// `RoutedLLM.makeGuidedSession(_:instructions:workingDirectory:)` instead
/// of the plain `RoutedLLM.makeSession(instructions:workingDirectory:)`, and
/// from there the loop's dispatch/max-turns/error-feedback code is
/// unchanged and unaware which strategy is in use.
public struct GuidedTurnFormat: TurnFormat {
    /// How many consecutive parse failures this format tolerates before
    /// `MultiToolAgent.respond(to:)` fails the loop — see
    /// `TurnFormat.maxRepairTurns`. Guided generation makes a parse failure
    /// rare (the session's grammar already constrains `AgentTurn`'s JSON
    /// *shape*), but `AgentTurn.asAgentStep()`'s cross-field validation can
    /// still reject a schema-valid-but-semantically-empty turn, so a small
    /// budget stays useful. Set at `init`, clamped to `0` or above.
    public let maxRepairTurns: Int

    /// Creates a guided turn format.
    ///
    /// - Parameter maxRepairTurns: how many consecutive parse failures to
    ///   tolerate before `MultiToolAgent.respond(to:)` fails the loop.
    ///   Negative values are clamped to `0`. Defaults to `1`.
    public init(maxRepairTurns: Int = 1) {
        self.maxRepairTurns = max(0, maxRepairTurns)
    }

    /// The grammar every turn is constrained to — `AgentTurn`'s derived JSON
    /// Schema, wrapped as `Grammar.jsonSchema(_:)`. See `TurnFormat.grammar`.
    public var grammar: Grammar? {
        .jsonSchema(AgentTurn.jsonSchemaSource)
    }

    /// Briefly explains the guided turn's fields — see
    /// `TurnFormat.formatInstructions(supportsFindAPIs:supportsDirectCall:)`.
    /// The response *shape* is already enforced by `grammar`, so this text
    /// only needs to teach the model the *semantics* of
    /// `kind`/`task`/`code`/`toolName`/`text`, not a response format to
    /// follow.
    ///
    /// - Parameters:
    ///   - supportsFindAPIs: whether to invite the model to use the
    ///     `findAPIs` kind; direct mode gets an explicit note that it isn't
    ///     available instead, since the grammar's `kind` enum always allows
    ///     every value regardless of this flag (only `MultiToolAgent
    ///     .dispatchFindAPIs`'s runtime rejection actually enforces
    ///     unavailability).
    ///   - supportsDirectCall: whether to invite the model to use the
    ///     `callTool` kind; an agent with no direct tools configured gets an
    ///     explicit note that it isn't available instead, for the same
    ///     grammar-always-allows-it reason as `supportsFindAPIs`. Defaults
    ///     to `false` (matching this method's own default for pre-existing
    ///     call sites that never exercise the escape hatch).
    /// - Returns: the format instructions.
    public func formatInstructions(supportsFindAPIs: Bool, supportsDirectCall: Bool = false) -> String {
        var lines = [
            "Each turn, respond with a single JSON object matching the required schema.",
            "Set \"kind\" to \"\(AgentTurn.Kind.runCode.rawValue)\" and \"code\" to the JavaScript snippet to run,",
            "or set \"kind\" to \"\(AgentTurn.Kind.final.rawValue)\" and \"text\" to your final answer.",
        ]
        if supportsFindAPIs {
            lines.append(
                "Set \"kind\" to \"\(AgentTurn.Kind.findAPIs.rawValue)\" and \"task\" to search for relevant tool "
                    + "functions first."
            )
        } else {
            lines.append(
                "\"\(AgentTurn.Kind.findAPIs.rawValue)\" is not available in this session; use help()/docs(name) "
                    + "inside runCode instead."
            )
        }
        if supportsDirectCall {
            lines.append(
                "Set \"kind\" to \"\(AgentTurn.Kind.callTool.rawValue)\", \"toolName\" to the exact name of the "
                    + "direct tool to call, and \"task\" to a plain-language description of the arguments to use, "
                    + "to call a direct tool with a schema-valid argument guarantee."
            )
        } else {
            lines.append(
                "\"\(AgentTurn.Kind.callTool.rawValue)\" is not available in this session."
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Decodes `raw` as `AgentTurn` JSON and converts it to an `AgentStep` —
    /// see `TurnFormat.parseTurn(_:)`.
    ///
    /// - Parameter raw: the session's raw text response — schema-valid JSON
    ///   when the session was actually created via
    ///   `RoutedLLM.makeGuidedSession(_:instructions:workingDirectory:)`
    ///   with this format's `grammar`.
    /// - Returns: the parsed step.
    /// - Throws: `TurnParseError` if `raw` isn't valid `AgentTurn` JSON, or
    ///   if it decodes but fails `AgentTurn.asAgentStep()`'s cross-field
    ///   validation.
    public func parseTurn(_ raw: String) throws -> AgentStep {
        let turn: AgentTurn
        do {
            turn = try AgentTurn(GeneratedContent(json: raw))
        } catch {
            throw TurnParseError(message: "Could not decode a guided AgentTurn from the model's response: \(error).")
        }
        return try turn.asAgentStep()
    }

    /// Builds the repair-turn text fed back to the model after a parse
    /// failure — see `TurnFormat.repairInstruction(for:)`.
    ///
    /// - Parameter error: the error `parseTurn(_:)` threw — its
    ///   `TurnParseError.message` when available, else its description.
    /// - Returns: the repair instruction to append to the transcript.
    public func repairInstruction(for error: Error) -> String {
        return """
            Your previous response could not be used: \(TurnParseError.reason(for: error))

            Respond again with a single well-formed JSON object matching the required schema.
            """
    }
}

extension TurnFormat where Self == GuidedTurnFormat {
    /// Plan.md's "Guided turns" strategy — see `GuidedTurnFormat`.
    ///
    /// - Parameter maxRepairTurns: how many consecutive parse failures to
    ///   tolerate before the loop fails. Defaults to `1`.
    /// - Returns: a `GuidedTurnFormat` configured with `maxRepairTurns`.
    public static func guided(maxRepairTurns: Int = 1) -> GuidedTurnFormat {
        GuidedTurnFormat(maxRepairTurns: maxRepairTurns)
    }
}
