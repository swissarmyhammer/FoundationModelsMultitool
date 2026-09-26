import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The offline checks of ``LiveProviderSetting``: the condition that enables
/// each test of `KeyedProviderLiveTests` (web.md § "Testing", Level 2).
///
/// Each check gives an environment dictionary to the setting. No check reads
/// the environment of the test run, and no check sends a request. Thus each
/// check always runs, and it needs no real key.
@Suite("LiveProviderSetting: a keyed live test runs only when its variable is set")
struct LiveProviderSettingTests {
    /// A value that is not a real key. The checks only need a value that is
    /// not empty.
    private static let placeholderKey = "placeholder-key"

    /// A base URL that `fromEnvironment()` accepts for `SEARXNG_URL`.
    private static let placeholderBaseURL = "https://searxng.example"

    /// An environment that sets each variable of a setting to a placeholder.
    ///
    /// - Parameter setting: The provider and its environment variables.
    /// - Returns: The environment dictionary.
    private static func environment(setting: LiveProviderSetting) -> [String: String] {
        let value = setting.holdsKey ? placeholderKey : placeholderBaseURL
        return Dictionary(uniqueKeysWithValues: setting.variables.map { ($0, value) })
    }

    @Test("The condition is true when a variable of the provider is set", arguments: LiveProviderSetting.all)
    func conditionIsTrueWhenSet(setting: LiveProviderSetting) async throws {
        let trait = ConditionTrait.enabled(whenSet: setting, in: Self.environment(setting: setting))
        #expect(try await trait.evaluate())
    }

    @Test("The condition is false when no variable of the provider is set", arguments: LiveProviderSetting.all)
    func conditionIsFalseWhenNotSet(setting: LiveProviderSetting) async throws {
        let trait = ConditionTrait.enabled(whenSet: setting, in: [:])
        #expect(try await trait.evaluate() == false)
    }

    @Test("An empty variable is not set", arguments: LiveProviderSetting.all)
    func emptyVariableIsNotSet(setting: LiveProviderSetting) {
        let environment = Dictionary(uniqueKeysWithValues: setting.variables.map { ($0, "") })
        #expect(setting.isSet(in: environment) == false)
    }

    @Test("BRAVE_API_KEY alone sets braveAPI")
    func braveAliasSetsBraveAPI() {
        #expect(LiveProviderSetting.braveAPI.isSet(in: ["BRAVE_API_KEY": Self.placeholderKey]))
    }

    @Test("A variable of another provider does not set the provider")
    func otherVariableDoesNotSet() {
        #expect(LiveProviderSetting.tavily.isSet(in: ["EXA_API_KEY": Self.placeholderKey]) == false)
    }

    @Test("When the variables are set, fromEnvironment() has the provider", arguments: LiveProviderSetting.all)
    func fromEnvironmentAgrees(setting: LiveProviderSetting) {
        let environment = Self.environment(setting: setting)
        let names = WebConfiguration.fromEnvironment(environment).providers.map(\.name)
        #expect(setting.isSet(in: environment))
        #expect(names.contains(setting.name), "fromEnvironment() gave \(names)")
    }

    @Test("The skip comment names each variable", arguments: LiveProviderSetting.all)
    func skipCommentNamesEachVariable(setting: LiveProviderSetting) {
        for variable in setting.variables {
            #expect(setting.notSetComment.rawValue.contains(variable))
        }
    }

    @Test("There is one setting for each of the six keyed providers")
    func settingsCoverEachKeyedProvider() {
        #expect(
            LiveProviderSetting.all.map(\.name) == ["braveAPI", "tavily", "exa", "serper", "kagi", "searxng"])
    }
}
