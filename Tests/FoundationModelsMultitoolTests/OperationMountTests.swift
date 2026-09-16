import Foundation
import FoundationModelsExtras
import Testing

import FoundationModels
@testable import FoundationModelsMultitool

/// Coverage for the mount of an `OperationDescribing` tool in
/// `MultiTool.RegistrySource.buildRegistry()`: one verb for each operation,
/// under the group the registration gives, and no fused `tools.notes({op})`
/// entry beside them.
///
/// Every case runs against ``NotesOperationTool``
/// (`Fixtures/OperationToolFixtures.swift`), a hand-conformed parent with five
/// notes operations over an in-memory store.
@Suite("OperationMountTests")
struct OperationMountTests {
    // MARK: - Shared test constants

    /// The golden of the five-verb fixture mounted as a standalone tool.
    private static let operationGoldenName = "OperationSurface.ts.txt"

    /// The directory of the goldens, from the repository root.
    private static let goldensDirectory = "Tests/FoundationModelsMultitoolTests/Goldens"

    /// The verb names of the five operations, in descriptor order.
    private static let verbNames = ["addNote", "getNote", "listNote", "deleteNote", "tagNote"]

    /// The name of the fixture tool, which is the group of its verbs when
    /// the tool is standalone.
    private static let notesGroup = "notes"

    /// The group name of the `addGroup(named:_:)` case.
    private static let codeGroup = "code"

    /// The noun of the capability case. It differs from the tool name, so
    /// the case shows that the noun wins.
    private static let memoNoun = "memo"

    /// A tool name that is not a legal TypeScript identifier.
    private static let illegalToolName = "bad-name"

    /// The verb name the duplicate case reports.
    private static let addNoteVerbName = "addNote"

    /// The path of the `add note` verb of a standalone fixture.
    private static let addNotePath = "\(notesGroup).\(addNoteVerbName)"

    /// The path of the `list note` verb of a standalone fixture.
    private static let listNotePath = "\(notesGroup).listNote"

    /// The title the rebuild case adds.
    private static let noteTitle = "kept across the rebuild"

    // MARK: - Helpers

    /// The verb paths under `group`, in descriptor order.
    ///
    /// - Parameter group: The group the verbs render under.
    /// - Returns: One `<group>.<verb>` path for each operation.
    private static func verbPaths(under group: String) -> [String] {
        verbNames.map { "\(group).\($0)" }
    }

    /// The entry paths of `registry`, in surface order.
    ///
    /// - Parameter registry: The registry to read.
    /// - Returns: The paths.
    private static func paths(of registry: MultiTool.Registry) -> [String] {
        registry.surface.entries.map(\.path)
    }

    /// Reads the golden file named `name`, with its trailing newlines trimmed
    /// as the rendered source is trimmed.
    ///
    /// - Parameter name: The file name under `Goldens/`.
    /// - Returns: The golden text.
    /// - Throws: When the file does not read.
    private static func golden(named name: String) throws -> String {
        try RepositoryFile.read(relativePath: "\(goldensDirectory)/\(name)")
            .trimmingCharacters(in: .newlines)
    }

    /// The elements of `content`, or `nil` when `content` is not an array.
    ///
    /// - Parameter content: The content to read.
    /// - Returns: The elements.
    private static func elements(of content: GeneratedContent) -> [GeneratedContent]? {
        guard case .array(let elements) = content.kind else { return nil }
        return elements
    }

    /// The builder error `build` throws, or `nil` when `build` throws
    /// another error or nothing.
    ///
    /// - Parameter build: The build to run.
    /// - Returns: The builder error.
    private static func builderError(of build: () throws -> MultiTool.Registry) -> MultiToolBuilderError? {
        do {
            _ = try build()
            return nil
        } catch {
            return error as? MultiToolBuilderError
        }
    }

    // MARK: - The standalone mount

    @Test("addTool(fixture) mounts one verb for each operation under the tool name, and no fused entry")
    func standaloneMountsTheVerbsUnderTheToolName() throws {
        let registry = try MultiTool.Builder()
            .addTool(NotesOperationTool())
            .buildRegistry()

        #expect(Self.paths(of: registry) == Self.verbPaths(under: Self.notesGroup))
        #expect(registry.tools[Self.notesGroup] == nil)
        #expect(registry.surface.entries.allSatisfy { $0.group == Self.notesGroup })
    }

    @Test("the surface of a standalone operation tool renders byte-identical to the golden file")
    func standaloneSurfaceMatchesGoldenFile() throws {
        let registry = try MultiTool.Builder()
            .addTool(NotesOperationTool())
            .buildRegistry()

        let golden = try Self.golden(named: Self.operationGoldenName)

        #expect(registry.surface.source.trimmingCharacters(in: .newlines) == golden)
    }

    // MARK: - The grouped mount

    @Test("addGroup(named:_:) flattens the verbs into the group, with no tool-name level")
    func groupedMountFlattensTheVerbsIntoTheGroup() throws {
        let registry = try MultiTool.Builder()
            .addGroup(named: Self.codeGroup, [NotesOperationTool()])
            .buildRegistry()

        #expect(Self.paths(of: registry) == Self.verbPaths(under: Self.codeGroup))
        #expect(Self.paths(of: registry).allSatisfy { !$0.contains(".\(Self.notesGroup).") })
    }

    @Test("a capability that holds the fixture mounts the verbs under its noun, and owns that noun")
    func capabilityMountsTheVerbsUnderItsNoun() throws {
        let registry = try MultiTool.Builder()
            .withCapability(FixtureCapability(noun: Self.memoNoun, tools: [NotesOperationTool()]))
            .buildRegistry()

        #expect(Self.paths(of: registry) == Self.verbPaths(under: Self.memoNoun))
        #expect(registry.surface.entries.allSatisfy { $0.group == Self.memoNoun })
    }

    // MARK: - Collisions

    @Test("two operation tools in one group with one shared op string fail with duplicateName, naming the verb")
    func sharedOpStringInOneGroupIsADuplicateName() throws {
        let error = try #require(
            Self.builderError {
                try MultiTool.Builder()
                    .addGroup(named: Self.notesGroup, [NotesOperationTool(), NotesOperationTool()])
                    .buildRegistry()
            })

        #expect(error.kind == .duplicateName)
        #expect(error.name == Self.addNoteVerbName)
        #expect(error.message.contains(Self.addNoteVerbName))
    }

    @Test("a standalone operation tool whose name is not a legal identifier fails with illegalGroupName")
    func illegalToolNameIsAnIllegalGroupName() throws {
        let error = try #require(
            Self.builderError {
                try MultiTool.Builder()
                    .addTool(RenamedNotesOperationTool(name: Self.illegalToolName))
                    .buildRegistry()
            })

        #expect(error.kind == .illegalGroupName)
        #expect(error.name == Self.illegalToolName)
    }

    @Test("a standalone plain tool named like the operation tool fails with duplicateName")
    func plainToolNamedLikeTheOperationToolIsADuplicateName() throws {
        let error = try #require(
            Self.builderError {
                try MultiTool.Builder()
                    .addTool(CatalogEntryTool(name: Self.notesGroup, description: "A plain tool named notes."))
                    .addTool(NotesOperationTool())
                    .buildRegistry()
            })

        #expect(error.kind == .duplicateName)
        #expect(error.name == Self.notesGroup)
    }

    // MARK: - The rebuild

    @Test("rebuildRegistry() keeps the verb paths, and the verbs share the parent store across the rebuild")
    func rebuildKeepsTheVerbsOverTheSameParentStore() async throws {
        let builder = MultiTool.Builder().addTool(NotesOperationTool())
        let first = try builder.buildRegistry()

        let rebuilt = try await builder.rebuildRegistry()

        #expect(Self.paths(of: rebuilt) == Self.paths(of: first))
        let addNote = try #require(first.tools[Self.addNotePath] as? OperationVerbTool)
        _ = try await addNote.call(
            arguments: GeneratedContent(properties: [NotesOperationTool.titleParameter: Self.noteTitle]))
        let listNote = try #require(rebuilt.tools[Self.listNotePath] as? OperationVerbTool)
        let listed = try await listNote.call(arguments: GeneratedContent(properties: [:]))
        let notes = try #require(Self.elements(of: listed), "listed was: \(listed)")
        #expect(notes.count == 1)
        #expect(try notes.first?.value(String.self, forProperty: NotesOperationTool.titleParameter) == Self.noteTitle)
    }
}
