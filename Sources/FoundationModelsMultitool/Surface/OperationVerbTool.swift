// `OperationVerbTool` — one operation of an `OperationDescribing` tool,
// presented as an ordinary `FoundationModels.Tool`.
//
// An `OperationDescribing` tool (`FoundationModelsExtras`) dispatches many
// operations through one `call(arguments:)` whose payload carries an `op` key.
// The grammar of this package wants one verb for each operation
// (`tools.notes.addNote`), with a schema of that operation alone, so this type
// wraps one `OperationDescriptor` of the parent and stands in for the verb. It
// is the unit the registry mounts, `ToolInvoker` validates, and `searchTools`
// indexes.
//
// It follows `Capabilities/MCP/MCPTool.swift`: one Swift type,
// `Arguments = GeneratedContent`, and a schema given at run time. Two things
// differ. The schema is built here, from the descriptor, with
// `DynamicGenerationSchema`; and the surface the model reads is rendered from
// the descriptor through the typed path of `ToolAPIRenderer`, so the order of
// the parameters and their choices come from the descriptor and not from how
// the schema encodes.
//
// **The type is internal**, the way `MCPTool` is: the capability that
// registers the verbs of an `OperationDescribing` tool is the production
// caller, and the tests reach the type with `@testable import`.

import Foundation
import FoundationModels
import FoundationModelsExtras

/// The `FoundationModels.Tool` that presents one operation of an
/// `OperationDescribing` tool as a verb of its own.
///
/// One `OperationVerbTool` stands for exactly one ``descriptor`` of one
/// ``parent``. Its ``parameters`` schema holds the parameters of that
/// operation and no `op` key. ``call(arguments:)`` adds the `op` key itself and
/// hands the payload to `parent.perform(_:)`, so the parent checks the payload
/// at dispatch as it does for a model call.
struct OperationVerbTool: Tool, Sendable {
    /// `GeneratedContent` already conforms to `ConvertibleFromGeneratedContent`
    /// (the identity conversion), so no per-verb `Generable` type is needed.
    typealias Arguments = GeneratedContent

    /// The parsed answer of the parent: an object or an array when the parent
    /// answered JSON text, and a string otherwise.
    typealias Output = GeneratedContent

    /// The key of the op string in a payload of ``parent``.
    static let opKey = "op"

    /// The characters that separate the words of an op string.
    private static let wordSeparators: Set<Character> = [" ", "_", "-"]

    /// The tool every call goes to.
    let parent: any OperationDescribing

    /// The one operation of ``parent`` this verb presents.
    let descriptor: OperationDescriptor

    /// The op string of ``descriptor`` as a camelCase identifier — see ``verbName(for:)``.
    let name: String

    /// The schema of the parameters of ``descriptor``, with no `op` property.
    ///
    /// It serves `ToolInvoker.validate` and the `Tool` conformance only; the
    /// rendered surface comes from ``render()``.
    let parameters: GenerationSchema

    /// Always `true`: the schema of this one operation is the one the model needs.
    let includesSchemaInInstructions = true

    /// The description of ``descriptor``.
    var description: String { descriptor.description }

    /// Creates the verb for one operation of `parent`.
    ///
    /// - Parameters:
    ///   - parent: The tool every call goes to.
    ///   - descriptor: The operation of `parent` this verb presents.
    /// - Throws: What `GenerationSchema.init(root:dependencies:)` throws when
    ///   the parameters of `descriptor` do not make a valid schema.
    init(parent: any OperationDescribing, descriptor: OperationDescriptor) throws {
        self.parent = parent
        self.descriptor = descriptor
        self.name = Self.verbName(for: descriptor.opString)
        self.parameters = try Self.schema(for: descriptor, named: name)
    }

    // MARK: - The verb name

    /// The camelCase identifier of an op string.
    ///
    /// The op string is split on spaces, underscores and hyphens, and every
    /// word is lowercased. The first word stays lowercase; each other word
    /// gets a capital first letter. So `get symbol` gives `getSymbol`,
    /// `get type_definition` gives `getTypeDefinition`, and the case of the
    /// input does not reach the identifier: `GET Type_Definition` gives
    /// `getTypeDefinition` too.
    ///
    /// - Parameter opString: The op string of one operation.
    /// - Returns: The identifier, or an empty string for an op string with no word.
    static func verbName(for opString: String) -> String {
        let words = opString.split(whereSeparator: wordSeparators.contains).map { $0.lowercased() }
        guard let first = words.first else { return "" }
        let rest = words.dropFirst().map { word in word.prefix(1).uppercased() + word.dropFirst() }
        return ([first] + rest).joined()
    }

    // MARK: - The schema

    /// The `GenerationSchema` of the parameters of `descriptor`.
    ///
    /// - Parameters:
    ///   - descriptor: The operation.
    ///   - name: The verb name, which names the root schema.
    /// - Returns: The schema.
    /// - Throws: What `GenerationSchema.init(root:dependencies:)` throws.
    private static func schema(for descriptor: OperationDescriptor, named name: String) throws -> GenerationSchema {
        let properties = descriptor.parameters.map { parameter in
            DynamicGenerationSchema.Property(
                name: parameter.name,
                description: parameter.description,
                schema: dynamicSchema(for: parameter, verbName: name),
                isOptional: !parameter.required)
        }
        let root = DynamicGenerationSchema(name: name, description: descriptor.description, properties: properties)
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// The dynamic schema of one parameter: the `anyOf` of its allowed values
    /// when it has some, else the schema of its type.
    ///
    /// - Parameters:
    ///   - parameter: The parameter.
    ///   - verbName: The verb name, which prefixes the name of a choice schema.
    /// - Returns: The dynamic schema.
    private static func dynamicSchema(
        for parameter: OperationParameterDescriptor, verbName: String
    ) -> DynamicGenerationSchema {
        guard let allowedValues = parameter.allowedValues else {
            return dynamicSchema(for: parameter.type)
        }
        return DynamicGenerationSchema(
            name: "\(verbName).\(parameter.name)", description: parameter.description, anyOf: allowedValues)
    }

    /// The dynamic schema of one parameter type.
    ///
    /// - Parameter type: The parameter type.
    /// - Returns: The dynamic schema.
    private static func dynamicSchema(for type: OperationParameterType) -> DynamicGenerationSchema {
        switch type {
        case .string:
            DynamicGenerationSchema(type: String.self)
        case .integer:
            DynamicGenerationSchema(type: Int.self)
        case .number:
            DynamicGenerationSchema(type: Double.self)
        case .boolean:
            DynamicGenerationSchema(type: Bool.self)
        case .array(let element):
            DynamicGenerationSchema(arrayOf: dynamicSchema(for: element))
        }
    }

    // MARK: - The rendered surface

    /// Renders the surface of this verb from ``descriptor``.
    ///
    /// The parameters render in descriptor order. Allowed values become
    /// `.string(choices:)`, and an array type becomes `.array(element:)`. The
    /// result is declared as a parsed JSON value, because ``call(arguments:)``
    /// parses JSON text before the snippet sees it.
    ///
    /// - Returns: The rendered descriptor.
    /// - Throws: `ToolAPIRendererError` when ``name`` is not a legal identifier.
    func render() throws -> ToolDescriptor {
        let arguments = descriptor.parameters.map { parameter in
            ToolAPIRenderer.RenderedParameter(
                name: parameter.name,
                shape: Self.shape(for: parameter),
                isRequired: parameter.required,
                description: parameter.description)
        }
        return try ToolAPIRenderer.render(name: name, description: description, arguments: arguments, returns: .json)
    }

    /// The rendered shape of one parameter: a string with choices when it has
    /// allowed values, else the shape of its type.
    ///
    /// - Parameter parameter: The parameter.
    /// - Returns: The shape.
    private static func shape(for parameter: OperationParameterDescriptor) -> ToolValueShape {
        guard let allowedValues = parameter.allowedValues else {
            return shape(for: parameter.type)
        }
        return .string(choices: allowedValues.map(InterpreterValue.string))
    }

    /// The rendered shape of one parameter type.
    ///
    /// - Parameter type: The parameter type.
    /// - Returns: The shape.
    private static func shape(for type: OperationParameterType) -> ToolValueShape {
        switch type {
        case .string:
            .string(choices: [])
        case .integer, .number:
            .number
        case .boolean:
            .boolean
        case .array(let element):
            .array(element: shape(for: element))
        }
    }

    // MARK: - The call

    /// Sends `arguments` with the op of ``descriptor`` to ``parent`` and parses
    /// the answer.
    ///
    /// The `op` key of this verb wins over any `op` the caller sent. Text the
    /// parent answers is parsed as JSON when `JSONSerialization` accepts it as
    /// an object or an array, so the snippet gets a parsed value; any other
    /// text reaches the snippet as a string.
    ///
    /// - Parameter arguments: The generated arguments of this one operation.
    /// - Returns: The parsed answer of the parent.
    /// - Throws: What `parent.perform(_:)` throws, unchanged, or what
    ///   `GeneratedContent.init(json:)` throws for JSON text it cannot read.
    func call(arguments: GeneratedContent) async throws -> GeneratedContent {
        let answer = try await parent.perform(Self.payload(from: arguments, op: descriptor.opString))
        return try Self.output(from: answer)
    }

    /// `arguments` with the `op` key set to `op`.
    ///
    /// The `op` key goes first in key order. An `arguments` value that is not
    /// an object carries no named fields, so the payload holds the `op` alone.
    ///
    /// - Parameters:
    ///   - arguments: The generated arguments.
    ///   - op: The op string of the operation.
    /// - Returns: The payload for `perform(_:)`.
    private static func payload(from arguments: GeneratedContent, op: String) -> GeneratedContent {
        let opContent = GeneratedContent(kind: .string(op))
        guard case .structure(var properties, let orderedKeys) = arguments.kind else {
            return GeneratedContent(kind: .structure(properties: [opKey: opContent], orderedKeys: [opKey]))
        }
        properties[opKey] = opContent
        let keys = [opKey] + orderedKeys.filter { $0 != opKey }
        return GeneratedContent(kind: .structure(properties: properties, orderedKeys: keys))
    }

    /// The generated content of the text a parent answered.
    ///
    /// - Parameter text: The answer of `perform(_:)`.
    /// - Returns: The parsed object or array when `text` is JSON, else the string.
    /// - Throws: What `GeneratedContent.init(json:)` throws.
    private static func output(from text: String) throws -> GeneratedContent {
        guard isJSONContainer(text) else {
            return GeneratedContent(text)
        }
        return try GeneratedContent(json: text)
    }

    /// Whether `JSONSerialization` reads `text` as a JSON object or array.
    ///
    /// - Parameter text: The text to check.
    /// - Returns: `true` for a JSON object or array.
    private static func isJSONContainer(_ text: String) -> Bool {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
    }
}
