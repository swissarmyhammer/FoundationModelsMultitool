import Foundation
import Testing
import os

@testable import FoundationModelsMultitool

/// Proves that `MultiTool` runs each snippet in the interpreter that the
/// caller injects, as it is.
///
/// `Interpreter` has no clock-arming requirement. The one outer timeout of a
/// `runCode` call is the tool-level timeout (`MultiTool.timeout(from:)`), thus
/// `MultiTool.init` does not change or copy the injected interpreter.
@Suite("MultiTool runs the injected interpreter")
struct InjectedInterpreterTests {
    /// An `Interpreter` that records the code of each run and executes none of
    /// it.
    ///
    /// It has only the two requirements that run or parse a snippet, thus it
    /// compiles only while the protocol has no other requirement.
    private final class RecordingInterpreter: Interpreter {
        /// The code of each run, in call order.
        private let recordedCode = OSAllocatedUnfairLock<[String]>(initialState: [])

        /// The code of each run that this interpreter received, in call order.
        var receivedCode: [String] {
            recordedCode.withLock { $0 }
        }

        /// Records `code` and gives a run with no return value and no console
        /// output.
        ///
        /// - Parameters:
        ///   - code: the JavaScript source to record.
        ///   - installing: not used.
        ///   - installingAsync: not used.
        /// - Returns: a result whose return value is `null`.
        func run(
            code: String,
            installing: [HostFunction],
            installingAsync: [AsyncHostFunction]
        ) async throws -> InterpreterResult {
            recordedCode.withLock { $0.append(code) }
            return InterpreterResult(returnValue: .null, consoleLines: [])
        }

        /// Accepts all code, because this interpreter parses nothing.
        ///
        /// - Parameter code: not used.
        func checkSyntax(of code: String) throws {}
    }

    /// A snippet that only this test sends, thus the recorded code can only
    /// contain it when the injected instance ran it.
    private static let snippet = "return 'sent to the injected interpreter';"

    @Test("MultiTool.call runs the snippet in the injected interpreter instance")
    func callRunsTheSnippetInTheInjectedInterpreter() async throws {
        let interpreter = RecordingInterpreter()
        let multiTool = MultiTool(registry: try MultiTool.Builder().buildRegistry(), interpreter: interpreter)

        _ = try await multiTool.call(arguments: RunCodeArguments(code: Self.snippet))

        let received = try #require(interpreter.receivedCode.first)
        #expect(interpreter.receivedCode.count == 1)
        #expect(received.contains(Self.snippet))
    }
}
