import FoundationModels
import Operations

// The one operation tool of the gated package. The unit tests of the root
// package drive a hand-conformed `OperationDescribing` fixture and no macro.
// This file drives the real stack: five `@Generable @Operation` structs, fused
// by `OperationTool`, so a live run proves that a tool the macros build
// expands into verbs, is found by `searchTools` and is called through
// `runCode`. It follows
// `../FoundationModelsExtras/Examples/NotesTool/Sources/NotesToolCore`, and
// it stands here because this package must not depend on an example target.

/// One note in ``IntegrationNotesStore``.
struct IntegrationNote: Encodable, Sendable, Equatable {
    /// The id the store gave the note, for example `note-1`.
    let id: String

    /// The title of the note.
    let title: String

    /// The body of the note, or `nil` when the note has no body.
    let body: String?

    /// The tags on the note, in the order they were added.
    var tags: [String]
}

/// The in-memory note store the five operations share.
///
/// An `actor`, because `OperationTool.call(arguments:)` can run for more
/// than one call at a time, and every change to the notes needs one
/// synchronized home. A test reads the store after the turn to grade what
/// the snippets really did.
actor IntegrationNotesStore {
    /// The prefix of every note id. The store appends a counter to it.
    static let noteIDPrefix = "note-"

    /// Every note in the store, by id.
    private var notesByID: [String: IntegrationNote] = [:]

    /// Every note id, in insertion order. A dictionary has no order, and
    /// ``list()`` must return the notes in a stable order.
    private var orderedIDs: [String] = []

    /// The counter the next note id takes.
    private var nextSequence = 1

    /// Inserts a new note and gives it the next id.
    ///
    /// - Parameters:
    ///   - title: The title of the note.
    ///   - body: The body of the note, or `nil`.
    ///   - tags: The tags to attach, in the given order.
    /// - Returns: The stored note, with its id.
    func insert(title: String, body: String?, tags: [String]) -> IntegrationNote {
        let note = IntegrationNote(id: "\(Self.noteIDPrefix)\(nextSequence)", title: title, body: body, tags: tags)
        nextSequence += 1
        notesByID[note.id] = note
        orderedIDs.append(note.id)
        return note
    }

    /// Finds one note by id.
    ///
    /// - Parameter id: The id to find.
    /// - Returns: The note, or `nil` when no note has that id.
    func find(id: String) -> IntegrationNote? {
        notesByID[id]
    }

    /// Every stored note, in insertion order.
    ///
    /// - Returns: The notes.
    func list() -> [IntegrationNote] {
        orderedIDs.compactMap { notesByID[$0] }
    }

    /// Removes one note by id.
    ///
    /// - Parameter id: The id to remove.
    /// - Returns: The removed note, or `nil` when no note had that id. The
    ///   store does not change in that case.
    func remove(id: String) -> IntegrationNote? {
        guard let note = notesByID.removeValue(forKey: id) else { return nil }
        orderedIDs.removeAll { $0 == id }
        return note
    }

    /// Adds `tags` to one note. A tag the note already has is not added again.
    ///
    /// - Parameters:
    ///   - tags: The tags to attach, in the given order.
    ///   - id: The id of the note.
    /// - Returns: The changed note, or `nil` when no note had that id. The
    ///   store does not change in that case.
    func addTags(_ tags: [String], toNoteWithID id: String) -> IntegrationNote? {
        guard var note = notesByID[id] else { return nil }
        for tag in tags where !note.tags.contains(tag) {
            note.tags.append(tag)
        }
        notesByID[id] = note
        return note
    }

    /// Returns `note`, or throws when it is `nil`.
    ///
    /// The three operations that read a note by id — get, delete and tag —
    /// share this one check, so the not-found error has one home.
    ///
    /// - Parameters:
    ///   - note: The result of a store lookup.
    ///   - id: The id the lookup used, for the error.
    /// - Returns: `note`, unwrapped.
    /// - Throws: ``IntegrationNotesError/notFound(id:)`` when `note` is `nil`.
    static func requiring(_ note: IntegrationNote?, id: String) throws -> IntegrationNote {
        guard let note else {
            throw IntegrationNotesError.notFound(id: id)
        }
        return note
    }
}

/// The error an operation throws when no note has the given id.
///
/// `OperationTool` wraps it in `OperationError.executionFailed(cause:)`, and
/// `runCode` hands that to the snippet as a rejection.
enum IntegrationNotesError: Error, Equatable {
    /// No note has this id.
    case notFound(id: String)
}

/// The environment every operation runs against.
struct IntegrationNotesContext: Sendable {
    /// The store the operations read and change.
    let store: IntegrationNotesStore
}

/// Creates a note.
@Generable
@Operation(verb: "add", noun: "note", description: "Create a new note with a title, and optionally a body and tags")
struct IntegrationAddNote {
    @Guide(description: "The title of the note")
    var title: String

    @Guide(description: "The body text of the note")
    var body: String?

    @Guide(description: "Tags to attach to the new note")
    var tags: [String]?
}

extension IntegrationAddNote {
    /// Inserts the note and returns it with its id.
    ///
    /// - Parameter context: The environment with the store.
    /// - Returns: The stored note.
    func execute(in context: IntegrationNotesContext) async -> IntegrationNote {
        await context.store.insert(title: title, body: body, tags: tags ?? [])
    }
}

/// Reads one note by id.
@Generable
@Operation(verb: "get", noun: "note", description: "Fetch one note by its id")
struct IntegrationGetNote {
    @Guide(description: "The id of the note")
    var id: String
}

extension IntegrationGetNote {
    /// Finds the note.
    ///
    /// - Parameter context: The environment with the store.
    /// - Returns: The note.
    /// - Throws: ``IntegrationNotesError/notFound(id:)`` when no note has the id.
    func execute(in context: IntegrationNotesContext) async throws -> IntegrationNote {
        try IntegrationNotesStore.requiring(await context.store.find(id: id), id: id)
    }
}

/// Lists every note. A unit struct: the operation has no parameters.
@Generable
@Operation(verb: "list", noun: "note", description: "List every stored note, to count them or to show them all")
struct IntegrationListNotes {
}

extension IntegrationListNotes {
    /// Reads every note, in insertion order.
    ///
    /// - Parameter context: The environment with the store.
    /// - Returns: The notes.
    func execute(in context: IntegrationNotesContext) async -> [IntegrationNote] {
        await context.store.list()
    }
}

/// Deletes one note by id.
@Generable
@Operation(verb: "delete", noun: "note", description: "Delete one note by its id")
struct IntegrationDeleteNote {
    @Guide(description: "The id of the note")
    var id: String
}

extension IntegrationDeleteNote {
    /// Removes the note and returns it as it was.
    ///
    /// - Parameter context: The environment with the store.
    /// - Returns: The removed note.
    /// - Throws: ``IntegrationNotesError/notFound(id:)`` when no note has the id.
    func execute(in context: IntegrationNotesContext) async throws -> IntegrationNote {
        try IntegrationNotesStore.requiring(await context.store.remove(id: id), id: id)
    }
}

/// Attaches tags to one note.
@Generable
@Operation(verb: "tag", noun: "note", description: "Attach tags or labels to an existing note by its id")
struct IntegrationTagNote {
    @Guide(description: "The id of the note")
    var id: String

    @Guide(description: "The tags to attach")
    var tags: [String]
}

extension IntegrationTagNote {
    /// Adds the tags and returns the changed note.
    ///
    /// - Parameter context: The environment with the store.
    /// - Returns: The changed note.
    /// - Throws: ``IntegrationNotesError/notFound(id:)`` when no note has the id.
    func execute(in context: IntegrationNotesContext) async throws -> IntegrationNote {
        try IntegrationNotesStore.requiring(await context.store.addTags(tags, toNoteWithID: id), id: id)
    }
}

/// The fused `notes` tool, and the catalog paths of the verbs a test grades.
///
/// A factory and not a stored value: `OperationTool.init` throws, and every
/// test builds the tool over a store of its own, so it reads what its own
/// run stored and nothing another run did.
enum IntegrationNotesTool {
    /// The name of the tool. The registry makes it the group of the verbs,
    /// so every verb path starts with it.
    static let name = "notes"

    /// The description of the fused tool.
    static let description = "Manage the user's notes: add, get, list, delete, and tag them."

    /// The catalog path of the `add note` verb.
    static let addNotePath = "\(name).addNote"

    /// The catalog path of the `list note` verb.
    static let listNotePath = "\(name).listNote"

    /// The catalog path of the `tag note` verb.
    static let tagNotePath = "\(name).tagNote"

    /// Fuses the five operations over `store`.
    ///
    /// - Parameter store: The store every operation of the tool reads and
    ///   changes.
    /// - Returns: The fused tool, ready for `MultiTool.Builder.addTool(_:)`.
    /// - Throws: What `OperationTool.init` throws when the fused schema is
    ///   not valid. The fixed operation set here does not make it throw.
    static func make(store: IntegrationNotesStore) throws -> OperationTool<IntegrationNotesContext> {
        try OperationTool(
            name: name,
            description: description,
            context: IntegrationNotesContext(store: store),
            operations: [
                AnyOperation(IntegrationAddNote.self),
                AnyOperation(IntegrationGetNote.self),
                AnyOperation(IntegrationListNotes.self),
                AnyOperation(IntegrationDeleteNote.self),
                AnyOperation(IntegrationTagNote.self),
            ]
        )
    }
}
