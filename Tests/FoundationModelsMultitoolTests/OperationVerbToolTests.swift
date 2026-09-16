import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing

@testable import FoundationModelsMultitool

/// Coverage for ``OperationVerbTool``, the `Tool` that presents one operation
/// of an `OperationDescribing` tool with a schema of that operation alone.
///
/// Every case runs against ``NotesOperationTool``
/// (`Fixtures/OperationToolFixtures.swift`), a hand-conformed parent with five
/// notes operations over an in-memory store. The parent records each payload
/// `perform(_:)` receives, so a case can read what the verb sent.
@Suite("OperationVerbToolTests")
struct OperationVerbToolTests {
    // MARK: - Shared test constants

    /// The op strings the camelCase rule is checked against, each with the
    /// verb name the card expects for it. The last two hold upper-case and
    /// mixed-case words, so the rule must lowercase each word before it
    /// capitalizes the first letter of the word.
    private static let verbNameCases: [(opString: String, verbName: String)] = [
        ("add note", "addNote"),
        ("list note", "listNote"),
        ("get type_definition", "getTypeDefinition"),
        ("get callgraph", "getCallgraph"),
        ("GET Type_Definition", "getTypeDefinition"),
        ("Delete NOTE", "deleteNote"),
    ]

    /// The verb name of the `add note` operation.
    private static let addNoteVerbName = "addNote"

    /// The declaration the renderer writes for `add note`: `title` required,
    /// `body` and `tags` optional, in descriptor order, with a parsed JSON result.
    private static let addNoteDeclaration =
        "declare function addNote(args: { title: string; body?: string; tags?: string[] }): Promise<object>;"

    /// The example call the renderer writes for `add note`; it names `title` only.
    private static let addNoteExample = #"await tools.addNote({ title: "title" });"#

    /// The `@example` line inside the doc block of `add note`.
    private static let addNoteExampleLine = #"@example const r = await tools.addNote({ title: "title" });"#

    /// The op string of the hand-built descriptor of the choices case.
    private static let setUnitOp = "set unit"

    /// The one parameter of the choices case.
    private static let unitParameter = "unit"

    /// The allowed values of the choices case.
    private static let unitValues = ["c", "f"]

    /// The union the renderer writes for the allowed values of the choices case.
    private static let unitUnion = #""c" | "f""#

    /// The title the call cases send.
    private static let noteTitle = "x"

    /// A note id no note has.
    private static let absentNoteID = "missing"

    /// A priority outside the allowed values of `tag note`.
    private static let rejectedPriority = "urgent"

    /// The tag the tag case adds.
    private static let addedTag = "work"

    // MARK: - Helpers

    /// The verb of `parent` for the operation `opString` names.
    ///
    /// - Parameters:
    ///   - opString: The op string of one operation of `parent`.
    ///   - parent: The fixture tool.
    /// - Returns: The verb.
    /// - Throws: When `parent` declares no such operation, or the schema cannot be built.
    private static func verb(for opString: String, on parent: NotesOperationTool) throws -> OperationVerbTool {
        let descriptor = try #require(parent.operationDescriptors.first { $0.opString == opString })
        return try OperationVerbTool(parent: parent, descriptor: descriptor)
    }

    /// A descriptor with one string parameter whose values are ``unitValues``.
    private static var setUnitDescriptor: OperationDescriptor {
        OperationDescriptor(
            verb: "set", noun: "unit", opString: setUnitOp,
            description: "Sets the temperature unit.",
            parameters: [
                OperationParameterDescriptor(
                    name: unitParameter, type: .string, required: true, description: "the unit.",
                    aliases: [], allowedValues: unitValues)
            ])
    }

    /// The string `content` holds, or `nil` when `content` is not a string.
    ///
    /// - Parameter content: The content to read.
    /// - Returns: The string.
    private static func text(of content: GeneratedContent) -> String? {
        guard case .string(let text) = content.kind else { return nil }
        return text
    }

    /// Adds one note to `parent` through the `add note` verb and returns its id.
    ///
    /// - Parameter parent: The fixture tool.
    /// - Returns: The id of the new note.
    /// - Throws: What the verb throws.
    private static func addNote(to parent: NotesOperationTool) async throws -> String {
        let verb = try verb(for: NotesOperationTool.addNoteOp, on: parent)
        let result = try await verb.call(
            arguments: GeneratedContent(properties: [NotesOperationTool.titleParameter: noteTitle]))
        return try result.value(String.self, forProperty: NotesOperationTool.idParameter)
    }

    // MARK: - The verb name

    @Test(
        "verbName(for:) splits the op string on spaces, underscores and hyphens into a camelCase identifier",
        arguments: verbNameCases)
    func verbNameIsCamelCase(opString: String, verbName: String) {
        #expect(OperationVerbTool.verbName(for: opString) == verbName)
    }

    @Test("name is the verb name of the op string, and description is the descriptor's")
    func nameAndDescriptionComeFromTheDescriptor() throws {
        let parent = NotesOperationTool()
        let verb = try Self.verb(for: NotesOperationTool.addNoteOp, on: parent)

        #expect(verb.name == Self.addNoteVerbName)
        #expect(verb.description == verb.descriptor.description)
    }

    // MARK: - The rendered surface

    @Test("render() declares the parameters in descriptor order with a parsed JSON result")
    func renderDeclaresParametersInDescriptorOrder() throws {
        let parent = NotesOperationTool()
        let verb = try Self.verb(for: NotesOperationTool.addNoteOp, on: parent)

        let rendered = try verb.render()

        #expect(rendered.declaration == Self.addNoteDeclaration)
    }

    @Test("render() names only the required parameters in the example")
    func renderExampleNamesRequiredParametersOnly() throws {
        let parent = NotesOperationTool()
        let verb = try Self.verb(for: NotesOperationTool.addNoteOp, on: parent)

        let rendered = try verb.render()

        #expect(rendered.example == Self.addNoteExample)
        #expect(rendered.doc.contains(Self.addNoteExampleLine), "doc was: \(rendered.doc)")
    }

    @Test("render() turns allowedValues into a union of string literals")
    func renderTurnsAllowedValuesIntoAUnion() throws {
        let verb = try OperationVerbTool(parent: NotesOperationTool(), descriptor: Self.setUnitDescriptor)

        let rendered = try verb.render()

        #expect(rendered.declaration.contains(Self.unitUnion), "declaration was: \(rendered.declaration)")
    }

    // MARK: - The schema

    @Test("includesSchemaInInstructions is true")
    func includesSchemaInInstructionsIsTrue() throws {
        let verb = try Self.verb(for: NotesOperationTool.addNoteOp, on: NotesOperationTool())

        #expect(verb.includesSchemaInInstructions)
    }

    @Test("ToolInvoker rejects a payload with the required title missing, and the error names title")
    func invokerRejectsAMissingRequiredParameter() async throws {
        let parent = NotesOperationTool()
        let verb = try Self.verb(for: NotesOperationTool.addNoteOp, on: parent)

        let error = try await #require(throws: ToolInvokerError.self) {
            try await ToolInvoker.invoke(verb, content: GeneratedContent(properties: [:]))
        }

        #expect(error.kind == .missingRequiredField)
        #expect(error.field == NotesOperationTool.titleParameter)
        #expect(error.message.contains(NotesOperationTool.titleParameter))
        #expect(parent.recordedCalls.isEmpty)
    }

    /// The card accepts either outcome for a value outside `allowedValues`,
    /// because the parent checks allowed values at dispatch. This case records
    /// the outcome the schema gives today: the `anyOf` of string constants
    /// encodes as an `enum`, so `ToolInvoker.validate` rejects the value as a
    /// guide violation before the parent sees it.
    @Test("ToolInvoker rejects a value outside allowedValues as a guide violation, before the parent is called")
    func invokerRejectsAValueOutsideAllowedValues() async throws {
        let parent = NotesOperationTool()
        let noteID = try await Self.addNote(to: parent)
        let verb = try Self.verb(for: NotesOperationTool.tagNoteOp, on: parent)
        let content = GeneratedContent(properties: [
            NotesOperationTool.idParameter: noteID,
            NotesOperationTool.tagParameter: Self.addedTag,
            NotesOperationTool.priorityParameter: Self.rejectedPriority,
        ])

        let error = try await #require(throws: ToolInvokerError.self) {
            try await ToolInvoker.invoke(verb, content: content)
        }

        #expect(error.kind == .guideViolation)
        #expect(error.field == NotesOperationTool.priorityParameter)
        // The seed call is an `add note`; no `tag note` reached the parent.
        #expect(parent.recordedCalls(withOp: NotesOperationTool.tagNoteOp).isEmpty)
    }

    // MARK: - The call

    @Test("call sends the op beside the arguments to the parent, and returns a parsed object for JSON text")
    func callSendsTheOpAndParsesAJSONAnswer() async throws {
        let parent = NotesOperationTool()
        let verb = try Self.verb(for: NotesOperationTool.addNoteOp, on: parent)

        let result = try await verb.call(
            arguments: GeneratedContent(properties: [NotesOperationTool.titleParameter: Self.noteTitle]))

        let recorded = try #require(parent.recordedCalls.first)
        let names = try #require(TestSupport.propertyNames(of: recorded.payload))
        #expect(Set(names) == [NotesOperationTool.opParameter, NotesOperationTool.titleParameter])
        #expect(recorded.string(NotesOperationTool.opParameter) == NotesOperationTool.addNoteOp)
        #expect(recorded.string(NotesOperationTool.titleParameter) == Self.noteTitle)
        #expect(recorded.contextOp == nil)
        #expect(TestSupport.propertyNames(of: result) != nil, "result was: \(result)")
        #expect(try result.value(String.self, forProperty: NotesOperationTool.titleParameter) == Self.noteTitle)
    }

    @Test("call puts the descriptor's op over any op the caller sent")
    func callOverridesTheCallersOp() async throws {
        let parent = NotesOperationTool()
        let verb = try Self.verb(for: NotesOperationTool.addNoteOp, on: parent)

        _ = try await verb.call(
            arguments: GeneratedContent(properties: [
                NotesOperationTool.opParameter: NotesOperationTool.deleteNoteOp,
                NotesOperationTool.titleParameter: Self.noteTitle,
            ]))

        let recorded = try #require(parent.recordedCalls.first)
        #expect(recorded.string(NotesOperationTool.opParameter) == NotesOperationTool.addNoteOp)
        #expect(parent.recordedCalls(withOp: NotesOperationTool.deleteNoteOp).isEmpty)
    }

    @Test("call returns a string when the parent answers text that is not JSON")
    func callReturnsAStringForPlainText() async throws {
        let parent = NotesOperationTool()
        let noteID = try await Self.addNote(to: parent)
        let verb = try Self.verb(for: NotesOperationTool.deleteNoteOp, on: parent)

        let result = try await verb.call(
            arguments: GeneratedContent(properties: [NotesOperationTool.idParameter: noteID]))

        #expect(Self.text(of: result) == NotesOperationTool.deletionMessage(for: noteID))
        #expect(parent.notes.isEmpty)
    }

    @Test("an error thrown by perform propagates out of call unchanged")
    func callPropagatesThePerformError() async throws {
        let parent = NotesOperationTool()
        let verb = try Self.verb(for: NotesOperationTool.getNoteOp, on: parent)

        let error = try await #require(throws: NotesOperationError.self) {
            try await verb.call(
                arguments: GeneratedContent(properties: [NotesOperationTool.idParameter: Self.absentNoteID]))
        }

        #expect(error == .missingNote(id: Self.absentNoteID))
    }
}
