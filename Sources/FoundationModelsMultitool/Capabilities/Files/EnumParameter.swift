// `EnumParameter` — the shared corrective vocabulary of a string-enum verb
// parameter.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// EnumParameter.swift`, unchanged in behavior. The consuming verbs — the
// read verb's `format` (^d3px093) and the grep verb's `outputMode` and
// `type` (^2j06zb7) — are not in this package yet, thus until those land
// the caller is the `CorrectiveVocabularyTests` suite, which pins the
// rendered messages byte for byte.

import Foundation

/// The shared corrective vocabulary of a string-enum verb parameter.
///
/// The read verb's `format`, the grep verb's `outputMode`, and the grep
/// verb's `type` are all string parameters whose accepted values are the
/// keys of one authoritative lookup table, and all three reject an
/// unrecognized value by naming that accepted set. Deriving the names from
/// the table is what keeps a corrective from drifting out of step with what
/// its own verb accepts; deriving them *here* is what keeps the three from
/// drifting out of step with each other.
///
/// The rendered text is model-facing output, pinned byte for byte by the
/// tests. What is centralized here is scoped accordingly: ``nameList(_:)``
/// decides the ordering and separator of the accepted-value list for all
/// three, while ``unknownValueMessage(validNames:parameterName:)`` decides
/// the whole sentence only for the two whose corrective is a plain "must be
/// one of". The grep verb's `type` composes ``nameList(_:)`` into a richer
/// sentence it still owns, because its corrective also names the value that
/// was rejected.
enum EnumParameter {
    /// The separator between the accepted values in a corrective message.
    private static let nameSeparator = ", "

    /// The accepted values, sorted and joined as they read in a corrective message.
    ///
    /// Sorting here rather than at the call site is what makes the list
    /// stable: the values come from dictionary keys, whose order is not.
    ///
    /// - Parameter validNames: the accepted values, in any order.
    /// - Returns: the values sorted ascending and comma-separated.
    static func nameList(_ validNames: some Sequence<String>) -> String {
        validNames.sorted().joined(separator: nameSeparator)
    }

    /// The corrective message naming the accepted values of a string-enum parameter.
    ///
    /// - Parameters:
    ///   - validNames: the accepted values, in any order.
    ///   - parameterName: the parameter's name, rendered in backticks.
    /// - Returns: the corrective message the model reads and acts on.
    static func unknownValueMessage(validNames: some Sequence<String>, parameterName: String) -> String {
        "The `\(parameterName)` parameter must be one of: \(nameList(validNames))."
    }
}
