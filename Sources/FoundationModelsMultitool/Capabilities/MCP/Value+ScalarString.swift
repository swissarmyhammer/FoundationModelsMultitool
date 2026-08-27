// `Value+ScalarString` — the string form of one scalar `MCP.Value`.
//
// A behavioral port of `../FoundationModelsMCP/Sources/FoundationModelsMCP/
// Value+ScalarString.swift`. eventplan.md § "Consolidation of the siblings"
// moves "the `SchemaConverter` / `GeneratedContentCodec` pair" into this
// folder, and this one function comes with the pair because `SchemaConverter`
// reads it.
//
// A JSON Schema `enum` lists values of any scalar type — `enum: [1, 2, 3]` is
// valid — and `DynamicGenerationSchema(name:description:anyOf:)` takes strings
// alone. This function is the one rendering the converter applies at that
// step, thus an enum of numbers still gives the model a set of choices.
//
// `ToolContentRenderer` reads the same function for its enum-membership
// check. The function stands in a file of its own for that reason: it has two
// readers, and neither one owns it.

import MCP

/// Renders one scalar `Value` (string, int, double or bool) to its string form.
///
/// - Parameter value: The value to render.
/// - Returns: The string form of `value`, or `nil` when `value` is not a
///   scalar. An array, an object, `null` and `data` have no defined string
///   form.
func scalarString(_ value: Value) -> String? {
    switch value {
    case .string(let string): return string
    case .int(let int): return String(describing: int)
    case .double(let double): return String(describing: double)
    case .bool(let bool): return String(describing: bool)
    default: return nil
    }
}
