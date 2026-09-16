import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import Synchronization

// MARK: - `NotesOperationTool` — a hand-conformed `OperationDescribing` fixture
//
// `OperationVerbToolTests` mounts one verb of this tool at a time. The fixture
// keeps five notes-like operations over an in-memory store, and it records
// every payload that `perform(_:)` receives beside the `op` of the ambient
// `ToolContext`. A later card reads that record. The fixture imports
// `FoundationModelsExtras` and `FoundationModelsRouter` only; it does not use
// the `Operations` macros.

/// One call that ``NotesOperationTool/perform(_:)`` received.
struct RecordedOperationCall: Sendable {
    /// The payload the parent received, with its `op` key.
    let payload: GeneratedContent

    /// The `op` of the ambient `ToolContext` at the time of the call, or `nil`
    /// when no context was bound.
    let contextOp: String?

    /// The string under `key` in the payload, or `nil` when the payload has
    /// no such string.
    ///
    /// A test that reads the `op`, the `id` or the `tag` of a recorded call
    /// reads it here, thus one implementation reads the payload and no suite
    /// carries a near-identical copy.
    ///
    /// - Parameter key: The key to read.
    /// - Returns: The string.
    func string(_ key: String) -> String? {
        NotesOperationTool.string(key, in: payload)
    }
}

/// The refusal ``NotesOperationTool/perform(_:)`` throws.
///
/// A distinct `Equatable` type, so a test can assert that the same error
/// comes out of `OperationVerbTool.call(arguments:)` unchanged.
enum NotesOperationError: Error, Equatable {
    /// The payload had no `op` key, or the `op` names no operation of the fixture.
    case unknownOperation(String?)

    /// The operation needs a parameter, and the payload did not have it.
    case missingParameter(String)

    /// No note has the given id.
    case missingNote(id: String)
}

/// One note in the in-memory store.
struct Note: Codable, Equatable, Sendable {
    /// The id the store gave the note.
    let id: String

    /// The title of the note.
    let title: String

    /// The body of the note, or an empty string.
    let body: String

    /// The tags on the note.
    var tags: [String]
}

/// The typed arguments of ``NotesOperationTool/call(arguments:)``: the `op`
/// key and the union of the fields of the five operations.
@Generable
struct NotesCallArguments {
    @Guide(description: "The operation to do, for example `add note`.")
    var op: String

    @Guide(description: "The id of a note.")
    var id: String?

    @Guide(description: "The title of a note.")
    var title: String?

    @Guide(description: "The body of a note.")
    var body: String?

    @Guide(description: "The tags to put on a new note.")
    var tags: [String]?

    @Guide(description: "One tag to add to a note, or to filter a list by.")
    var tag: String?

    @Guide(description: "The priority of a tag.")
    var priority: String?
}

/// An `OperationDescribing` tool with five notes operations over an
/// in-memory store.
///
/// `final class ... Sendable`, and not a `struct`, because the store and the
/// call record are shared mutable state a test reads after a call returns.
/// The only stored property is a `Mutex`, which is `Sendable`.
final class NotesOperationTool: OperationDescribing, Sendable {
    // MARK: Op strings

    /// The op string of the operation that adds a note.
    static let addNoteOp = "add note"

    /// The op string of the operation that reads one note.
    static let getNoteOp = "get note"

    /// The op string of the operation that lists notes.
    static let listNoteOp = "list note"

    /// The op string of the operation that deletes a note.
    static let deleteNoteOp = "delete note"

    /// The op string of the operation that adds a tag to a note.
    static let tagNoteOp = "tag note"

    // MARK: Parameter names

    /// The key of the `op` string in a payload.
    static let opParameter = "op"

    /// The name of the `id` parameter.
    static let idParameter = "id"

    /// The name of the `title` parameter.
    static let titleParameter = "title"

    /// The name of the `body` parameter.
    static let bodyParameter = "body"

    /// The name of the `tags` parameter.
    static let tagsParameter = "tags"

    /// The name of the `tag` parameter.
    static let tagParameter = "tag"

    /// The name of the `priority` parameter.
    static let priorityParameter = "priority"

    /// The values the `priority` parameter accepts.
    static let priorityValues = ["low", "medium", "high"]

    /// The noun of every operation of this fixture.
    static let noun = "note"

    /// The prefix of every note id; the store appends a counter.
    private static let noteIDPrefix = "n"

    // MARK: Tool

    let name = "notes"

    let description = "Keeps notes in an in-memory store."

    /// The descriptors of the five operations, in the order the tool declares them.
    let operationDescriptors: [OperationDescriptor] = [
        OperationDescriptor(
            verb: "add", noun: noun, opString: addNoteOp,
            description: "Adds a note and returns it.",
            parameters: [
                parameter(titleParameter, type: .string, required: true, description: "the note title."),
                parameter(bodyParameter, type: .string, required: false, description: "the note body."),
                parameter(tagsParameter, type: .array(of: .string), required: false, description: "tags to attach."),
            ]),
        OperationDescriptor(
            verb: "get", noun: noun, opString: getNoteOp,
            description: "Returns one note.",
            parameters: [
                parameter(idParameter, type: .string, required: true, description: "the note id.")
            ]),
        OperationDescriptor(
            verb: "list", noun: noun, opString: listNoteOp,
            description: "Lists the notes, all of them or those with one tag.",
            parameters: [
                parameter(tagParameter, type: .string, required: false, description: "keep only notes with this tag.")
            ]),
        OperationDescriptor(
            verb: "delete", noun: noun, opString: deleteNoteOp,
            description: "Deletes one note.",
            parameters: [
                parameter(idParameter, type: .string, required: true, description: "the note id.")
            ]),
        OperationDescriptor(
            verb: "tag", noun: noun, opString: tagNoteOp,
            description: "Adds a tag to one note.",
            parameters: [
                parameter(idParameter, type: .string, required: true, description: "the note id."),
                parameter(tagParameter, type: .string, required: true, description: "the tag to add."),
                parameter(
                    priorityParameter, type: .string, required: false, description: "the priority of the tag.",
                    allowedValues: priorityValues),
            ]),
    ]

    // MARK: Store

    /// The store and the call record, behind one lock.
    private struct State {
        /// The notes, by id.
        var notes: [String: Note] = [:]

        /// The counter the next note id takes.
        var nextNoteNumber = 1

        /// Every payload `perform(_:)` received, in call order.
        var calls: [RecordedOperationCall] = []
    }

    /// The store and the call record.
    private let state = Mutex(State())

    /// Every call `perform(_:)` received, in call order.
    var recordedCalls: [RecordedOperationCall] {
        state.withLock { $0.calls }
    }

    /// The calls `perform(_:)` received whose `op` is `op`, in call order.
    ///
    /// A test that seeds the store through one operation and then checks the
    /// calls of another operation reads the second set here, thus the seed
    /// calls do not mix with the calls under test, and no suite carries a
    /// near-identical filter.
    ///
    /// - Parameter op: The op string to keep.
    /// - Returns: The calls with that op.
    func recordedCalls(withOp op: String) -> [RecordedOperationCall] {
        recordedCalls.filter { $0.string(Self.opParameter) == op }
    }

    /// The notes in the store, in id order.
    var notes: [Note] {
        state.withLock { $0.notes.values.sorted { $0.id < $1.id } }
    }

    // MARK: Calls

    /// The model-facing entry. A refusal comes back as text, as the
    /// `OperationDescribing` contract asks; any other error propagates.
    ///
    /// - Parameter arguments: The typed payload of one operation.
    /// - Returns: The output text, or the refusal as text.
    func call(arguments: NotesCallArguments) async throws -> String {
        do {
            return try await perform(arguments.generatedContent)
        } catch let refusal as NotesOperationError {
            return "Error: \(refusal)"
        }
    }

    /// Records `arguments` beside the ambient `op`, then dispatches the operation.
    ///
    /// - Parameter arguments: The payload with the `op` key and the fields of one operation.
    /// - Returns: The output text of the operation.
    /// - Throws: ``NotesOperationError`` for a bad op, a missing parameter, or a missing note.
    func perform(_ arguments: GeneratedContent) async throws -> String {
        let call = RecordedOperationCall(payload: arguments, contextOp: ToolContext.current?.op)
        state.withLock { $0.calls.append(call) }
        let op = Self.string(Self.opParameter, in: arguments)
        switch op {
        case Self.addNoteOp:
            return try addNote(arguments)
        case Self.getNoteOp:
            return try encode(try note(withIDIn: arguments))
        case Self.listNoteOp:
            return try listNotes(arguments)
        case Self.deleteNoteOp:
            return try deleteNote(arguments)
        case Self.tagNoteOp:
            return try tagNote(arguments)
        default:
            throw NotesOperationError.unknownOperation(op)
        }
    }

    // MARK: Operations

    /// Adds a note from `title`, `body` and `tags`, and returns it as JSON.
    private func addNote(_ arguments: GeneratedContent) throws -> String {
        guard let title = Self.string(Self.titleParameter, in: arguments) else {
            throw NotesOperationError.missingParameter(Self.titleParameter)
        }
        let body = Self.string(Self.bodyParameter, in: arguments) ?? ""
        let tags = Self.strings(Self.tagsParameter, in: arguments) ?? []
        let note = state.withLock { state in
            let note = Note(id: "\(Self.noteIDPrefix)\(state.nextNoteNumber)", title: title, body: body, tags: tags)
            state.nextNoteNumber += 1
            state.notes[note.id] = note
            return note
        }
        return try encode(note)
    }

    /// Lists the notes as a JSON array, filtered by `tag` when the payload has one.
    private func listNotes(_ arguments: GeneratedContent) throws -> String {
        let tag = Self.string(Self.tagParameter, in: arguments)
        let kept = notes.filter { note in tag.map(note.tags.contains) ?? true }
        return try encode(kept)
    }

    /// Deletes the note `id` names and returns a plain-text confirmation.
    private func deleteNote(_ arguments: GeneratedContent) throws -> String {
        let note = try note(withIDIn: arguments)
        state.withLock { $0.notes[note.id] = nil }
        return Self.deletionMessage(for: note.id)
    }

    /// Adds `tag` to the note `id` names and returns the note as JSON.
    private func tagNote(_ arguments: GeneratedContent) throws -> String {
        var note = try note(withIDIn: arguments)
        guard let tag = Self.string(Self.tagParameter, in: arguments) else {
            throw NotesOperationError.missingParameter(Self.tagParameter)
        }
        note.tags.append(tag)
        state.withLock { $0.notes[note.id] = note }
        return try encode(note)
    }

    /// The plain-text confirmation ``deleteNote(_:)`` returns. It is not JSON.
    ///
    /// - Parameter id: The id of the deleted note.
    /// - Returns: The confirmation text.
    static func deletionMessage(for id: String) -> String {
        "Deleted note \(id)."
    }

    // MARK: Helpers

    /// The note the `id` of `arguments` names.
    ///
    /// - Throws: ``NotesOperationError/missingParameter(_:)`` when the payload
    ///   has no `id`, or ``NotesOperationError/missingNote(id:)`` when no note has it.
    private func note(withIDIn arguments: GeneratedContent) throws -> Note {
        guard let id = Self.string(Self.idParameter, in: arguments) else {
            throw NotesOperationError.missingParameter(Self.idParameter)
        }
        guard let note = state.withLock({ $0.notes[id] }) else {
            throw NotesOperationError.missingNote(id: id)
        }
        return note
    }

    /// `value` as JSON text with sorted keys, so the text is the same on every run.
    private func encode(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// The string under `key` in `payload`, or `nil` when the key is absent,
    /// `null`, or not a string.
    ///
    /// ``RecordedOperationCall/string(_:)`` calls this for a recorded payload,
    /// so the read stays in one place.
    static func string(_ key: String, in payload: GeneratedContent) -> String? {
        try? payload.value(String.self, forProperty: key)
    }

    /// The string array under `key` in `payload`, or `nil` when the key is
    /// absent, `null`, or not an array of strings.
    private static func strings(_ key: String, in payload: GeneratedContent) -> [String]? {
        try? payload.value([String].self, forProperty: key)
    }

    /// A parameter descriptor with no aliases.
    private static func parameter(
        _ name: String,
        type: OperationParameterType,
        required: Bool,
        description: String,
        allowedValues: [String]? = nil
    ) -> OperationParameterDescriptor {
        OperationParameterDescriptor(
            name: name, type: type, required: required, description: description,
            aliases: [], allowedValues: allowedValues)
    }
}

// MARK: - `RenamedNotesOperationTool` — the notes operations under a name a test picks

/// An `OperationDescribing` tool with the five operations of
/// ``NotesOperationTool``, under a name the test gives.
///
/// The registry makes the tool name the group of the verbs, and it checks
/// that name with the group-name rule. `OperationMountTests` uses this
/// fixture to give an operation tool a name that is not a legal identifier.
/// Every call goes to the wrapped ``NotesOperationTool``.
struct RenamedNotesOperationTool: OperationDescribing {
    /// The name the registry reads as the group of the verbs.
    let name: String

    /// The tool that holds the operations and the store.
    let notes = NotesOperationTool()

    var description: String { notes.description }

    var operationDescriptors: [OperationDescriptor] { notes.operationDescriptors }

    func call(arguments: NotesCallArguments) async throws -> String {
        try await notes.call(arguments: arguments)
    }

    func perform(_ arguments: GeneratedContent) async throws -> String {
        try await notes.perform(arguments)
    }
}
