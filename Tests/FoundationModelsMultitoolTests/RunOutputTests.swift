// `RunOutputTests` — the failure of `RunOutput.decoded(_:from:)` names the
// output that came back.

import Foundation
import Testing

@testable import MultitoolTestSupport

/// Tests for the decode of a `runCode` output.
@Suite("RunOutputTests")
struct RunOutputTests {

    /// A value type that the tests decode.
    private struct Pair: Decodable, Equatable {

        /// The one field of the value.
        let left: Int
    }

    /// An output that is not the JSON text of the type.
    private static let badOutput = "not json at all"

    /// A JSON output decodes into the value.
    @Test("a JSON output decodes into the value")
    func aJSONOutputDecodesIntoTheValue() throws {
        #expect(try RunOutput.decoded(Pair.self, from: #"{"left": 3}"#) == Pair(left: 3))
    }

    /// A bad output throws an error whose description names the output,
    /// thus the failure of the test says what came back.
    @Test("a bad output throws an error that names the output")
    func aBadOutputThrowsAnErrorThatNamesTheOutput() throws {
        let error = try #require(throws: RunOutputDecodingError.self) {
            try RunOutput.decoded(Pair.self, from: Self.badOutput)
        }
        #expect(error.description.contains(Self.badOutput), "description was: \(error.description)")
    }
}
