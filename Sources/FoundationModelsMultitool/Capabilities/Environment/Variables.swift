// `Variables` — the `tools.environment.variables` verb.
//
// The verb gives the environment variables of the process, as name and value
// pairs in name order. The user decided (2026-10-08) that the verb gives ALL
// names and values. There is no redaction filter.
//
// The verb is a plain `FoundationModels.Tool` that holds the context of the
// environment capability, in the pattern of `Capabilities/Git/Branches.swift`.
// The capability supplies the noun, thus this verb's `name` is the bare
// `variables` and the surface path renders as `tools.environment.variables`.
//
// The verb reads the variables through `EnvironmentContext.variables` at each
// call. Thus a variable that changes between two calls shows in the second
// result.
//
// A name that is not set, and `name` with `prefix` together, stay IN BAND, as
// a `correction` beside no variable. They are never thrown: each one is a
// mistake that the model can correct inside the turn, and a thrown error
// would end the turn instead.

import Foundation
import FoundationModels

/// The arguments of `tools.environment.variables`: one exact name, or one
/// prefix, or neither.
@Generable(description: "Which environment variables to give: one exact name, one prefix, or neither for all.")
struct VariablesArguments {

    /// The exact name of the one variable to give, or `nil`.
    @Guide(
        description:
            "The exact name of the one variable to give, with the same case (PATH, not path). Null to give more "
            + "than one variable. Do not give it together with prefix.")
    var name: String?

    /// The start of each name to give, or `nil`.
    @Guide(
        description:
            "Give each variable whose name starts with this text, with the same case. Null to give each "
            + "variable. Do not give it together with name.")
    var prefix: String?
}

/// One environment variable: its name and its value.
@Generable(description: "One environment variable: its name and its value.")
struct EnvironmentVariable {

    /// The name of the variable.
    @Guide(description: "The name of the variable.")
    var name: String

    /// The value of the variable, as the process has it.
    @Guide(description: "The value of the variable, as the process has it. It can be empty.")
    var value: String
}

/// The result of `tools.environment.variables`: the variables, or the
/// correction that says why there is no variable.
///
/// `correction` and the variables are exclusive. A list that answers
/// variables carries no correction, and a correction carries no variable.
@Generable(description: "the environment variables in name order, or the correction that says why there is no variable.")
struct VariablesResult {

    /// The variables that the arguments select, in name order.
    @Guide(description: "The environment variables that the arguments select, in name order.")
    var variables: [EnvironmentVariable]

    /// Why the verb answered no variable, or `nil` when the variables stand.
    @Guide(description: "Why the verb answered no variable; null when the variables stand.")
    var correction: String?
}

extension Variables {

    // MARK: Corrective text

    /// The correction for `name` and `prefix` together.
    private static let nameAndPrefixCorrection =
        "give name or prefix, not both: name gives one variable, and prefix gives each variable whose name "
        + "starts with it"

    /// The correction for a name that is not set.
    ///
    /// - Parameter name: The name that the model asked for.
    /// - Returns: The correction the model reads.
    private static func unsetCorrection(for name: String) -> String {
        "the environment variable \(name) is not set; call variables with no argument, or with a prefix, to "
            + "see the names that are set"
    }

    // MARK: Execution

    /// Gives the variables that the arguments select, or the correction that
    /// says why there is no variable.
    ///
    /// Reads the variables through the context at each call. Each mistake
    /// comes back as the `correction` field of the result; nothing here
    /// throws.
    ///
    /// - Parameter arguments: One exact name, or one prefix, or neither.
    /// - Returns: The variables, or the correction.
    func call(arguments: VariablesArguments) async throws -> VariablesResult {
        guard arguments.name == nil || arguments.prefix == nil else {
            return Self.corrective(Self.nameAndPrefixCorrection)
        }
        let variables = context.variables()
        if let name = arguments.name {
            return Self.result(naming: name, in: variables)
        }
        return Self.result(listing: variables, startingWith: arguments.prefix)
    }

    // MARK: Steps

    /// The result for one exact name.
    ///
    /// - Parameters:
    ///   - name: The name that the model asked for.
    ///   - variables: The variables of the process.
    /// - Returns: The one variable, or the correction for a name that is not
    ///   set.
    private static func result(naming name: String, in variables: [String: String]) -> VariablesResult {
        guard let value = variables[name] else {
            return corrective(unsetCorrection(for: name))
        }
        return VariablesResult(variables: [EnvironmentVariable(name: name, value: value)], correction: nil)
    }

    /// The result for each variable whose name starts with a prefix.
    ///
    /// - Parameters:
    ///   - variables: The variables of the process.
    ///   - prefix: The start of each name to give, or `nil` for each
    ///     variable.
    /// - Returns: The variables that match, in name order. No match is an
    ///   empty list, not a correction.
    private static func result(listing variables: [String: String], startingWith prefix: String?) -> VariablesResult {
        let listed =
            variables
            .filter { name, _ in prefix.map { name.hasPrefix($0) } ?? true }
            .map { name, value in EnvironmentVariable(name: name, value: value) }
            .sorted { $0.name < $1.name }
        return VariablesResult(variables: listed, correction: nil)
    }

    // MARK: Corrective results

    /// A result that carries only a correction: no variable.
    ///
    /// - Parameter message: The correction the model reads and acts on.
    /// - Returns: The corrective ``VariablesResult``.
    private static func corrective(_ message: String) -> VariablesResult {
        VariablesResult(variables: [], correction: message)
    }
}

/// Gives the environment variables of the process, as name and value pairs.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const { variables } = await tools.environment.variables({ prefix: "LANG" });
/// ```
///
/// The contract: with no argument, each variable in name order; with `name`,
/// only that variable; with `prefix`, each variable whose name starts with
/// it, in name order. A name that is not set, and the two arguments
/// together, come back as a `correction`, not as an error.
struct Variables: Tool {

    /// The verb this tool renders as, which the environment noun stands in
    /// front of: `tools.environment.variables`.
    let name = "variables"

    /// The usage instructions, as the model reads them.
    let description = """
        variables gives the environment variables of the process, as name and value pairs in name \
        order, with each value as the process has it. With no argument it gives each variable. name \
        gives only the variable with that exact name; prefix gives each variable whose name starts \
        with that text. Names match with the same case. A name that is not set, or name and prefix \
        together, comes back as a correction rather than as an error — read it and act on it.
        """

    /// The session context this verb reads against, which the environment
    /// capability owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Variables(context:)`.
    let context: EnvironmentContext
}
