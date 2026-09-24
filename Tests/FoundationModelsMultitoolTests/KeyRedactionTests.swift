import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for `KeyRedaction.redactingKeys(_:keys:)`: each occurrence of each
/// key value in a text becomes `<redacted>`.
///
/// Each value here is an obvious test value, not a real key.
@Suite("KeyRedaction")
struct KeyRedactionTests {
    @Test("a key in a provider error text becomes <redacted>")
    func keyBecomesRedacted() {
        let text = "401 Unauthorized: the key test-key-1234 is not valid"
        let redacted = KeyRedaction.redactingKeys(text, keys: ["test-key-1234"])
        #expect(redacted == "401 Unauthorized: the key <redacted> is not valid")
    }

    @Test("each occurrence of a key is redacted")
    func eachOccurrenceIsRedacted() {
        let text = "test-key-1234, then test-key-1234 again"
        let redacted = KeyRedaction.redactingKeys(text, keys: ["test-key-1234"])
        #expect(redacted == "<redacted>, then <redacted> again")
    }

    @Test("each key of the list is redacted")
    func eachKeyIsRedacted() {
        let text = "first test-key-one, second test-key-two"
        let redacted = KeyRedaction.redactingKeys(text, keys: ["test-key-one", "test-key-two"])
        #expect(redacted == "first <redacted>, second <redacted>")
    }

    @Test("a key that contains a shorter key is removed whole")
    func longerKeyIsRemovedWhole() {
        let text = "echo: test-key-1234-extended"
        let redacted = KeyRedaction.redactingKeys(
            text, keys: ["test-key-1234", "test-key-1234-extended"])
        #expect(redacted == "echo: <redacted>")
    }

    @Test("an empty key changes nothing")
    func emptyKeyChangesNothing() {
        let text = "no key here"
        #expect(KeyRedaction.redactingKeys(text, keys: [""]) == text)
    }

    @Test("an empty key list changes nothing")
    func emptyKeyListChangesNothing() {
        let text = "the key test-key-1234 stays"
        #expect(KeyRedaction.redactingKeys(text, keys: []) == text)
    }
}
