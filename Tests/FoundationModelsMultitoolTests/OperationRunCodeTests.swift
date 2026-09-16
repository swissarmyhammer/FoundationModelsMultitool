import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Coverage for a `runCode` snippet that calls a verb of an `OperationDescribing`
/// tool through the JavaScriptCore interpreter: the preamble binding of
/// `tools.notes.<verb>`, `ToolInvoker.validate` against the schema of that one
/// verb, the `op` key the verb adds, `perform(_:)`, the parsed result, and the
/// error that comes back to the snippet.
///
/// Every case runs against ``NotesOperationTool``
/// (`Fixtures/OperationToolFixtures.swift`), mounted as a standalone tool so
/// its five verbs render under `tools.notes`. The fixture records each payload
/// `perform(_:)` receives beside the `op` of the ambient `ToolContext`, and a
/// case reads that record after the snippet returns.
@Suite("OperationRunCodeTests")
struct OperationRunCodeTests {
    // MARK: - Shared test constants

    /// The group of the verbs, which is the name of the fixture tool.
    private static let notesGroup = "notes"

    /// The verb name of the `tag note` operation.
    private static let tagNoteVerbName = "tagNote"

    /// The journal op of a `tagNote` call: the verb, then the group.
    private static let tagNoteJournalOp = "\(tagNoteVerbName) \(notesGroup)"

    /// The title the `addNote` snippet sends.
    private static let noteTitle = "Plan"

    /// The body the `addNote` snippet sends.
    private static let noteBody = "deadline Friday"

    /// The text the loop snippet looks for in the body of each note.
    private static let bodyFilter = "Friday"

    /// The tag the loop snippet and the journal case add to a note.
    private static let addedTag = "due"

    /// A note id no note has.
    private static let absentNoteID = "missing"

    /// The note id of the validation case. The fixture never sees it, because
    /// the payload has no `tag`.
    private static let unreachedNoteID = "note-1"

    /// The word the catch-all branch of a snippet returns when the awaited
    /// call did not reject.
    private static let unreachableMarker = "unreachable"

    /// The notes the list cases seed, as title and body pairs. Two bodies hold
    /// ``bodyFilter`` and one does not, so the loop has hits and a miss.
    private static let seededNotes: [(title: String, body: String)] = [
        (noteTitle, noteBody),
        ("Groceries", "milk and eggs"),
        ("Standup", "Friday agenda"),
    ]

    /// The exact `TypeError` text JavaScriptCore gives for a call on the
    /// `tools.notes` namespace. The search-and-hints card reads this text.
    private static let namespaceCallTypeErrorMessage =
        #"tools.notes is not a function. (In 'tools.notes({ op: "add note", title: "x" })', 'tools.notes' is an instance of Object)"#

    // MARK: - What a snippet reports back

    /// What the list snippet reports about the value `listNote` gave it.
    private struct ListReport: Decodable {
        /// Whether `Array.isArray` accepted the value.
        let isArray: Bool

        /// The `length` of the value.
        let count: Int
    }

    /// What the plain-text snippet reports about the value `deleteNote` gave it.
    private struct TextReport: Decodable {
        /// The `typeof` of the value.
        let kind: String

        /// The value itself.
        let text: String
    }

    /// What a snippet reports about an error it caught.
    private struct CaughtError: Decodable {
        /// The `name` of the error.
        let name: String

        /// Whether `instanceof TypeError` accepted the error.
        let isTypeError: Bool

        /// The `message` of the error.
        let message: String
    }

    // MARK: - Helpers

    /// A `runCode` tool over a registry that holds `parent` as a standalone tool.
    ///
    /// - Parameter parent: The fixture tool.
    /// - Returns: The `runCode` tool.
    /// - Throws: What `buildRegistry()` throws.
    private static func makeMultiTool(over parent: NotesOperationTool) throws -> MultiTool {
        MultiTool(registry: try MultiTool.Builder().addTool(parent).buildRegistry())
    }

    /// Runs one snippet over a registry that holds `parent`, with no ambient context.
    ///
    /// - Parameters:
    ///   - code: The snippet to run.
    ///   - parent: The fixture tool.
    /// - Returns: The rendered output of `runCode`.
    /// - Throws: What `MultiTool.call(arguments:)` throws.
    private static func run(_ code: String, over parent: NotesOperationTool) async throws -> String {
        try await makeMultiTool(over: parent).call(arguments: RunCodeArguments(code: code))
    }

    /// The rendered output of `runCode`, decoded as JSON.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - output: The rendered output.
    /// - Returns: The decoded value.
    /// - Throws: What `JSONDecoder` throws.
    private static func decode<Value: Decodable>(_ type: Value.Type, from output: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(output.utf8))
    }

    /// Adds `notes` to the store of `parent` through `perform(_:)`, outside
    /// any snippet, so a case starts with notes to list.
    ///
    /// - Parameters:
    ///   - parent: The fixture tool.
    ///   - notes: The title and body of each note.
    /// - Throws: What `perform(_:)` throws.
    private static func seed(_ parent: NotesOperationTool, with notes: [(title: String, body: String)]) async throws {
        for note in notes {
            _ = try await parent.perform(
                GeneratedContent(properties: [
                    NotesOperationTool.opParameter: NotesOperationTool.addNoteOp,
                    NotesOperationTool.titleParameter: note.title,
                    NotesOperationTool.bodyParameter: note.body,
                ]))
        }
    }

    /// A snippet that awaits `call`, returns `e.message` when the call
    /// rejects, and returns ``unreachableMarker`` when it does not.
    ///
    /// - Parameter call: The JavaScript expression to await.
    /// - Returns: The snippet.
    private static func catchingSnippet(awaiting call: String) -> String {
        """
        try {
          await \(call);
          return "\(unreachableMarker)";
        } catch (e) {
          return e.message;
        }
        """
    }

    // MARK: - Snippet 1: addNote

    @Test("tools.notes.addNote returns the note the store assigned, and the fixture saw one payload with op, title and body")
    func addNoteReachesTheFixtureWithTheOpKey() async throws {
        let parent = NotesOperationTool()

        let output = try await Self.run(
            """
            const n = await tools.notes.addNote({ title: "\(Self.noteTitle)", body: "\(Self.noteBody)" });
            return n.id;
            """,
            over: parent)

        let stored = try #require(parent.notes.first)
        #expect(try Self.decode(String.self, from: output) == stored.id)
        let recorded = try #require(parent.recordedCalls.first)
        #expect(parent.recordedCalls.count == 1)
        // The verb puts `op` first. The keys after it come from the marshaled
        // JavaScript object, whose order the marshaler does not keep, so the
        // rest of the payload is checked as a set.
        let keys = try #require(TestSupport.propertyNames(of: recorded.payload))
        #expect(keys.first == NotesOperationTool.opParameter)
        #expect(
            Set(keys) == [
                NotesOperationTool.opParameter, NotesOperationTool.titleParameter, NotesOperationTool.bodyParameter,
            ])
        #expect(recorded.string(NotesOperationTool.opParameter) == NotesOperationTool.addNoteOp)
        #expect(recorded.string(NotesOperationTool.titleParameter) == Self.noteTitle)
        #expect(recorded.string(NotesOperationTool.bodyParameter) == Self.noteBody)
    }

    // MARK: - Snippet 2: listNote

    @Test("tools.notes.listNote gives the snippet an array, and its length is a number")
    func listNoteGivesAnArray() async throws {
        let parent = NotesOperationTool()
        try await Self.seed(parent, with: Self.seededNotes)

        let output = try await Self.run(
            """
            const all = await tools.notes.listNote({});
            return { isArray: Array.isArray(all), count: all.length };
            """,
            over: parent)

        let report = try Self.decode(ListReport.self, from: output)
        #expect(report.isArray)
        #expect(report.count == Self.seededNotes.count)
    }

    // MARK: - Snippet 3: the loop

    @Test("a loop that lists, filters on body and tags each hit sends op: tag note on every tagNote payload")
    func loopTagsEachHitThroughTheVerb() async throws {
        let parent = NotesOperationTool()
        try await Self.seed(parent, with: Self.seededNotes)
        let hits = parent.notes.filter { $0.body.contains(Self.bodyFilter) }

        let output = try await Self.run(
            """
            const all = await tools.notes.listNote({});
            let count = 0;
            for (const note of all) {
              if (note.body.includes("\(Self.bodyFilter)")) {
                await tools.notes.tagNote({ id: note.id, tag: "\(Self.addedTag)" });
                count += 1;
              }
            }
            return count;
            """,
            over: parent)

        #expect(try Self.decode(Int.self, from: output) == hits.count)
        let tagCalls = parent.recordedCalls(withOp: NotesOperationTool.tagNoteOp)
        #expect(tagCalls.count == hits.count)
        #expect(tagCalls.map { $0.string(NotesOperationTool.idParameter) } == hits.map(\.id))
        #expect(tagCalls.allSatisfy { $0.string(NotesOperationTool.tagParameter) == Self.addedTag })
        let tagged = parent.notes.filter { $0.tags.contains(Self.addedTag) }
        #expect(tagged.map(\.id) == hits.map(\.id))
    }

    // MARK: - Snippet 4: validation before the fixture

    @Test("tools.notes.tagNote with no tag rejects before the fixture sees a payload, and the text names the missing parameter")
    func missingRequiredParameterRejectsBeforeTheFixture() async throws {
        let parent = NotesOperationTool()

        let output = try await Self.run(
            Self.catchingSnippet(awaiting: #"tools.notes.tagNote({ id: "\#(Self.unreachedNoteID)" })"#),
            over: parent)

        let message = try Self.decode(String.self, from: output)
        #expect(message != Self.unreachableMarker)
        #expect(message.contains("\"\(NotesOperationTool.tagParameter)\""), "message was: \(message)")
        #expect(parent.recordedCalls.isEmpty)
    }

    // MARK: - Snippet 5: the fixture throws

    @Test("an error perform throws reaches the snippet as a rejection whose message holds the fixture's error text")
    func performErrorReachesTheSnippet() async throws {
        let parent = NotesOperationTool()

        let output = try await Self.run(
            Self.catchingSnippet(awaiting: #"tools.notes.getNote({ id: "\#(Self.absentNoteID)" })"#),
            over: parent)

        let message = try Self.decode(String.self, from: output)
        let fixtureText = String(describing: NotesOperationError.missingNote(id: Self.absentNoteID))
        #expect(message.contains(fixtureText), "message was: \(message)")
        #expect(parent.recordedCalls.count == 1)
    }

    // MARK: - Snippet 6: plain text

    @Test("a verb that answers plain text gives the snippet a string")
    func plainTextAnswerIsAString() async throws {
        let parent = NotesOperationTool()
        try await Self.seed(parent, with: [Self.seededNotes[0]])
        let stored = try #require(parent.notes.first)

        let output = try await Self.run(
            """
            const r = await tools.notes.deleteNote({ id: "\(stored.id)" });
            return { kind: typeof r, text: r };
            """,
            over: parent)

        let report = try Self.decode(TextReport.self, from: output)
        #expect(report.kind == "string")
        #expect(report.text == NotesOperationTool.deletionMessage(for: stored.id))
        #expect(parent.notes.isEmpty)
    }

    // MARK: - Snippet 7: a call on the namespace

    @Test("tools.notes({ op }) is a TypeError in the snippet, and the fixture is not reached")
    func callOnTheNamespaceIsATypeError() async throws {
        let parent = NotesOperationTool()

        let output = try await Self.run(
            """
            try {
              await tools.notes({ op: "add note", title: "x" });
              return "\(Self.unreachableMarker)";
            } catch (e) {
              return { name: e.name, isTypeError: e instanceof TypeError, message: e.message };
            }
            """,
            over: parent)

        let caught = try Self.decode(CaughtError.self, from: output)
        #expect(caught.isTypeError)
        #expect(caught.name == "TypeError")
        #expect(caught.message == Self.namespaceCallTypeErrorMessage)
        #expect(parent.recordedCalls.isEmpty)
    }

    // MARK: - The journal op

    @Test("under a RunBinding, a tagNote call reaches the fixture stamped with the op \"tagNote notes\"")
    func tagNoteCallCarriesTheJournalOp() async throws {
        let parent = NotesOperationTool()
        try await Self.seed(parent, with: [Self.seededNotes[0]])
        let stored = try #require(parent.notes.first)
        let multiTool = try Self.makeMultiTool(over: parent)
        let context = try await makeOuterRunContext()

        _ = try await ToolContext.$current.withValue(context) {
            try await multiTool.call(
                arguments: RunCodeArguments(
                    code: #"return await tools.notes.tagNote({ id: "\#(stored.id)", tag: "\#(Self.addedTag)" });"#))
        }

        let tagCall = try #require(parent.recordedCalls(withOp: NotesOperationTool.tagNoteOp).first)
        #expect(tagCall.contextOp == Self.tagNoteJournalOp)
    }
}
