// `EnvironmentVariablesTests` — the behavioral suite of the
// `tools.environment.variables` verb.
//
// The suite makes `VariablesArguments` with the memberwise initializer and
// calls the `Variables` verb directly, the way `GitBranchesTests` calls its
// verb. Each test injects its own variables through an `EnvironmentContext`.
// No test reads the real environment of the process, thus the results do not
// change from one machine to a different machine.

import Foundation
import Synchronization
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the `tools.environment.variables` verb (task
/// `^9p3e1nh`).
///
/// The card names each case: all variables, `name`, `prefix`, an unset name,
/// the two arguments together, and a live read.
@Suite("EnvironmentVariablesTests")
struct EnvironmentVariablesTests {

    /// The injected variables. The values include a space, an equals sign,
    /// an empty value, and text that is not ASCII, thus a test can see if the
    /// verb changes a value.
    private static let injected = [
        "PATH": "/usr/bin:/bin",
        "HOME": "/Users/someone",
        "APP_MODE": "debug mode",
        "APP_FLAGS": "a=b",
        "APP_EMPTY": "",
        "GREETING": "grüß dich",
    ]

    /// The prefix that three of the injected names start with.
    private static let appPrefix = "APP_"

    /// A name that no injected variable has.
    private static let unsetName = "NOT_SET_ANYWHERE"

    // MARK: - No argument

    /// With no argument, the verb gives each variable in name order, and each
    /// value as it is.
    @Test("with no argument, the verb gives each variable in name order")
    func withNoArgumentTheVerbGivesEachVariableInNameOrder() async throws {
        let result = try await Self.variables(VariablesArguments(name: nil, prefix: nil))

        #expect(result.correction == nil)
        #expect(
            Self.pairs(of: result) == [
                Self.Pair(name: "APP_EMPTY", value: ""),
                Self.Pair(name: "APP_FLAGS", value: "a=b"),
                Self.Pair(name: "APP_MODE", value: "debug mode"),
                Self.Pair(name: "GREETING", value: "grüß dich"),
                Self.Pair(name: "HOME", value: "/Users/someone"),
                Self.Pair(name: "PATH", value: "/usr/bin:/bin"),
            ])
    }

    /// With no variable set, the verb gives an empty list, and no correction.
    @Test("with no variable set, the verb gives an empty list")
    func withNoVariableSetTheVerbGivesAnEmptyList() async throws {
        let result = try await Self.variables(VariablesArguments(name: nil, prefix: nil), from: [:])

        #expect(result.correction == nil)
        #expect(result.variables.isEmpty)
    }

    // MARK: - name

    /// A `name` that is set gives only that variable.
    @Test("a name that is set gives only that variable")
    func aNameThatIsSetGivesOnlyThatVariable() async throws {
        let result = try await Self.variables(VariablesArguments(name: "APP_MODE", prefix: nil))

        #expect(result.correction == nil)
        #expect(Self.pairs(of: result) == [Self.Pair(name: "APP_MODE", value: "debug mode")])
    }

    /// A `name` whose value is empty is set, thus the verb gives it with its
    /// empty value.
    @Test("a name with an empty value is set")
    func aNameWithAnEmptyValueIsSet() async throws {
        let result = try await Self.variables(VariablesArguments(name: "APP_EMPTY", prefix: nil))

        #expect(result.correction == nil)
        #expect(Self.pairs(of: result) == [Self.Pair(name: "APP_EMPTY", value: "")])
    }

    /// A `name` that is not set gives no variable, and a correction that
    /// names the variable. The verb does not throw.
    @Test("a name that is not set gives a correction")
    func aNameThatIsNotSetGivesACorrection() async throws {
        let result = try await Self.variables(VariablesArguments(name: Self.unsetName, prefix: nil))

        #expect(result.variables.isEmpty)
        let correction = try #require(result.correction)
        #expect(correction.contains(Self.unsetName), "correction was: \(correction)")
    }

    /// The names of environment variables are case-sensitive on macOS. Thus
    /// `path` does not find `PATH`.
    @Test("a name matches with the same case only")
    func aNameMatchesWithTheSameCaseOnly() async throws {
        let result = try await Self.variables(VariablesArguments(name: "path", prefix: nil))

        #expect(result.variables.isEmpty)
        #expect(result.correction != nil)
    }

    // MARK: - prefix

    /// A `prefix` gives each variable whose name starts with it, in name
    /// order.
    @Test("a prefix gives each variable whose name starts with it, in name order")
    func aPrefixGivesEachMatchingVariableInNameOrder() async throws {
        let result = try await Self.variables(VariablesArguments(name: nil, prefix: Self.appPrefix))

        #expect(result.correction == nil)
        #expect(
            Self.pairs(of: result) == [
                Self.Pair(name: "APP_EMPTY", value: ""),
                Self.Pair(name: "APP_FLAGS", value: "a=b"),
                Self.Pair(name: "APP_MODE", value: "debug mode"),
            ])
    }

    /// A `prefix` that no name starts with gives an empty list, and no
    /// correction: no match is a fact, not a mistake of the model.
    @Test("a prefix with no match gives an empty list")
    func aPrefixWithNoMatchGivesAnEmptyList() async throws {
        let result = try await Self.variables(VariablesArguments(name: nil, prefix: "ZZZ_"))

        #expect(result.correction == nil)
        #expect(result.variables.isEmpty)
    }

    /// A `prefix` matches with the same case only, as a name does.
    @Test("a prefix matches with the same case only")
    func aPrefixMatchesWithTheSameCaseOnly() async throws {
        let result = try await Self.variables(VariablesArguments(name: nil, prefix: "app_"))

        #expect(result.variables.isEmpty)
    }

    // MARK: - name and prefix

    /// `name` and `prefix` together give a correction and no variable. The
    /// verb does not throw.
    @Test("name and prefix together give a correction")
    func nameAndPrefixTogetherGiveACorrection() async throws {
        let result = try await Self.variables(VariablesArguments(name: "APP_MODE", prefix: Self.appPrefix))

        #expect(result.variables.isEmpty)
        #expect(result.correction != nil)
    }

    // MARK: - Live read

    /// The verb reads the variables at each call. A change between two calls
    /// shows in the second result.
    @Test("a change to the variables between two calls shows in the second call")
    func aChangeBetweenTwoCallsShowsInTheSecondCall() async throws {
        let store = Mutex(["FIRST": "1"])
        let verb = Variables(context: EnvironmentContext(variables: { store.withLock { $0 } }))
        let allArguments = VariablesArguments(name: nil, prefix: nil)

        let before = try await verb.call(arguments: allArguments)
        store.withLock { $0["SECOND"] = "2" }
        let after = try await verb.call(arguments: allArguments)

        #expect(Self.pairs(of: before) == [Self.Pair(name: "FIRST", value: "1")])
        #expect(Self.pairs(of: after) == [Self.Pair(name: "FIRST", value: "1"), Self.Pair(name: "SECOND", value: "2")])
    }

    // MARK: - Helpers

    /// One name and its value, in a form that `#expect` compares.
    private struct Pair: Equatable {
        /// The name of the variable.
        let name: String

        /// The value of the variable.
        let value: String
    }

    /// Calls the `tools.environment.variables` verb over injected variables.
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the call.
    ///   - variables: The variables the context gives. Defaults to
    ///     ``injected``.
    /// - Returns: The result of the verb.
    private static func variables(
        _ arguments: VariablesArguments, from variables: [String: String] = injected
    ) async throws -> VariablesResult {
        try await Variables(context: EnvironmentContext(variables: { variables })).call(arguments: arguments)
    }

    /// The variables of a result, as pairs in result order.
    ///
    /// - Parameter result: The result of the verb.
    /// - Returns: One pair for each variable.
    private static func pairs(of result: VariablesResult) -> [Pair] {
        result.variables.map { Pair(name: $0.name, value: $0.value) }
    }
}
