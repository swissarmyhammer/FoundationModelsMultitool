// `LiveProviderSetting` — one keyed provider of the live tests, the environment
// variables that configure it, and the condition that enables its live test
// (web.md § "Testing", Level 2).
//
// The user decided on 2026-09-26 that a keyed live test runs only when its
// variable is set, and that the test is skipped when the variable is not set.
// This is a written exception to the review rule
// `test-integrity/test-partitioning`, for the six tests of
// `KeyedProviderLiveTests` only. No other test reads the environment to
// decide if it runs.

import Foundation
import Testing

/// One keyed provider of the live tests, and the environment variables that
/// configure it.
struct LiveProviderSetting: Sendable {
    /// The name of the provider, for example `braveAPI`.
    let name: String

    /// The environment variables that can configure the provider, in the
    /// order that `fromEnvironment()` reads them.
    let variables: [String]

    /// `true` when each variable holds an API key. `false` for `searxng`,
    /// whose variable holds the base URL of an instance and not a key.
    var holdsKey = true

    /// The Brave Search API, with `BRAVE_SEARCH_API_KEY` or the alias
    /// `BRAVE_API_KEY`.
    static let braveAPI = LiveProviderSetting(name: "braveAPI", variables: ["BRAVE_SEARCH_API_KEY", "BRAVE_API_KEY"])

    /// Tavily, with `TAVILY_API_KEY`.
    static let tavily = LiveProviderSetting(name: "tavily", variables: ["TAVILY_API_KEY"])

    /// Exa, with `EXA_API_KEY`.
    static let exa = LiveProviderSetting(name: "exa", variables: ["EXA_API_KEY"])

    /// Serper, with `SERPER_API_KEY`.
    static let serper = LiveProviderSetting(name: "serper", variables: ["SERPER_API_KEY"])

    /// Kagi, with `KAGI_API_KEY`.
    static let kagi = LiveProviderSetting(name: "kagi", variables: ["KAGI_API_KEY"])

    /// A SearXNG instance, with its base URL in `SEARXNG_URL`.
    static let searxng = LiveProviderSetting(name: "searxng", variables: ["SEARXNG_URL"], holdsKey: false)

    /// The six keyed providers, in the order of `fromEnvironment()`.
    static let all = [braveAPI, tavily, exa, serper, kagi, searxng]

    /// The comment of the skip when no variable of the provider is set. It
    /// names each variable.
    var notSetComment: Comment {
        Comment(rawValue: "\(variableNames) is not set")
    }

    /// The comment of the failure when a variable is set but
    /// `fromEnvironment()` does not have the provider. It names each
    /// variable.
    var notConfiguredComment: Comment {
        Comment(
            rawValue: "\(variableNames) is set, but fromEnvironment() does not have \(name): "
                + "the value is not correct for the provider")
    }

    /// The variables, joined with `or`, for a comment.
    private var variableNames: String {
        variables.joined(separator: " or ")
    }

    /// Tells if the environment sets a variable of the provider.
    ///
    /// - Parameter environment: The environment dictionary to read.
    /// - Returns: `true` when a variable is set and not empty. An empty
    ///   variable is not set, the same as in `fromEnvironment()`.
    func isSet(in environment: [String: String]) -> Bool {
        !setValues(in: environment).isEmpty
    }

    /// The key values that the environment holds for the provider.
    ///
    /// - Parameter environment: The environment of the test run.
    /// - Returns: The value of each variable that is set and not empty, or no
    ///   value when the variables hold no key.
    func keyValues(in environment: [String: String]) -> [String] {
        holdsKey ? setValues(in: environment) : []
    }

    /// The value of each variable that is set and not empty.
    ///
    /// - Parameter environment: The environment dictionary to read.
    /// - Returns: The values, in the order of ``variables``.
    private func setValues(in environment: [String: String]) -> [String] {
        variables.compactMap { environment[$0] }.filter { !$0.isEmpty }
    }
}

extension LiveProviderSetting: CustomTestStringConvertible {
    /// The name of the provider, as the name of a test argument.
    var testDescription: String { name }
}

extension Trait where Self == ConditionTrait {
    /// Enables a keyed live test only when the environment sets a variable of
    /// its provider. When no variable is set, the test is skipped with
    /// ``LiveProviderSetting/notSetComment``.
    ///
    /// This is the user's written exception to
    /// `test-integrity/test-partitioning` (2026-09-26), for the six tests of
    /// `KeyedProviderLiveTests` only.
    ///
    /// - Parameters:
    ///   - setting: The provider and its environment variables.
    ///   - environment: The environment dictionary to read. The default is
    ///     the environment of the test run. A check gives its own dictionary.
    /// - Returns: The condition trait.
    static func enabled(
        whenSet setting: LiveProviderSetting,
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        .enabled(if: setting.isSet(in: environment), setting.notSetComment)
    }
}
