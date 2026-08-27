import Foundation
import MCP
import Testing

@testable import FoundationModelsMultitool

/// Coverage for the host-overridable render budget (``RenderBudget``):
/// `ToolContentRenderer` applies its own middle-elision budget, but a host
/// like Router *independently* wraps any `Output == String` tool in a
/// `ToolOutputCapping` byte-prefix cap, so a rendered result could otherwise
/// be truncated twice. ``RenderBudget`` lets a host that caps downstream turn
/// this package's own trimming off instead of composing the two.
///
/// A port of the sibling `FoundationModelsMCP` suite `RenderBudget`, renamed
/// so that `swift test --filter RenderBudgetTests` selects it. The sibling
/// exercised the budget at its two host-overridable surfaces, `MCPTool` and
/// `MCPServer`. Neither type is in this package yet, so this port exercises
/// each case of the type through
/// `ToolContentRenderer.render(result:outputSchema:budget:)`, which is the one
/// renderer both surfaces reach. The per-tool and per-server halves come with
/// the ports of those two types.
@Suite("RenderBudgetTests")
struct RenderBudgetTests {

    // MARK: - Shared test-data constants

    /// A custom render budget well below ``ToolContentRenderer/defaultRenderBudget``,
    /// used by the "honors a custom limited budget" test.
    private static let customBudgetCharacterLimit = 100

    /// Text length comfortably larger than ``customBudgetCharacterLimit``,
    /// used by the "honors a custom limited budget" test to guarantee
    /// trimming actually happens.
    private static let largeTextLength = 1_000

    /// How much larger than ``ToolContentRenderer/defaultRenderBudget`` to
    /// make test text in the "default budget still trims" test — just
    /// enough to guarantee the text exceeds the default budget.
    private static let defaultBudgetOverage = 500

    /// The factor to multiply ``ToolContentRenderer/defaultRenderBudget`` by
    /// in the "`.unlimited` disables trimming" test, to guarantee the text
    /// is well past the default budget even though trimming should be off.
    private static let largeTextMultiplier = 3

    /// Wraps `text` as the one `.text` content item of a `tools/call` result.
    private func textResult(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }

    // MARK: - The type itself

    @Test("RenderBudget.default is .limited at ToolContentRenderer.defaultRenderBudget")
    func defaultIsLimitedAtRendererDefault() {
        #expect(RenderBudget.default == .limited(characters: ToolContentRenderer.defaultRenderBudget))
    }

    @Test(".limited maps to its own character count")
    func limitedMapsToItsCharacterCount() {
        let budget = RenderBudget.limited(characters: Self.customBudgetCharacterLimit)
        #expect(budget.characterLimit == Self.customBudgetCharacterLimit)
    }

    @Test(".unlimited maps to Int.max, so no text can reach it")
    func unlimitedMapsToIntMax() {
        #expect(RenderBudget.unlimited.characterLimit == Int.max)
    }

    // MARK: - The renderer: each case of the budget

    @Test("render(result:outputSchema:budget:) honors a custom limited budget")
    func rendererHonorsCustomLimitedBudget() {
        let text = String(repeating: "x", count: Self.largeTextLength)

        let output = ToolContentRenderer.render(
            result: textResult(text), budget: .limited(characters: Self.customBudgetCharacterLimit))

        #expect(output.count <= Self.customBudgetCharacterLimit)
        #expect(output.contains("elided"))
    }

    @Test("render(result:outputSchema:budget: .unlimited) disables trimming — output is byte-for-byte the full rendering")
    func rendererUnlimitedBudgetDisablesTrimming() {
        let text = String(repeating: "y", count: ToolContentRenderer.defaultRenderBudget * Self.largeTextMultiplier)

        let output = ToolContentRenderer.render(result: textResult(text), budget: .unlimited)

        #expect(output == text)
    }

    @Test("render(result:outputSchema:budget: .default) still trims at ToolContentRenderer.defaultRenderBudget — unchanged default behavior")
    func rendererDefaultBudgetMatchesRendererDefault() {
        let text = String(repeating: "z", count: ToolContentRenderer.defaultRenderBudget + Self.defaultBudgetOverage)

        let output = ToolContentRenderer.render(result: textResult(text), budget: .default)

        let expected = ToolContentRenderer.render(
            result: textResult(text), budget: ToolContentRenderer.defaultRenderBudget)
        #expect(output == expected)
        #expect(output.contains("elided"))
    }
}
