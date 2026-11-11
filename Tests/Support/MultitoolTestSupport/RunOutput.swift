// `RunOutput` — the one way a test reads the JSON value that a `runCode`
// snippet returned.
//
// A snippet that returns an object or an array gives its JSON text as the
// rendered output. A suite decodes that text into a value type of its own, and
// then compares fields. `RunOutput.decoded(_:from:)` is that decode, written
// one time here rather than once for each suite. The unit test target and the
// live web suites of `IntegrationTests/` both read it, thus it stands in the
// `MultitoolTestSupport` product and not in one test target.
//
// The file does not import `Testing`. A failed decode throws an error that
// names the output, and the test runner records that error. Thus the
// `MultitoolTestSupport` product links no test framework, and an executable
// such as `GitNoProgramProbe` can link the product and run outside a test
// bundle.

import Foundation

/// The error of a failed decode of a `runCode` output. Its description names
/// the type and the raw output, thus the failure says what came back.
struct RunOutputDecodingError: Error, CustomStringConvertible {

    /// The name of the value type that the decode expected.
    let typeName: String

    /// The rendered run output that did not decode.
    let output: String

    /// The error of the JSON decoder.
    let underlying: any Error

    /// The type, the raw output, and the decoder error.
    var description: String {
        "the output did not decode as \(typeName): \(output) (\(underlying))"
    }
}

/// Reads the rendered output of a `runCode` snippet.
enum RunOutput {
    /// Decodes the JSON value that one run returned.
    ///
    /// - Parameters:
    ///   - type: The value type to decode.
    ///   - output: The rendered run output.
    /// - Returns: The decoded value.
    /// - Throws: ``RunOutputDecodingError`` when `output` is not the JSON text
    ///   of `type`. The error names the raw output, thus the failure names
    ///   what came back.
    static func decoded<Value: Decodable>(_ type: Value.Type, from output: String) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: Data(output.utf8))
        } catch {
            throw RunOutputDecodingError(typeName: "\(type)", output: output, underlying: error)
        }
    }
}
