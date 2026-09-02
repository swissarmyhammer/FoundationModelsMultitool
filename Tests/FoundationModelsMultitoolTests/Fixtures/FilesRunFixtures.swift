// `FilesRunFixtures` — a files registry beside a stub run, and the one way to
// run a `runCode` snippet over a registry.
//
// A suite that proves what the files verbs deliver to a session needs the
// same ground each time: a canonical root the test owns, a registry built
// with `MultiTool.Builder().withFiles(root:recordsChanges:)` over it, the
// change journal of that registry, and a stub run from `makeStubRun()` whose
// transcript the suite reads back. `makeFilesRun(named:recordsChanges:alongside:)`
// is that ground, built one time here rather than once for each suite.
//
// `runSnippet(_:over:under:)` is the one way a test drives a `MultiTool` over
// a registry: with a context, the way a Router session binds one around the
// outer run, or with none, which is the bare-session mode every other unit
// suite runs in. `runSnippet(_:through:under:)` is the same drive over a
// `MultiTool` the test already holds, for a test whose two calls must share
// one.
//
// `writeVerbCall(writing:content:)` and `writeVerbSnippet(writing:content:)`
// are the write a model makes, as JavaScript, thus each suite that writes one
// file through `tools.files.write` writes the same call.

import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// The registry path of the write verb, through which a test reaches the
/// change journal the six files verbs share.
private let writeVerbPath = "files.write"

/// A stub run beside a files registry rooted in a canonical directory the
/// test owns, and the change journal the registry's verbs share.
struct FilesRun {
    /// The stub session and its context.
    let run: StubRun

    /// The registry that holds the six files verbs.
    let registry: MultiTool.Registry

    /// The canonical session root.
    let root: URL

    /// The change journal the registry's verbs share.
    let journal: FileChangeJournal
}

/// Builds a files run: a canonical root, a files registry over it, the
/// journal of that registry, and a stub run.
///
/// The root is canonicalized, because the path guard canonicalizes every path
/// it resolves and a test that compares a path a verb reports against one it
/// builds from the root must start from the same spelling.
///
/// - Parameters:
///   - directoryName: the prefix of the temporary root, thus a leaked
///     directory is traceable to the suite that made it.
///   - recordsChanges: whether the capability records changes.
///   - tools: the standalone tools to register beside the files verbs, each
///     at `tools.<name>`. Defaults to none.
/// - Returns: the files run.
/// - Throws: when the registry does not build, holds no write verb, or
///   standing up the stub run throws.
func makeFilesRun(
    named directoryName: String, recordsChanges: Bool, alongside tools: [any Tool] = []
) async throws -> FilesRun {
    let root = TestSupport.makeCanonicalTemporaryDirectory(named: directoryName)
    let registry = try MultiTool.Builder()
        .withFiles(root: root, recordsChanges: recordsChanges)
        .addTools(tools)
        .buildRegistry()
    let write = try #require(registry.tools[writeVerbPath] as? Write)
    let run = try await makeStubRun()
    return FilesRun(run: run, registry: registry, root: root, journal: write.context.changes)
}

/// Runs one `runCode` snippet through a new `MultiTool` over `registry`,
/// under `context` when one is given.
///
/// The call goes through `MultiTool.call(arguments:)`, thus through the JSC
/// interpreter, the `tools.*` bindings, and `RunBinding.invoke`, which binds
/// the context around each inner verb call. Passing `nil` for `context` is
/// the no-ambient-context mode: a `MultiTool` constructed and called directly,
/// outside any session.
///
/// - Parameters:
///   - code: the snippet to run.
///   - registry: the catalog the snippet's `tools.*` calls dispatch into.
///   - context: the ambient session context to bind around the call, or `nil`
///     to run with no session at all.
/// - Returns: the rendered `runCode` output, as the model would read it.
/// - Throws: whatever `MultiTool.call(arguments:)` throws.
func runSnippet(
    _ code: String, over registry: MultiTool.Registry, under context: ToolContext? = nil
) async throws -> String {
    try await runSnippet(code, through: MultiTool(registry: registry), under: context)
}

/// Runs one `runCode` snippet through `multiTool`, under `context` when one
/// is given.
///
/// The form for a test whose calls must share ONE `MultiTool`: two calls that
/// run at the same time over it, each under a context of its own, prove that
/// the tool keeps the two runs apart.
///
/// - Parameters:
///   - code: the snippet to run.
///   - multiTool: the tool to call.
///   - context: the ambient session context to bind around the call, or `nil`
///     to run with no session at all.
/// - Returns: the rendered `runCode` output, as the model would read it.
/// - Throws: whatever `MultiTool.call(arguments:)` throws.
func runSnippet(
    _ code: String, through multiTool: MultiTool, under context: ToolContext?
) async throws -> String {
    let arguments = RunCodeArguments(code: code)
    guard let context else {
        return try await multiTool.call(arguments: arguments)
    }
    return try await ToolContext.$current.withValue(context) {
        try await multiTool.call(arguments: arguments)
    }
}

/// The one JavaScript statement that calls `tools.files.write` and binds the
/// result to `written`.
///
/// - Parameters:
///   - fileName: the path of the file to write, as the snippet passes it.
///   - content: the content to write. It stands in a JS template literal,
///     thus a newline in it stands as itself.
/// - Returns: the statement.
func writeVerbCall(writing fileName: String, content: String) -> String {
    "const written = await tools.files.write({ path: \"\(fileName)\", content: `\(content)` });"
}

/// The snippet that writes one file through `tools.files.write` and answers
/// the byte count, or the correction when nothing was written.
///
/// The rendered output of a run of this snippet is the JSON text of
/// `bytesWritten`, or the correction text. Thus a test compares the output to
/// the count it expects, and reads the correction when the two differ.
///
/// - Parameters:
///   - fileName: the path of the file to write, as the snippet passes it.
///   - content: the content to write.
/// - Returns: the snippet.
func writeVerbSnippet(writing fileName: String, content: String) -> String {
    """
    \(writeVerbCall(writing: fileName, content: content))
    if (written.correction) { return written.correction; }
    return written.bytesWritten;
    """
}
