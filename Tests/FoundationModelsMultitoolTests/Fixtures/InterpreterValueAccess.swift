@testable import FoundationModelsMultitool

/// Reads one case of an `InterpreterValue` as an optional, thus a test can
/// unwrap it with the require macro and does not need a `guard case`.
///
/// Each member gives `nil` when the value is a different case. Then the
/// require macro records an issue and stops the test at that point.
extension InterpreterValue {

    /// The items of an array value, or `nil` when the value is not an array.
    var arrayItems: [InterpreterValue]? {
        if case .array(let items) = self {
            return items
        }
        return nil
    }

    /// The fields of an object value, or `nil` when the value is not an
    /// object.
    var objectFields: [String: InterpreterValue]? {
        if case .object(let fields) = self {
            return fields
        }
        return nil
    }

    /// The text of a string value, or `nil` when the value is not a string.
    var stringText: String? {
        if case .string(let text) = self {
            return text
        }
        return nil
    }
}
