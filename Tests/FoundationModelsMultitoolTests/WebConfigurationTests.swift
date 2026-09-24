import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for `WebConfiguration`: the provider order that
/// `fromEnvironment(_:)` makes from a given dictionary, the `.keyless`
/// configuration, and that no string form of a configuration shows a key
/// value.
///
/// Each value here is an obvious test value, not a real key.
@Suite("WebConfiguration")
struct WebConfigurationTests {
    /// The base URL of a SearXNG instance that the tests give.
    private let searxngBase = "http://localhost:8888"

    /// An environment that sets each variable that `fromEnvironment(_:)` reads.
    private var fullEnvironment: [String: String] {
        [
            "BRAVE_SEARCH_API_KEY": "test-brave-search",
            "BRAVE_API_KEY": "test-brave-alias",
            "TAVILY_API_KEY": "test-tavily",
            "EXA_API_KEY": "test-exa",
            "SERPER_API_KEY": "test-serper",
            "KAGI_API_KEY": "test-kagi",
            "SEARXNG_URL": searxngBase,
        ]
    }

    @Test("each set variable adds its provider in the documented order")
    func fullEnvironmentGivesTheDocumentedOrder() throws {
        let configuration = WebConfiguration.fromEnvironment(fullEnvironment)
        let expected: [WebSearchProvider] = [
            .braveAPI(.environment("BRAVE_SEARCH_API_KEY")),
            .tavily(.environment("TAVILY_API_KEY")),
            .exa(.environment("EXA_API_KEY")),
            .serper(.environment("SERPER_API_KEY")),
            .kagi(.environment("KAGI_API_KEY")),
            .searxng(try #require(URL(string: searxngBase))),
            .braveHTML,
            .duckDuckGoHTML,
        ]
        #expect(configuration.providers == expected)
    }

    @Test("the provider names follow the documented order")
    func providerNamesFollowTheOrder() {
        let names = WebConfiguration.fromEnvironment(fullEnvironment).providers.map(\.name)
        #expect(
            names == [
                "braveAPI", "tavily", "exa", "serper", "kagi", "searxng", "braveHTML",
                "duckDuckGoHTML",
            ])
    }

    @Test("an empty environment gives only the keyless fallback")
    func emptyEnvironmentGivesTheKeylessFallback() {
        let configuration = WebConfiguration.fromEnvironment([:])
        #expect(configuration.providers == [.braveHTML, .duckDuckGoHTML])
    }

    @Test("the keyless providers come last after one keyed provider")
    func keylessFallbackComesLast() {
        let configuration = WebConfiguration.fromEnvironment(["EXA_API_KEY": "test-exa"])
        #expect(
            configuration.providers == [.exa(.environment("EXA_API_KEY")), .braveHTML, .duckDuckGoHTML])
    }

    @Test("BRAVE_SEARCH_API_KEY wins over the BRAVE_API_KEY alias")
    func primaryBraveVariableWins() {
        let configuration = WebConfiguration.fromEnvironment([
            "BRAVE_SEARCH_API_KEY": "test-brave-search", "BRAVE_API_KEY": "test-brave-alias",
        ])
        #expect(configuration.providers.first == .braveAPI(.environment("BRAVE_SEARCH_API_KEY")))
    }

    @Test("the BRAVE_API_KEY alias applies when BRAVE_SEARCH_API_KEY is not set")
    func braveAliasAppliesAlone() {
        let configuration = WebConfiguration.fromEnvironment(["BRAVE_API_KEY": "test-brave-alias"])
        #expect(configuration.providers.first == .braveAPI(.environment("BRAVE_API_KEY")))
    }

    @Test("the BRAVE_API_KEY alias applies when BRAVE_SEARCH_API_KEY is empty")
    func braveAliasAppliesOverAnEmptyPrimary() {
        let configuration = WebConfiguration.fromEnvironment([
            "BRAVE_SEARCH_API_KEY": "", "BRAVE_API_KEY": "test-brave-alias",
        ])
        #expect(configuration.providers.first == .braveAPI(.environment("BRAVE_API_KEY")))
    }

    @Test("an empty key variable adds no provider")
    func emptyVariableAddsNoProvider() {
        let configuration = WebConfiguration.fromEnvironment(["TAVILY_API_KEY": ""])
        #expect(configuration.providers == [.braveHTML, .duckDuckGoHTML])
    }

    @Test("a keyed provider holds the variable name, and resolves the value at call time")
    func keyedProviderResolvesAtCallTime() throws {
        let configuration = WebConfiguration.fromEnvironment(["KAGI_API_KEY": "test-kagi"])
        let kagiKey: WebAPIKey? = {
            if case .kagi(let key) = configuration.providers.first { key } else { nil }
        }()
        let key = try #require(kagiKey)
        #expect(key == .environment("KAGI_API_KEY"))
        #expect(key.resolve(in: configuration.environment) == "test-kagi")
    }

    @Test("SEARXNG_URL adds a searxng provider with that base URL")
    func searxngURLAddsAProvider() throws {
        let configuration = WebConfiguration.fromEnvironment(["SEARXNG_URL": searxngBase])
        let base = try #require(URL(string: searxngBase))
        #expect(configuration.providers == [.searxng(base), .braveHTML, .duckDuckGoHTML])
    }

    @Test("a SEARXNG_URL with an upper-case scheme adds a searxng provider")
    func upperCaseSearxngSchemeAddsAProvider() throws {
        let value = "HTTPS://search.example.com"
        let configuration = WebConfiguration.fromEnvironment(["SEARXNG_URL": value])
        let base = try #require(URL(string: value))
        #expect(configuration.providers == [.searxng(base), .braveHTML, .duckDuckGoHTML])
    }

    @Test("a SEARXNG_URL that is not an http or https URL adds no provider", arguments: [
        "", "not a url", "ftp://localhost:8888", "localhost:8888",
    ])
    func invalidSearxngURLAddsNoProvider(value: String) {
        let configuration = WebConfiguration.fromEnvironment(["SEARXNG_URL": value])
        #expect(configuration.providers == [.braveHTML, .duckDuckGoHTML])
    }

    @Test("fromEnvironment keeps the given dictionary for call-time key reads")
    func fromEnvironmentKeepsTheDictionary() {
        let configuration = WebConfiguration.fromEnvironment(fullEnvironment)
        #expect(configuration.environment == fullEnvironment)
    }

    @Test("keyless has the two keyless providers and reads no environment")
    func keylessReadsNoEnvironment() {
        let configuration = WebConfiguration.keyless
        #expect(configuration.providers == [.braveHTML, .duckDuckGoHTML])
        #expect(configuration.environment.isEmpty)
    }

    @Test("the fetch policy has the documented defaults")
    func fetchPolicyDefaults() {
        let policy = WebConfiguration.keyless.fetch
        #expect(policy.maxBytes == 5 * 1024 * 1024)
        #expect(policy.maxRedirects == 10)
        #expect(policy.searchTimeout == 10)
        #expect(policy.defaultFetchTimeout == 30)
        #expect(policy.userAgent.contains("FoundationModelsMultitool"))
    }

    @Test("no string form of a configuration shows a key value")
    func stringFormsShowNoKeyValue() {
        var configuration = WebConfiguration.fromEnvironment(fullEnvironment)
        configuration.providers.insert(.serper(.literal("test-literal-key")), at: 0)
        let forms = [
            String(describing: configuration),
            String(reflecting: configuration),
            WebRedactionProbe.dumped(configuration),
        ]
        let values = fullEnvironment.values.filter { $0 != searxngBase } + ["test-literal-key"]
        for form in forms {
            for value in values {
                #expect(!form.contains(value), "a string form shows \(value): \(form)")
            }
        }
    }

    @Test("the string form of a configuration names each provider")
    func descriptionNamesEachProvider() {
        let text = String(describing: WebConfiguration.fromEnvironment(fullEnvironment))
        for name in ["braveAPI", "tavily", "exa", "serper", "kagi", "searxng", "braveHTML"] {
            #expect(text.contains(name))
        }
    }
}
