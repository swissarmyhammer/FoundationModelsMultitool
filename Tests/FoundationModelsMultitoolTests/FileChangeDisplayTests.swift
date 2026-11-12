// `FileChangeDisplayTests` — the mutating file verbs post one display diff for
// each changed file.
//
// The request: when the agent writes or edits a file, the chat of the client
// must show the diff of the change, not only a text result. Thus each
// mutating verb posts one `ToolDisplayEvent` with a `.contentChunk` that holds
// `ToolDisplayContent.diff(path:oldText:newText:)` for each changed file,
// through the ambient `ToolContext` of its call. The verb does this also when
// the session does not record changes. A call that changes no file posts no
// diff.
//
// Each test mounts a verb on the context of a stub run, with a
// `RecordingEventSink`, and reads the display events of that sink. No test
// uses a clock: a synchronous call posts its display events before it
// returns.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the display diff of the mutating file verbs.
@Suite("FileChangeDisplayTests", .ownsTemporaryDirectories)
struct FileChangeDisplayTests {

    /// The name of the temporary directory of one test.
    private static let testDirectoryName = "FileChangeDisplayTests"

    /// The content that the write tests write.
    private static let writtenContent = "hello\n"

    /// The content that the edit tests seed.
    private static let editedBefore = "one\ntwo\n"

    /// The content that the edit test expects after the change.
    private static let editedAfter = "one\nTWO\n"

    // MARK: - The ground of one test

    /// A stub run, a files capability over a root that this test owns, and
    /// the sink that each mounted verb posts to.
    private struct Ground {
        /// The stub session and its context.
        let run: StubRun

        /// The capability that the verbs come from.
        let capability: FilesCapability

        /// The canonical session root.
        let root: URL

        /// The sink of each mounted verb.
        let sink: RecordingEventSink

        /// The absolute path of `name` under the root.
        ///
        /// - Parameter name: the file name relative to the root.
        /// - Returns: the absolute path.
        func path(_ name: String) -> String {
            TestSupport.path(name, in: root)
        }
    }

    /// Builds the ground and gives it to `body`. Closes the session of the
    /// stub run on each path.
    ///
    /// - Parameters:
    ///   - files: the file names and UTF-8 contents to seed under the root.
    ///   - readOnly: whether the capability forbids the mutating verbs.
    ///   - recordsChanges: whether the journal of the capability records.
    ///   - body: the work that uses the ground.
    /// - Throws: a seed-write failure, a stub-run failure, or what `body`
    ///   throws.
    private static func withGround(
        seeding files: [(name: String, contents: String)] = [],
        readOnly: Bool = false,
        recordsChanges: Bool = false,
        _ body: (Ground) async throws -> Void
    ) async throws {
        let root = TestSupport.canonicalDirectory(
            TestSupport.makeTemporaryDirectory(named: testDirectoryName))
        for file in files {
            try Data(file.contents.utf8).write(
                to: root.appendingPathComponent(file.name, isDirectory: false))
        }
        let capability = FilesCapability(root: root, readOnly: readOnly, recordsChanges: recordsChanges)
        try await withStubRun { run in
            try await body(
                Ground(run: run, capability: capability, root: root, sink: RecordingEventSink()))
        }
    }

    /// The verb of the capability of type `Verb`, mounted as a synchronous
    /// tool that posts to the sink of the ground.
    ///
    /// - Parameters:
    ///   - kind: the verb type to mount.
    ///   - ground: the ground whose capability, context and sink to use.
    /// - Returns: the mounted verb.
    /// - Throws: when the capability holds no such verb.
    private static func mounted<Verb: Tool>(
        _ kind: Verb.Type, in ground: Ground
    ) throws -> any Tool<Verb.Arguments, Verb.Output> {
        let verb = try #require(ground.capability.tools.compactMap { $0 as? Verb }.first)
        return ground.run.context.mount(verb, as: .synchronous, postingTo: ground.sink)
    }

    /// The display contents that the sink of the ground got, in order.
    ///
    /// - Parameter ground: the ground whose sink to read.
    /// - Returns: the content of each `.contentChunk` display event.
    private static func displayedContents(in ground: Ground) async -> [ToolDisplayContent] {
        await ground.sink.displayEvents.compactMap { event in
            guard case .contentChunk(let content) = event.kind else { return nil }
            return content
        }
    }

    // MARK: - The write verb

    @Test("a write of a new file posts one diff with no old text")
    func writeOfANewFilePostsADiffWithNoOldText() async throws {
        try await Self.withGround { ground in
            let path = ground.path("new.txt")
            let result = try await Self.mounted(Write.self, in: ground)
                .call(arguments: WriteArguments(path: path, content: Self.writtenContent))

            #expect(result.correction == nil)
            #expect(
                await Self.displayedContents(in: ground) == [
                    .diff(path: path, oldText: nil, newText: Self.writtenContent)
                ])
        }
    }

    @Test("a write over a file posts one diff with the old and the new text")
    func writeOverAFilePostsADiffWithBothTexts() async throws {
        try await Self.withGround(seeding: [("old.txt", Self.editedBefore)]) { ground in
            let path = ground.path("old.txt")
            let result = try await Self.mounted(Write.self, in: ground)
                .call(arguments: WriteArguments(path: path, content: Self.writtenContent))

            #expect(result.correction == nil)
            #expect(
                await Self.displayedContents(in: ground) == [
                    .diff(path: path, oldText: Self.editedBefore, newText: Self.writtenContent)
                ])
        }
    }

    @Test("a failed write in a read-only session posts no diff")
    func failedWritePostsNoDiff() async throws {
        try await Self.withGround(readOnly: true) { ground in
            let result = try await Self.mounted(Write.self, in: ground)
                .call(arguments: WriteArguments(path: ground.path("new.txt"), content: Self.writtenContent))

            #expect(result.correction != nil)
            #expect(await ground.sink.displayEvents.isEmpty)
        }
    }

    @Test("a write to a path outside the root posts no diff")
    func writeOutsideTheRootPostsNoDiff() async throws {
        try await Self.withGround { ground in
            let outside = ground.root.deletingLastPathComponent()
                .appendingPathComponent("outside-\(UUID().uuidString).txt").path
            let result = try await Self.mounted(Write.self, in: ground)
                .call(arguments: WriteArguments(path: outside, content: Self.writtenContent))

            #expect(result.correction != nil)
            #expect(await ground.sink.displayEvents.isEmpty)
        }
    }

    // MARK: - The edit verb

    @Test("an edit posts one diff with the old and the new text")
    func editPostsADiffWithBothTexts() async throws {
        try await Self.withGround(seeding: [("code.txt", Self.editedBefore)]) { ground in
            let path = ground.path("code.txt")
            let result = try await Self.mounted(Edit.self, in: ground)
                .call(
                    arguments: EditArguments(
                        path: path, find: ["two"], replace: ["TWO"], replacesAll: nil, occurrence: nil))

            #expect(result.correction == nil)
            #expect(
                await Self.displayedContents(in: ground) == [
                    .diff(path: path, oldText: Self.editedBefore, newText: Self.editedAfter)
                ])
        }
    }

    @Test("an edit that finds no match posts no diff")
    func unresolvedEditPostsNoDiff() async throws {
        try await Self.withGround(seeding: [("code.txt", Self.editedBefore)]) { ground in
            _ = try await Self.mounted(Edit.self, in: ground)
                .call(
                    arguments: EditArguments(
                        path: ground.path("code.txt"), find: ["absent"], replace: ["x"], replacesAll: nil,
                        occurrence: nil))

            #expect(await ground.sink.displayEvents.isEmpty)
        }
    }

    // MARK: - The patch verb

    @Test("a patch of four files posts one diff for each file, in order")
    func patchPostsOneDiffForEachFile() async throws {
        try await Self.withGround(seeding: [
            ("update.txt", "one\ntwo\n"),
            ("delete.txt", "obsolete\n"),
            ("source.txt", "keep me\n"),
        ]) { ground in
            let envelope = """
                *** Begin Patch
                *** Add File: \(ground.path("added.txt"))
                +added
                *** Update File: \(ground.path("update.txt"))
                *** Find:
                two
                *** Replace:
                TWO
                *** Delete File: \(ground.path("delete.txt"))
                *** Update File: \(ground.path("source.txt"))
                *** Move to: \(ground.path("dest.txt"))
                *** End Patch

                """
            let result = try await Self.mounted(Patch.self, in: ground)
                .call(arguments: PatchArguments(patch: envelope))

            #expect(result.correction == nil)
            #expect(
                await Self.displayedContents(in: ground) == [
                    .diff(path: ground.path("added.txt"), oldText: nil, newText: "added\n"),
                    .diff(path: ground.path("update.txt"), oldText: "one\ntwo\n", newText: "one\nTWO\n"),
                    .diff(path: ground.path("delete.txt"), oldText: "obsolete\n", newText: ""),
                    .diff(path: ground.path("dest.txt"), oldText: "keep me\n", newText: "keep me\n"),
                ])
        }
    }

    // MARK: - The delete verb

    @Test("a delete posts one diff with the old text and an empty new text")
    func deletePostsADiffWithAnEmptyNewText() async throws {
        try await Self.withGround(seeding: [("gone.txt", Self.editedBefore)]) { ground in
            let path = ground.path("gone.txt")
            let result = try await Self.mounted(Delete.self, in: ground)
                .call(arguments: DeleteArguments(path: path, directory: nil))

            #expect(result.correction == nil)
            #expect(
                await Self.displayedContents(in: ground) == [
                    .diff(path: path, oldText: Self.editedBefore, newText: "")
                ])
        }
    }

    // MARK: - Recording and the run

    @Test("a recording session posts the same diff, and the stamps of the run")
    func recordingSessionPostsTheDiffWithTheStampsOfTheRun() async throws {
        try await Self.withGround(recordsChanges: true) { ground in
            let path = ground.path("new.txt")
            _ = try await Self.mounted(Write.self, in: ground)
                .call(arguments: WriteArguments(path: path, content: Self.writtenContent))

            let events = await ground.sink.displayEvents
            #expect(events.count == 1)
            let event = try #require(events.first)
            #expect(event.kind == .contentChunk(.diff(path: path, oldText: nil, newText: Self.writtenContent)))
            let write = try #require(ground.capability.tools.compactMap { $0 as? Write }.first)
            #expect(event.tool == write.name)
            #expect(await ground.sink.events.contains { $0.correlationID == event.correlationID })
        }
    }

    @Test("a write in a runCode snippet posts its diff under the runCode run")
    func writeInARunCodeSnippetPostsTheDiffUnderTheRun() async throws {
        try await Self.withGround { ground in
            let path = ground.path("snippet.txt")
            let registry = try MultiTool.Builder(mode: .open).withFiles(root: ground.root).buildRegistry()
            let multiTool = MultiTool(registry: registry)
            let mounted = ground.run.context.mount(multiTool, as: .synchronous, postingTo: ground.sink)
            _ = try await mounted.call(
                arguments: RunCodeArguments(
                    code: """
                        const written = await tools.files.write({ path: "snippet.txt", content: "hello\\n" });
                        return written.correction ?? "ok";
                        """))

            let events = await ground.sink.displayEvents
            #expect(events.map(\.kind) == [.contentChunk(.diff(path: path, oldText: nil, newText: Self.writtenContent))])
            #expect(events.first?.tool == multiTool.name)
        }
    }
}
