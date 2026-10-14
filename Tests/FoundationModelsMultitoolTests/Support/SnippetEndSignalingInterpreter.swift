// `SnippetEndSignalingInterpreter` — a `JSCInterpreter` that tells a test
// when the code of a `runCode` snippet ended.
//
// `MultiTool` marks the end of the snippet code with the host function
// `MultiTool.snippetEndHostName` (see `SnippetEndMark`). An inner call that
// ends after that mark is a call that the snippet did not await. A test that
// must make a call end after the snippet code ended opens the gate of that
// call here, at the mark, and needs no sleep.

@testable import FoundationModelsMultitool

/// A `JSCInterpreter` that opens a gate each time the code of a snippet ends.
///
/// It wraps the host function ``MultiTool/snippetEndHostName``: the wrapper
/// first calls the host function of `MultiTool`, thus the mark is set, and then
/// opens ``snippetEnded``. A call that waits on ``snippetEnded`` thus always
/// ends after the mark. Each other host function goes to `JSCInterpreter`
/// unchanged.
struct SnippetEndSignalingInterpreter: Interpreter {
    /// The interpreter that runs each snippet.
    private let wrapped = JSCInterpreter()

    /// The gate that opens when the code of the first snippet ends. A nested
    /// `tools.runCode` snippet ends before its outer snippet, thus a nested
    /// run opens the gate first.
    let snippetEnded: TestGate

    /// Makes an interpreter that opens `snippetEnded` at the end of the
    /// snippet code.
    ///
    /// - Parameter snippetEnded: The gate to open.
    init(opening snippetEnded: TestGate) {
        self.snippetEnded = snippetEnded
    }

    /// Runs `code` on `JSCInterpreter`, with the snippet end host function
    /// wrapped so that it opens ``snippetEnded``.
    ///
    /// - Parameters:
    ///   - code: The JavaScript source to run.
    ///   - installing: The synchronous host functions of the run.
    ///   - installingAsync: The asynchronous host functions of the run.
    /// - Returns: The result of `JSCInterpreter`.
    /// - Throws: What `JSCInterpreter` throws.
    func run(
        code: String,
        installing: [HostFunction],
        installingAsync: [AsyncHostFunction]
    ) async throws -> InterpreterResult {
        let snippetEnded = snippetEnded
        let signaling = installing.map { function -> HostFunction in
            guard function.name == MultiTool.snippetEndHostName else { return function }
            return HostFunction(name: function.name) { arguments in
                let value = try function.call(arguments)
                snippetEnded.open()
                return value
            }
        }
        return try await wrapped.run(code: code, installing: signaling, installingAsync: installingAsync)
    }

    /// Checks the syntax of `code` on `JSCInterpreter`.
    ///
    /// - Parameter code: The JavaScript source to parse.
    /// - Throws: What `JSCInterpreter` throws.
    func checkSyntax(of code: String) throws {
        try wrapped.checkSyntax(of: code)
    }
}
