import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for `WebAPIKey`: where the key value comes from, and that no string
/// form of a key shows the value.
///
/// Each value here is an obvious test value, not a real key.
@Suite("WebAPIKey")
struct WebAPIKeyTests {
    /// The name of the environment variable that the `.environment` cases read.
    private let variable = "EXAMPLE_SEARCH_API_KEY"

    /// A key value that each string-form test looks for.
    private let secret = "test-secret-value-1234"

    @Test("a literal key resolves to its value in each environment")
    func literalResolvesToItsValue() {
        let key = WebAPIKey.literal(secret)
        #expect(key.resolve(in: [:]) == secret)
        #expect(key.resolve(in: [variable: "other-value"]) == secret)
    }

    @Test("an environment key reads the dictionary at the time of the call")
    func environmentKeyReadsAtCallTime() {
        let key = WebAPIKey.environment(variable)
        #expect(key.resolve(in: [variable: "first-value"]) == "first-value")
        #expect(key.resolve(in: [variable: "second-value"]) == "second-value")
    }

    @Test("an environment key whose variable is missing resolves to nil")
    func missingVariableResolvesToNil() {
        let key = WebAPIKey.environment(variable)
        #expect(key.resolve(in: ["OTHER_VARIABLE": secret]) == nil)
    }

    @Test("an environment key whose variable is empty resolves to nil")
    func emptyVariableResolvesToNil() {
        let key = WebAPIKey.environment(variable)
        #expect(key.resolve(in: [variable: ""]) == nil)
    }

    @Test("an empty literal key resolves to nil")
    func emptyLiteralResolvesToNil() {
        #expect(WebAPIKey.literal("").resolve(in: [:]) == nil)
    }

    @Test("String(describing:) shows no key value", arguments: [true, false])
    func describingShowsNoValue(isLiteral: Bool) {
        let text = String(describing: makeKey(isLiteral: isLiteral))
        #expect(text == "WebAPIKey(<redacted>)")
    }

    @Test("String(reflecting:) shows no key value", arguments: [true, false])
    func reflectingShowsNoValue(isLiteral: Bool) {
        let text = String(reflecting: makeKey(isLiteral: isLiteral))
        #expect(text == "WebAPIKey(<redacted>)")
    }

    @Test("dump shows no key value", arguments: [true, false])
    func dumpShowsNoValue(isLiteral: Bool) {
        let text = WebRedactionProbe.dumped(makeKey(isLiteral: isLiteral))
        #expect(text.contains("<redacted>"))
        #expect(!text.contains(secret))
    }

    @Test("a key inside a provider shows no key value in a string form")
    func providerShowsNoValue() {
        let provider = WebSearchProvider.tavily(.literal(secret))
        #expect(!String(describing: provider).contains(secret))
        #expect(!String(reflecting: provider).contains(secret))
        #expect(!WebRedactionProbe.dumped(provider).contains(secret))
    }

    /// Makes a key of the kind that a parameterized test names. The
    /// `.environment` key holds the name `secret`, thus a string form that
    /// shows the name also fails the test.
    ///
    /// - Parameter isLiteral: `true` for a `.literal` key, and `false` for an
    ///   `.environment` key.
    /// - Returns: The key.
    private func makeKey(isLiteral: Bool) -> WebAPIKey {
        isLiteral ? .literal(secret) : .environment(secret)
    }
}
