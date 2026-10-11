import FoundationModelsMultitool
import Testing

/// Tests for ``MultiTool/callsNoTool(snippet:)``: the static check that tells
/// a host that a `runCode` snippet calls no `tools.*` verb.
///
/// The check reads the snippet text only. No test here runs a snippet, so a
/// snippet that never settles (`await new Promise(() => {});`) is safe to
/// give to it.
@Suite struct NoOpSnippetTests {
    /// The no-op snippets that SWE-bench run no-otel-1011 recorded while a
    /// `tools.*` call was pending, and the empty snippet. None of them names
    /// `tools`, thus each one is a no-op.
    @Test(arguments: [
        "return null",
        "return \"waiting 3\"",
        "",
        "return \"stop\";",
        "return 1;",
        "1",
        "return \"waiting for 01M4P046...\";",
        "await new Promise(() => {});"
    ])
    func snippetThatNamesNoToolsCallsNoTool(snippet: String) {
        #expect(MultiTool.callsNoTool(snippet: snippet))
    }

    /// Each snippet can call a `tools.*` verb: directly, through an alias,
    /// through a computed member, or with `tools` at the start or the end of
    /// the text. The check must never mark one of them as a no-op.
    @Test(arguments: [
        "return await tools.shell.execute({ command: \"ls\" });",
        "const t = tools; return await t.shell.execute({ command: \"ls\" });",
        "return await tools[\"shell\"].execute({ command: \"ls\" });",
        "tools",
        "return tools",
        "(tools).git.status({})",
        "return [tools.shell];",
        "x=tools\n"
    ])
    func snippetThatNamesToolsCanCallATool(snippet: String) {
        #expect(!MultiTool.callsNoTool(snippet: snippet))
    }

    /// A word that only holds the letters `tools` is a different identifier,
    /// thus it does not reach the `tools` global.
    @Test(arguments: [
        "return devtools;",
        "return toolset;",
        "return $tools;",
        "return tools_;",
        "return tools2;"
    ])
    func longerIdentifierThatHoldsToolsCallsNoTool(snippet: String) {
        #expect(MultiTool.callsNoTool(snippet: snippet))
    }

    /// JavaScript lets an identifier hold a `\u` escape, so the snippet
    /// text below names the identifier `tools`. A snippet with a `\u`
    /// escape is never marked as a no-op.
    @Test func unicodeEscapeIsNeverANoOp() {
        #expect(!MultiTool.callsNoTool(snippet: "return t\\u006fols.shell;"))
    }
}
