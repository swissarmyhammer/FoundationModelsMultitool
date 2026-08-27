// `RenderBudget` — how large one rendered text unit may grow before
// `ToolContentRenderer` trims it.
//
// A behavioral port of `../FoundationModelsMCP/Sources/FoundationModelsMCP/
// RenderBudget.swift`. eventplan.md § "Consolidation of the siblings" moves
// "`ToolContentRenderer` with its `RenderBudget`" into this folder. The
// renderer is the reader: a host sets a budget on the server, or on one tool,
// and each `tools/call` result of that tool renders under it.
//
// **Why the budget is a type, and not a number.** `ToolContentRenderer` keeps
// a size budget of its own, because a rendered tool result is context-window
// cost. But a host can apply a second cap of its own on top of the rendered
// text. FoundationModelsRouter is such a host: it wraps any tool whose
// `Output == String` in a `ToolOutputCapping` decorator, found by a runtime
// cast with no cooperation from the tool. A rendered MCP result can then be
// truncated two times — the middle elision here, and a byte-prefix cap there —
// and the second pass does not know that the first one spent part of the
// budget on an elision marker. A byte-prefix cap that lands inside the marker
// makes the visible text disagree with the count the marker states. So the
// budget is a decision: `limited(characters:)` keeps the elision, and
// `unlimited` turns it off for a host that caps downstream.
//
// **The types are internal.** The Shell capability keeps its types internal,
// and this folder does the same: `MCPTool` and `MCPServer`, which come in later
// tasks, are the production callers, and the tests reach the type with
// `@testable import`.

/// How large a single rendered text unit — a `.text`/`.resource` content
/// item's text, or `structuredContent`'s JSON — may grow before
/// ``ToolContentRenderer`` trims it.
///
/// - ``limited(characters:)`` — the middle-elision behavior
///   `ToolContentRenderer` has always had: text over the limit is trimmed,
///   with an elision marker naming exactly how much was removed.
/// - ``unlimited`` — trimming is off entirely. `ToolContentRenderer` renders
///   every text unit in full, however large, so the result a host receives
///   is byte-for-byte the untrimmed rendering.
/// - ``default`` — ``limited(characters:)`` at
///   ``ToolContentRenderer/defaultRenderBudget``. Every host that configures
///   nothing keeps the stock trimming exactly as it is.
///
/// - Important: **If your host caps tool output downstream — Router's
///   `ToolOutputCapping` or an equivalent of your own — set this to**
///   ``unlimited`` **on the server (or the individual tool) it applies to.**
///   The two passes are not designed to compose: pick exactly one place to
///   trim, and let this package's trimming be the one that yields when a host
///   already owns that job downstream.
enum RenderBudget: Sendable, Equatable {
    /// Trim any single rendered text unit that exceeds `characters`,
    /// replacing its middle with an elision marker naming exactly how many
    /// characters were removed — see `ToolContentRenderer`'s
    /// `trimmed(text:budget:)`.
    case limited(characters: Int)

    /// Never trim: every rendered text unit is returned in full, however
    /// large — the setting for a host that caps output downstream itself
    /// (see this type's own documentation for why the two must not compose).
    case unlimited

    /// The default render budget: ``limited(characters:)`` at
    /// ``ToolContentRenderer/defaultRenderBudget`` — unchanged from the
    /// sibling package's behavior for every host that configures nothing.
    static let `default`: RenderBudget = .limited(characters: ToolContentRenderer.defaultRenderBudget)

    /// The character budget to pass to `ToolContentRenderer.render(result:outputSchema:budget:)`.
    ///
    /// `unlimited` maps to `Int.max` rather than a sentinel `ToolContentRenderer`
    /// itself must special-case: `trimmed(text:budget:)` only ever trims when
    /// a text's character count exceeds its budget, and no `String` in
    /// practice can reach `Int.max` characters, so passing it through
    /// unmodified already guarantees "never trims" with no change to the
    /// renderer's own trimming logic.
    var characterLimit: Int {
        switch self {
        case .limited(let characters):
            return characters
        case .unlimited:
            return .max
        }
    }
}
