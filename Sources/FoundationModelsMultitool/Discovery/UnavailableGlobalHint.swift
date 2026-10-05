import Foundation

/// Builds the repair hint for a snippet that used a Node.js or browser global
/// that the `runCode` sandbox does not have.
///
/// A model that learned JavaScript from Node.js code writes `Buffer.from(...)`,
/// `require("fs")` or `process.env`. The sandbox is a bare JavaScriptCore
/// context, and JavaScriptCore answers `ReferenceError: Can't find variable:
/// Buffer`. That text says what failed, but not what to write instead.
///
/// The research of task `^dj4egen` measured a plain `JSContext` on 2026-10-05:
/// every name in ``rows`` is `undefined` there, `TextEncoder`, `atob` and
/// `btoa` included. Thus no advice tells the model to use one of them.
/// `UnavailableGlobalHintTests` runs the same check against the real sandbox,
/// so a name the sandbox gets later fails that test and leaves the table.
///
/// Two decisions keep this a hint and nothing more:
///
/// - **No stub object under the name.** The removed `wait()` keeps a function
///   that throws its repair text. A `Buffer` stub would change what
///   `typeof Buffer` answers, and a snippet that tests for the global first
///   would then take the wrong branch.
/// - **No `imaginedTool` record.** That record collects the tool names a model
///   expects. A Node.js global is not a tool name.
enum UnavailableGlobalHint {
    /// How the hint says that a global is not in the sandbox.
    ///
    /// The only place the phrase is written, so a test reads it from here
    /// and a reword moves the test with it.
    static let unavailablePhrase = "is not available in runCode"

    /// What every hint says about the sandbox, after the phrase.
    private static let sandboxSentence =
        "A runCode snippet runs plain JavaScript, with no Node.js and no browser APIs."

    /// One row of ``rows``: the globals that get the same advice.
    private struct Row {
        /// The global names, spelled as JavaScript spells them.
        let names: Set<String>

        /// What to write instead, in one or two sentences.
        let advice: String
    }

    /// The globals the hint knows, grouped by the advice they get.
    private static let rows = [
        Row(
            names: ["Buffer", "TextEncoder", "TextDecoder", "atob", "btoa"],
            advice: "Keep text in plain strings and arrays. There is no byte buffer and no base64 function."
        ),
        Row(
            names: ["require", "module", "exports", "fs", "__dirname", "__filename"],
            advice: "There are no modules and no file system. Use the tools.* functions to read files and to run commands."
        ),
        Row(
            names: ["process"],
            advice: "There is no process object and no environment. Use the tools.* functions to run commands."
        ),
        Row(
            names: ["setTimeout", "setInterval"],
            advice: "There is no timer. Do not wait inside a snippet."
        ),
        Row(
            names: ["fetch"],
            advice: "There is no network access. Use a tools.* function for web work."
        ),
    ]

    /// Every global name the hint knows.
    static var globalNames: Set<String> {
        rows.reduce(into: []) { names, row in names.formUnion(row.names) }
    }

    /// The hint for a missing-variable error on a known global, or nil.
    ///
    /// Reads the first `Can't find variable: <name>` in `message`, which is
    /// how JavaScriptCore words a `ReferenceError` for an undeclared name.
    /// The match is case-sensitive, because JavaScript names are: `buffer`
    /// is the snippet's own name, not the Node.js global.
    ///
    /// - Parameter message: the thrown JS exception's message text.
    /// - Returns: the hint text, or nil when the message names no global of
    ///   ``rows``.
    static func hint(message: String) -> String? {
        let pattern = /Can't find variable: ([A-Za-z_$][A-Za-z0-9_$]*)/
        guard let name = message.firstMatch(of: pattern).map({ String($0.1) }),
            let row = rows.first(where: { $0.names.contains(name) })
        else { return nil }
        return "\(name) \(unavailablePhrase). \(sandboxSentence) \(row.advice)"
    }
}
