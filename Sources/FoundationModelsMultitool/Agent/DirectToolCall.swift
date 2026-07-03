import Foundation
import FoundationModels
import FoundationModelsRouter

/// A failure from `DirectToolCall`'s own dispatch.
///
/// The escape-hatch counterpart to `ToolInvokerError`/`MultiToolAgentError`:
/// never a failure from the invoked tool itself (that propagates unchanged,
/// exactly like `ToolInvoker.invoke`'s own posture toward a tool's thrown
/// error), and never a failure from deriving the schema or from the guided
/// session (`ToolAPIRendererError` and whatever the session throws both
/// propagate unchanged too — this package's established posture of never
/// wrapping another component's own error type). Only the one novel step
/// `DirectToolCall` itself introduces — turning the guided session's
/// schema-valid `JSONValue` output into a `GeneratedContent` `ToolInvoker`
/// can validate — raises this type.
public struct DirectToolCallError: Error, Sendable, Equatable, CustomStringConvertible {
    /// What kind of failure this was.
    public enum Kind: Sendable, Equatable {
        /// The guided session's schema-valid `JSONValue` output could not be
        /// turned into a `GeneratedContent` — either it failed to re-encode
        /// as JSON text, or `GeneratedContent(json:)` itself rejected that
        /// text. Not expected in practice (the guided output is already
        /// schema-valid JSON), kept as a defensive, reportable failure
        /// rather than a trap, matching this package's "throw rather than
        /// crash" posture (e.g. `ArgumentMarshalerError.malformedOutputJSON`).
        case malformedGuidedOutput
    }

    /// What kind of failure this was.
    public let kind: Kind

    /// A human-readable, model-repairable description of the failure.
    public let message: String

    /// Creates a direct-tool-call error.
    ///
    /// - Parameters:
    ///   - kind: what kind of failure this was.
    ///   - message: a human-readable, model-repairable description.
    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    /// A human-readable description of the error, satisfying
    /// `CustomStringConvertible`. Identical to `message`.
    public var description: String { message }
}

/// The minimal seam `DirectToolCall` drives to get schema-valid arguments
/// for one direct tool call — Router's `RoutedLLM.respond(to:matching:)` (a
/// one-shot, dynamic-JSON guided call over a *runtime* schema), abstracted
/// the same way `AgentSession` abstracts `RoutedSession` for the main loop,
/// so a unit test can drive `DirectToolCall` against a scripted fake with
/// zero GPU and no Router dependency at all.
///
/// Deliberately **not** `AgentSession`: `respond(to:matching:)` lives on
/// `RoutedLLM` (the resolved model *handle*), not `RoutedSession` (a
/// stateful, instruction-rooted session) — confirmed against the Router
/// package source (`Guided/GuidedGeneration.swift`), where it is declared
/// `public func respond(to prompt: String, matching jsonSchema: String)
/// async throws -> JSONValue` on `RoutedModel where Container == any
/// LoadedLLMContainer`. This is a genuinely different primitive than
/// `AgentSession`'s session-based `respond(to:)`: every `DirectToolCall`
/// constrains generation against a *different* runtime schema (the called
/// tool's own `parameters`), not one fixed grammar a long-lived session is
/// rooted on, so there is no session/prefix to reuse across calls — each
/// call derives its own schema and asks fresh.
public protocol DirectCallSession: Sendable {
    /// Generates a response constrained to `jsonSchema`, parsed into a
    /// dynamically-typed `JSONValue` — see `RoutedLLM.respond(to:matching:)`.
    ///
    /// - Parameters:
    ///   - prompt: the prompt to respond to.
    ///   - jsonSchema: the runtime JSON Schema source constraining the
    ///     output.
    /// - Returns: the schema-valid output parsed into a `JSONValue`.
    /// - Throws: whatever the underlying guided-generation call throws.
    func respond(to prompt: String, matching jsonSchema: String) async throws -> JSONValue
}

/// Adapts a Router `RoutedLLM` to the `DirectCallSession` seam
/// `DirectToolCall` drives.
///
/// A thin wrapper, not a reimplementation: the call forwards to the wrapped
/// model handle unchanged — the same "adapts, never reimplements" posture
/// `RoutedAgentSession` takes toward `RoutedSession`.
public struct RoutedDirectCallSession: DirectCallSession {
    /// The Router model handle every call forwards to.
    private let model: RoutedLLM

    /// Wraps `model` as a `DirectCallSession`.
    ///
    /// - Parameter model: the resolved `RoutedLLM` to adapt — typically the
    ///   same handle `MultiToolAgent`'s main loop runs on
    ///   (`MultiToolAgent(model:)`), reused here rather than resolving a
    ///   second, independent slot for the escape hatch.
    public init(model: RoutedLLM) {
        self.model = model
    }

    /// Forwards to the wrapped `RoutedLLM`'s own `respond(to:matching:)` —
    /// see `DirectCallSession.respond(to:matching:)`.
    public func respond(to prompt: String, matching jsonSchema: String) async throws -> JSONValue {
        try await model.respond(to: prompt, matching: jsonSchema)
    }
}

/// plan.md § "Escape hatch — keep the schema-valid-args guarantee": calls
/// one *direct* tool through Router guided generation instead of wrapping it
/// as `tools.*` in a `runCode` snippet, so its arguments stay
/// xgrammar-constrained and schema-valid end to end, at the cost of one
/// extra round trip.
///
/// The pipeline `call(_:task:using:)` runs, per plan.md's description of the
/// escape hatch:
///
/// 1. **Encode** — `tool.parameters: GenerationSchema` is encoded to a raw
///    JSON Schema string via `ToolAPIRenderer.jsonSchemaString(for:)`,
///    reusing M2's own encode path rather than duplicating it.
/// 2. **Constrain** — `session.respond(to:matching:)` constrains a Router
///    turn to that schema (`Grammar.jsonSchema` under the hood), returning
///    schema-valid output as a dynamically-typed `JSONValue` — there is no
///    fixed Swift type to decode into, since `tool`'s `Arguments` type is
///    only known via existential opening, not nameable here as a
///    compile-time `Generable` target.
/// 3. **Marshal** — the schema-valid `JSONValue` is re-encoded to JSON text
///    and parsed into a `GeneratedContent` via `GeneratedContent(json:)`.
/// 4. **Invoke** — the marshaled content is validated and the tool is
///    called natively through `ToolInvoker.invoke(_:content:)` — the exact
///    same invocation core `runCode`'s wrapped-tool path uses, so a direct
///    tool and a wrapped tool share one validation/call pipeline; only how
///    the arguments were produced differs.
public enum DirectToolCall {
    /// Calls `tool` with arguments generated under a grammar derived from
    /// its own schema — see this type's documentation for the full
    /// encode/constrain/marshal/invoke pipeline.
    ///
    /// - Parameters:
    ///   - tool: the direct tool to call. May be passed as a concrete `T` or
    ///     as an `any Tool` existential — SE-0352 implicit opening binds `T`
    ///     to the existential's underlying type either way, the same as
    ///     `ToolInvoker.invoke(_:content:)`.
    ///   - task: a plain-language description of what the caller wants this
    ///     call to accomplish — never the literal argument values
    ///     themselves, which the guided session produces on its own from
    ///     this description and the tool's own schema/description.
    ///   - session: the guided-call seam to constrain generation through —
    ///     production callers pass a `RoutedDirectCallSession`; tests pass a
    ///     scripted fake.
    /// - Returns: `tool`'s `Output`, exactly as `tool.call(arguments:)`
    ///   produced it.
    /// - Throws: `ToolAPIRendererError` if `tool.parameters` can't be
    ///   encoded to a JSON Schema string; whatever `session
    ///   .respond(to:matching:)` throws, unchanged; `DirectToolCallError` if
    ///   the guided output can't be turned into a `GeneratedContent`;
    ///   `ToolInvokerError` if the marshaled content fails pre-call
    ///   validation; otherwise whatever `tool.call(arguments:)` itself
    ///   throws, unchanged.
    public static func call<T: Tool>(
        _ tool: T,
        task: String,
        using session: any DirectCallSession
    ) async throws -> T.Output {
        let schema = try ToolAPIRenderer.jsonSchemaString(for: tool.parameters)
        let value = try await session.respond(to: Self.prompt(for: tool, task: task), matching: schema)
        let content = try Self.content(from: value, toolName: tool.name)
        return try await ToolInvoker.invoke(tool, content: content)
    }

    /// Builds the prompt `session.respond(to:matching:)` generates
    /// schema-valid arguments for — the tool's own name/description (so the
    /// guided model knows what it's filling in arguments for) plus the
    /// caller's plain-language `task`.
    ///
    /// - Parameters:
    ///   - tool: the direct tool being called.
    ///   - task: the plain-language description of what the caller wants
    ///     this call to accomplish.
    /// - Returns: the prompt to constrain generation for.
    private static func prompt<T: Tool>(for tool: T, task: String) -> String {
        """
        Produce arguments for calling the tool "\(tool.name)".
        Tool description: \(tool.description)
        What the caller wants this call to accomplish: \(task)
        Respond with a JSON object matching the required schema.
        """
    }

    /// Turns a guided session's schema-valid `JSONValue` output into a
    /// `GeneratedContent` — re-encoding it to JSON text (`JSONValue` is
    /// `Codable`) and parsing that text via `GeneratedContent(json:)`.
    ///
    /// - Parameters:
    ///   - value: the schema-valid output `session.respond(to:matching:)`
    ///     returned.
    ///   - toolName: the owning tool's name, for the error message.
    /// - Returns: the equivalent `GeneratedContent`.
    /// - Throws: `DirectToolCallError` with kind `.malformedGuidedOutput` if
    ///   `value` fails to re-encode as JSON, or if `GeneratedContent(json:)`
    ///   rejects the re-encoded text.
    private static func content(from value: JSONValue, toolName: String) throws -> GeneratedContent {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw DirectToolCallError(
                kind: .malformedGuidedOutput,
                message: "Tool \"\(toolName)\"'s guided argument output failed to encode: \(error)."
            )
        }
        let json = String(decoding: data, as: UTF8.self)
        do {
            return try GeneratedContent(json: json)
        } catch {
            throw DirectToolCallError(
                kind: .malformedGuidedOutput,
                message: "Tool \"\(toolName)\"'s guided argument output was not valid JSON for GeneratedContent: \(error)."
            )
        }
    }
}
