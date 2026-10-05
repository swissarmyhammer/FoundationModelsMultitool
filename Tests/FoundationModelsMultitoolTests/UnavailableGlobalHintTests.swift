import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Holds the repair hint for a snippet that uses a Node.js or browser global
/// that the `runCode` sandbox does not have.
///
/// **Why this suite exists.** In a SWE-bench run the model wrote snippets that
/// used `Buffer`. JavaScriptCore answers `ReferenceError: Can't find variable:
/// Buffer`, which tells the model nothing about what to write instead.
@Suite("UnavailableGlobalHintTests")
struct UnavailableGlobalHintTests {

    /// The snippet of the SWE-bench run: base64 through `Buffer`.
    private static let bufferSnippet = "return Buffer.from('abc').toString('base64');"

    /// A global name that no table row holds, because it is the snippet's own
    /// name and not a Node.js or browser global.
    private static let snippetOwnName = "myOwnHelper"

    /// Builds a `MultiTool` over a one-tool catalog.
    ///
    /// - Returns: the tool.
    /// - Throws: whatever `MultiTool.Builder.buildRegistry()` throws.
    private static func makeMultiTool() throws -> MultiTool {
        MultiTool(registry: try MultiTool.Builder().addTool(CitiesTool()).buildRegistry())
    }

    @Test("a snippet that uses Buffer gets a hint that says Buffer is not available")
    func bufferSnippetGetsTheHint() async throws {
        let output = try await Self.makeMultiTool().call(arguments: RunCodeArguments(code: Self.bufferSnippet))
        let hint = try #require(UnavailableGlobalHint.hint(message: "ReferenceError: Can't find variable: Buffer"))

        #expect(output.contains("Can't find variable: Buffer"), "output was: \(output)")
        #expect(output.contains(hint), "output was: \(output)")
        #expect(hint.hasPrefix("Buffer \(UnavailableGlobalHint.unavailablePhrase)"), "hint was: \(hint)")
        #expect(output.contains(RepairDirective.repairSnippet.closingLine))
    }

    @Test("a missing name that is no Node.js or browser global gets no hint")
    func snippetOwnMissingNameGetsNoHint() {
        let message = "ReferenceError: Can't find variable: \(Self.snippetOwnName)"

        #expect(UnavailableGlobalHint.hint(message: message) == nil)
    }

    @Test("a message that is not a missing-variable error gets no hint")
    func otherErrorGetsNoHint() {
        #expect(UnavailableGlobalHint.hint(message: "TypeError: Buffer.from is not a function") == nil)
    }

    @Test("every name the hint table holds is really undefined in the runCode sandbox")
    func everyTableNameIsUndefinedInTheSandbox() async throws {
        let names = UnavailableGlobalHint.globalNames.sorted()
        let quoted = names.map { "\"\($0)\"" }.joined(separator: ", ")
        let code = "return [\(quoted)].filter(name => typeof globalThis[name] !== 'undefined');"

        let output = try await Self.makeMultiTool().call(arguments: RunCodeArguments(code: code))

        #expect(!names.isEmpty)
        #expect(try RunOutput.decoded([String].self, from: output) == [])
    }
}
