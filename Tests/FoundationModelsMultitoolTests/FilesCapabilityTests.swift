import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Coverage for `FilesCapability` and for `MultiTool.Builder.withFiles(...)` —
/// eventplan.md § "Registration of capabilities: noun/verb": *"The Builder opts
/// modules in explicitly: `withShell()`, `withFiles(root:)`..."*.
///
/// Three properties carry this suite, and each one is a sentence of
/// eventplan.md § "The capability contract":
///
/// 1. The capability owns ONE noun and renders exactly six verbs under it.
/// 2. Files is OFF by default: a builder that never calls `withFiles(root:)`
///    renders no entry under that noun at all, and a second registration of
///    the noun fails loudly at `buildRegistry()`.
/// 3. The six verbs reach every discovery surface alike — `searchTools`,
///    `help()` and `docs(name)` — because all six read the one `APISurface`
///    the builder rendered.
///
/// Each test that touches the disk roots its context in a temporary directory
/// of its own, thus the tests are independent and they run in parallel safely.
/// The one behavioral test here is the shared-context proof — a
/// `tools.files.write` result is visible to a following `tools.files.read` —
/// and the `FilesReadTests` through `FilesGrepTests` suites prove the behavior
/// of each verb.
@Suite("FilesCapabilityTests")
struct FilesCapabilityTests {

    /// The name of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryName = "FilesCapabilityTests"

    /// The one noun this capability owns.
    private static let filesNoun = "files"

    /// The verbs the capability holds, in the order they render. Each one is a
    /// `Tool.name`, which is the second segment of `tools.<noun>.<verb>`.
    private static let filesVerbs = ["read", "write", "edit", "patch", "glob", "grep"]

    /// The rendered call path of each verb, built from the two segments rather
    /// than written out again, thus the noun and the verbs have one home here.
    private static let filesPaths = filesVerbs.map { "\(filesNoun).\($0)" }

    /// How many verbs the capability renders. The card ^3gzc6an fixes the
    /// count at six: the two content reads, the three mutations, and the two
    /// searches make read, write, edit, patch, glob, and grep.
    private static let verbCount = 6

    /// The first segment of every path the capability claims, with its
    /// separator. A builder that never registered the capability renders no
    /// path that opens with it.
    private static let filesPathPrefix = "\(filesNoun)."

    /// The rendered call path of the one tool the off-by-default test registers
    /// instead, which proves that test reads a surface that was really built.
    private static let unrelatedToolPath = "getWeather"

    /// The content the shared-context proof writes and reads back.
    private static let sharedContextContent = "alpha\nbeta\n"

    /// The plain-language goal the discovery test searches for.
    private static let filesTask = "read a file, change it, and search the tree"

    /// What the scripted selection tier answers: every files verb, by its
    /// rendered path. Built from ``filesPaths`` so a verb added or taken away
    /// moves the reply with it.
    private static var selectionReply: String {
        let ids = filesPaths.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"ids\":[\(ids)]}"
    }

    // MARK: - The ground of one test

    /// A session root directory this test owns.
    ///
    /// - Returns: A directory no other test shares.
    private func makeRoot() -> URL {
        TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
    }

    /// The capability over a root this test owns.
    ///
    /// - Returns: The capability.
    private func makeCapability() -> FilesCapability {
        FilesCapability(root: makeRoot())
    }

    /// A registry holding the files capability and nothing else.
    ///
    /// - Returns: The registry.
    /// - Throws: When the surface does not render.
    private func makeFilesRegistry() throws -> MultiTool.Registry {
        try MultiTool.Builder()
            .withFiles(root: makeRoot())
            .buildRegistry()
    }

    /// The one verb of `capability` that is a `Verb`.
    ///
    /// Read by type rather than by position, thus a test states which verb it
    /// means and no test indexes into the array.
    ///
    /// - Parameters:
    ///   - kind: The verb type to find.
    ///   - capability: The capability to read.
    /// - Returns: That verb.
    /// - Throws: When the capability holds no such verb.
    private static func verb<Verb: Tool>(
        _ kind: Verb.Type, in capability: FilesCapability
    ) throws -> Verb {
        try #require(capability.tools.compactMap { $0 as? Verb }.first)
    }

    // MARK: - The noun and its verbs

    /// eventplan.md § "Registration of capabilities: noun/verb": a capability
    /// is a noun plus its tools, and nothing else. The capability supplies the
    /// first segment one time, and each verb supplies the second.
    @Test("the capability owns the files noun and holds exactly its six verbs")
    func theCapabilityOwnsTheFilesNounAndHoldsItsSixVerbs() throws {
        let capability = makeCapability()

        #expect(capability.noun == Self.filesNoun)
        #expect(capability.tools.count == Self.verbCount)
        #expect(capability.tools.map { $0.name } == Self.filesVerbs)
    }

    /// The six verbs answer for one session, because each one holds the one
    /// `FileContext` the capability made — the promise each verb's own doc
    /// comment makes: "the context it reads against is the context the files
    /// capability owns". A context for each verb would make `read` blind to
    /// what `write` just wrote.
    @Test("the six verbs hold one session context")
    func theSixVerbsHoldOneSessionContext() throws {
        let capability = makeCapability()

        let read = try Self.verb(Read.self, in: capability)
        let write = try Self.verb(Write.self, in: capability)
        let edit = try Self.verb(Edit.self, in: capability)
        let patch = try Self.verb(Patch.self, in: capability)
        let glob = try Self.verb(Glob.self, in: capability)
        let grep = try Self.verb(Grep.self, in: capability)

        #expect(read.context === write.context)
        #expect(write.context === edit.context)
        #expect(edit.context === patch.context)
        #expect(patch.context === glob.context)
        #expect(glob.context === grep.context)
    }

    /// The shared-context proof in behavior: what `tools.files.write` writes,
    /// a following `tools.files.read` reads back — the same bytes, the same
    /// freshness hash, and the same hashline-tagged lines.
    @Test("a write result is visible to a following read")
    func aWriteResultIsVisibleToAFollowingRead() async throws {
        let root = makeRoot()
        let capability = FilesCapability(root: root)
        let path = root.appendingPathComponent("note.txt", isDirectory: false).path

        let write = try Self.verb(Write.self, in: capability)
        let read = try Self.verb(Read.self, in: capability)

        let writeResult = try await write.call(
            arguments: WriteArguments(path: path, content: Self.sharedContextContent))
        let readResult = try await read.call(
            arguments: ReadArguments(path: path, offset: nil, limit: nil, format: nil))

        #expect(writeResult.correction == nil)
        #expect(readResult.correction == nil)
        #expect(readResult.hash == writeResult.hash)
        #expect(readResult.lines == writeResult.taggedContent)
    }

    /// The initializer's session settings reach the one context every verb
    /// holds, thus a host that asks for a read-only session gets one on every
    /// mutating verb at once.
    @Test("the session settings reach the one context of the verbs")
    func theSessionSettingsReachTheOneContext() throws {
        let root = makeRoot()

        let capability = FilesCapability(root: root, readOnly: true)

        let read = try Self.verb(Read.self, in: capability)
        #expect(read.context.root == root)
        #expect(read.context.readOnly)
    }

    // MARK: - The rendered surface

    /// eventplan.md § "Registration of capabilities: noun/verb": each entry is
    /// `tools.<noun>.<verb>`, and it has two segments. `withFiles(root:)` is
    /// the short form of `withCapability(FilesCapability(...))`, so it renders
    /// the same six paths that capability holds — and nothing else under the
    /// noun.
    @Test("withFiles renders exactly the six files verbs")
    func withFilesRendersExactlyTheSixVerbs() throws {
        let registry = try makeFilesRegistry()

        let paths = registry.surface.entries.map(\.path)

        #expect(paths == Self.filesPaths)
        #expect(Set(paths).count == Self.verbCount)
    }

    /// eventplan.md § "The capability contract": "The modules are opt-in ...
    /// They are off by default." A builder that never asked for the files
    /// capability claims no part of that namespace.
    @Test("a builder with no withFiles renders no entry under the files noun")
    func aBuilderWithNoWithFilesRendersNoFilesEntry() throws {
        let surface = try MultiTool.Builder().addTool(WeatherTool()).build()

        // The unrelated tool proves the surface was really built, thus the two
        // expectations below read an answer rather than an empty catalog.
        #expect(surface.entries.map(\.path) == [Self.unrelatedToolPath])
        #expect(!surface.entries.contains { $0.path.hasPrefix(Self.filesPathPrefix) })
        #expect(!surface.entries.contains { $0.path == Self.filesNoun })
    }

    /// eventplan.md § "Registration of capabilities: noun/verb": "Nouns are
    /// unique. Registration rejects a duplicate noun. An MCP server with the
    /// name `files`, against the files capability, fails loudly at
    /// `buildRegistry()`." The server registers through the primitive
    /// `register(noun:tool:)`, and its verb is its own.
    @Test("a second registration under the files noun makes buildRegistry() throw")
    func aSecondRegistrationUnderTheFilesNounThrows() throws {
        let root = makeRoot()

        #expect {
            try MultiTool.Builder()
                .withFiles(root: root)
                .register(noun: Self.filesNoun, tool: WeatherTool())
                .buildRegistry()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .duplicateNoun && builderError.name == Self.filesNoun
        }
    }

    /// A second files capability is the other shape of the same failure. Its
    /// verbs collide path by path, so `buildRegistry()` reports the first path
    /// collision — loudly, and never a quiet merge.
    @Test("a second withFiles registration makes buildRegistry() throw")
    func aSecondWithFilesRegistrationThrows() throws {
        let root = makeRoot()

        #expect {
            try MultiTool.Builder()
                .withFiles(root: root)
                .withFiles(root: root)
                .buildRegistry()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .duplicateName
                && builderError.name == Self.filesVerbs.first
        }
    }

    // MARK: - Discovery

    /// eventplan.md § "Registration of capabilities: noun/verb": "The path, the
    /// `findAPIs` result, the `help()` entry ... all come from the one pair."
    /// `findAPIs` ships as `searchTools`, and the answer it formats carries each
    /// matched entry's verbatim block plus that entry's runnable example,
    /// qualified with the noun so a model can call it as written.
    @Test("searchTools finds each files verb, with the runnable example of that verb")
    func searchToolsFindsEachFilesVerbWithItsRunnableExample() async throws {
        let surface = try MultiTool.Builder()
            .withFiles(root: makeRoot())
            .build()
        let selection = RootSessionRespondCalledDirectlySession(
            forkResponses: [Self.selectionReply])
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .auto,
            selection: SelectionConfig(model: { _, _ in selection }, capacityCharacterLimit: .max)
        )
        let searchTools = SearchToolsTool(searcher: searcher, limit: surface.entries.count)

        let feedback = try await searchTools.call(
            arguments: SearchToolsArguments(task: Self.filesTask))

        for path in Self.filesPaths {
            let entry = try #require(surface.entries.first { $0.path == path })
            #expect(feedback.contains(entry.block), "feedback was: \(feedback)")
            #expect(feedback.contains("Example: \(entry.qualifiedExample)"))
            #expect(entry.qualifiedExample.hasPrefix("await tools.\(path)("))
        }
    }

    /// `help()` reads the same rendered surface, so it names each verb by its
    /// qualified path.
    @Test("help() renders the six files verbs")
    func helpRendersTheSixFilesVerbs() async throws {
        let multiTool = MultiTool(registry: try makeFilesRegistry())

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return help();"))

        let paths = try JSONDecoder().decode([String].self, from: Data(output.utf8))
        #expect(paths == Self.filesPaths)
    }

    /// `docs(name)` hands back the entry's own rendered block, unchanged. Thus
    /// a snippet reads the same text discovery read, and the two can never
    /// describe a verb differently.
    @Test("docs() renders the block of each files verb")
    func docsRendersTheBlockOfEachFilesVerb() async throws {
        let registry = try makeFilesRegistry()
        let multiTool = MultiTool(registry: registry)

        for path in Self.filesPaths {
            let entry = try #require(registry.surface.entries.first { $0.path == path })

            let output = try await multiTool.call(
                arguments: RunCodeArguments(code: "return docs('\(path)');"))

            let rendered = try JSONDecoder().decode(String.self, from: Data(output.utf8))
            #expect(rendered == entry.block)
        }
    }
}
