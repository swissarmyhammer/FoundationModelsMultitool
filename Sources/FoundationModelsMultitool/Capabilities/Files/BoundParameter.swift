// `BoundParameter` — the shared corrective vocabulary of a bounded integer
// verb parameter.
//
// The read verb's `offset` and `limit`, and the web verbs' `count`,
// `maxCharacters`, and `timeout`, are integer parameters with an inclusive
// range. Each one rejects a value out of its range with one corrective
// message that names the range. This type is that one code path, thus the
// verbs do not drift out of step with each other.

import Foundation

/// A bounded integer parameter: its name, the kind of value it expects, and
/// its inclusive range.
///
/// Bound checking is data, not control flow: each parameter is one instance
/// of this type, and ``violation(_:)`` is the single code path that
/// validates a value and builds its corrective message. There is no
/// per-parameter validation function or message string to keep in lockstep —
/// a parameter's whole identity lives in its instance.
struct BoundParameter {
    /// The parameter name, as it appears in backticks in a corrective message (`offset`).
    let parameterName: String

    /// The kind of value expected, as it reads in a corrective message (`1-based line number`).
    let typeDescription: String

    /// The smallest acceptable value.
    let minimum: Int

    /// The largest acceptable value, or `nil` when the range has no upper end.
    let maximum: Int?

    /// Makes a bounded parameter.
    ///
    /// - Parameters:
    ///   - parameterName: The parameter name, as it appears in backticks in a
    ///     corrective message.
    ///   - typeDescription: The kind of value expected, as it reads in a
    ///     corrective message.
    ///   - minimum: The smallest acceptable value.
    ///   - maximum: The largest acceptable value. The default, `nil`, gives
    ///     a range with no upper end.
    init(parameterName: String, typeDescription: String, minimum: Int, maximum: Int? = nil) {
        self.parameterName = parameterName
        self.typeDescription = typeDescription
        self.minimum = minimum
        self.maximum = maximum
    }

    /// The corrective message naming this parameter's valid, inclusive range.
    var correctiveMessage: String {
        let lead = "The `\(parameterName)` parameter must be a \(typeDescription)"
        guard let maximum else { return "\(lead) of \(minimum) or more." }
        return "\(lead) between \(minimum) and \(maximum)."
    }

    /// A corrective message when `value` is present and out of range, or `nil` when acceptable.
    ///
    /// An absent value is acceptable (the parameter was omitted); an
    /// in-range value is acceptable; an out-of-range value yields
    /// ``correctiveMessage``.
    ///
    /// - Parameter value: the requested value, or `nil` when the parameter was omitted.
    /// - Returns: ``correctiveMessage`` when `value` is present and out
    ///   of range, else `nil`.
    func violation(_ value: Int?) -> String? {
        guard let value else { return nil }
        let isInRange = value >= minimum && (maximum.map { value <= $0 } ?? true)
        return isInRange ? nil : correctiveMessage
    }
}
