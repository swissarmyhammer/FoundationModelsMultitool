import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// One snippet that calls each verb of the environment capability, through a
/// real `MultiTool` and with no model (task `^pykbc2k`).
///
/// The registry comes from `MultiTool.Builder().withEnvironment(context:)`
/// over ``InjectedEnvironment``. The snippet goes through
/// `MultiTool.call(arguments:)`: the JSC interpreter, the
/// `tools.environment` bindings, and `ToolInvoker`. Each input is injected,
/// thus the test reads no real variable, no real host, and no real clock.
@Suite("EnvironmentGoalSnippetTests")
struct EnvironmentGoalSnippetTests {

    /// The time zone that the snippet gives to `tools.environment.now`.
    private static let snippetTimeZone = "UTC"

    /// The key of the correction in the object that the snippet returns.
    private static let correctionKey = "correction"

    /// The key of the result of `vars.correction === null` in the object
    /// that the snippet returns.
    private static let correctionIsNullKey = "correctionIsNull"

    /// The snippet: each verb one time, and the fields that the test reads.
    private static let goalSnippet = """
        const vars = await tools.environment.variables({ prefix: "\(InjectedEnvironment.applicationPrefix)" });
        const os = await tools.environment.os({});
        const now = await tools.environment.now({ timeZone: "\(snippetTimeZone)" });
        return {
          names: vars.variables.map(v => v.name),
          variables: vars.variables,
          \(correctionKey): vars.correction,
          \(correctionIsNullKey): vars.correction === null,
          os: os.name,
          date: now.date,
          weekday: now.weekday
        };
        """

    /// The output that the snippet must give over ``InjectedEnvironment``:
    /// each application variable in name order, the injected platform, and
    /// the date of the injected instant in UTC.
    private static let expectedOutput = GoalSnippetOutput(
        names: [InjectedEnvironment.modeName, InjectedEnvironment.titleName],
        variables: [
            SnippetVariable(name: InjectedEnvironment.modeName, value: InjectedEnvironment.modeValue),
            SnippetVariable(name: InjectedEnvironment.titleName, value: InjectedEnvironment.titleValue),
        ],
        correction: nil,
        os: InjectedEnvironment.operatingSystem.name,
        date: "2026-10-08",
        weekday: "Thursday")

    // MARK: - Helpers

    /// Runs the goal snippet over a registry with the injected environment.
    ///
    /// - Returns: The rendered output of the run.
    /// - Throws: What `buildRegistry()` or the run throws.
    private static func runGoalSnippet() async throws -> String {
        let registry = try MultiTool.Builder()
            .withEnvironment(context: InjectedEnvironment.context())
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: goalSnippet))
    }

    // MARK: - Tests

    /// The snippet gives the application variables as objects, no
    /// correction, the injected platform, and the date of the injected
    /// instant in the time zone that the snippet asks for.
    @Test("the goal snippet gives the injected variables, platform, and date")
    func theGoalSnippetGivesTheInjectedValues() async throws {
        let output = try await Self.runGoalSnippet()

        let result = try RunOutput.decoded(GoalSnippetOutput.self, from: output)
        #expect(result == Self.expectedOutput, "the output was \(output)")
    }

    /// The `nil` correction of `tools.environment.variables` reaches the
    /// snippet as `null`, as its `@Guide` text says, and `=== null` in
    /// JavaScript is true for it (task `^efqdpfn`).
    ///
    /// `ArgumentMarshaler.renderOutput(_:)` gives `null` for each `nil`
    /// optional field that the schema of a result declares. Thus
    /// `JSON.stringify` writes a `correction` key with the value `null`. A
    /// decode into `String?` gives `nil` for `null` and for a missing key,
    /// thus this test reads the JSON object itself.
    @Test("the nil correction reaches the snippet as null")
    func theNilCorrectionReachesTheSnippetAsNull() async throws {
        let output = try await Self.runGoalSnippet()

        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
            "the output was \(output)")
        #expect(object[Self.correctionKey] is NSNull, "the output was \(output)")
        #expect(object[Self.correctionIsNullKey] as? Bool == true, "the output was \(output)")
    }
}

/// The value that the goal snippet returns.
private struct GoalSnippetOutput: Decodable, Equatable {

    /// The name of each variable, in the order of the result.
    let names: [String]

    /// Each variable, as the snippet read it.
    let variables: [SnippetVariable]

    /// The correction of `tools.environment.variables`, or `nil`.
    let correction: String?

    /// The name of the platform.
    let os: String

    /// The date, as `yyyy-MM-dd`.
    let date: String

    /// The English name of the day of the week.
    let weekday: String
}

/// One environment variable, as the snippet returns it.
private struct SnippetVariable: Decodable, Equatable {

    /// The name of the variable.
    let name: String

    /// The value of the variable.
    let value: String
}
