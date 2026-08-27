import Foundation

@testable import FoundationModelsMultitool

// MARK: - The one read of a mounted surface
//
// `help()` answers the fully-qualified path of every entry of the registry the
// running snippet reads, as a JSON array. A suite that asserts what a swap did
// reads the surface that way: it runs the snippet on the tool it holds, and it
// decodes the answer.
//
// The snippet and the decode stand here one time, so a suite of the swap and a
// suite of the refresher read the same surface the same way.

/// The snippet that answers the surface of the sandbox as a list of paths.
let helpSnippet = "return help();"

/// The paths `help()` lists in a snippet run on `runCode`.
///
/// - Parameter runCode: The tool to run the snippet on.
/// - Returns: The paths, in render order.
/// - Throws: What the run or the decode throws.
func helpPaths(of runCode: MultiTool) async throws -> [String] {
    let rendered = try await runCode.call(arguments: RunCodeArguments(code: helpSnippet))
    return try JSONDecoder().decode([String].self, from: Data(rendered.utf8))
}
