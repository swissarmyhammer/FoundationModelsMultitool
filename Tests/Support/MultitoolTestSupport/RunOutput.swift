// `RunOutput` — the one way a test reads the JSON value that a `runCode`
// snippet returned.
//
// A snippet that returns an object or an array gives its JSON text as the
// rendered output. A suite decodes that text into a value type of its own, and
// then compares fields. `RunOutput.decoded(_:from:)` is that decode, written
// one time here rather than once for each suite. The unit test target and the
// live web suites of `IntegrationTests/` both read it, thus it stands in the
// `MultitoolTestSupport` product and not in one test target.

import Foundation
import Testing

/// Reads the rendered output of a `runCode` snippet.
enum RunOutput {
    /// Decodes the JSON value that one run returned.
    ///
    /// - Parameters:
    ///   - type: The value type to decode.
    ///   - output: The rendered run output.
    /// - Returns: The decoded value.
    /// - Throws: When `output` is not the JSON text of `type`. The raw output
    ///   is recorded first, thus the failure names what came back.
    static func decoded<Value: Decodable>(_ type: Value.Type, from output: String) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: Data(output.utf8))
        } catch {
            Issue.record("the output did not decode as \(type): \(output)")
            throw error
        }
    }
}
