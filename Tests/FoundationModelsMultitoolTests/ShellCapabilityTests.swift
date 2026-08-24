import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Coverage for `ShellCapability` and for `MultiTool.Builder.withShell(...)` —
/// eventplan.md § "Registration of capabilities: noun/verb": *"`withShell()` is
/// a short form of `withCapability(ShellCapability(...))`."*
///
/// Three properties carry this suite, and each one is a sentence of
/// eventplan.md § "The capability contract":
///
/// 1. The capability owns ONE noun and renders exactly three verbs under it.
/// 2. Shell is OFF by default: a builder that never calls `withShell()` renders
///    no entry under that noun at all.
/// 3. The three verbs reach every discovery surface alike — `searchTools`,
///    `help()` and `docs(name)` — because all three read the one `APISurface`
///    the builder rendered.
///
/// Each test that makes a store makes it in a temporary directory of its own,
/// thus the tests are independent and they run in parallel safely. No test here
/// spawns a command: what this suite proves is the WIRING of the capability,
/// and `ShellExecuteTests` and `ShellHistoryOpsTests` prove the behaviour of
/// each verb.
@Suite("ShellCapabilityTests")
struct ShellCapabilityTests {

    /// Owns the temporary directories this test makes. Thus they go away when
    /// the test ends, and they do not collect in `$TMPDIR` run after run.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "shellcapability-tests"

    /// The name of the store folder inside the directory of one test.
    private static let shellStoreDirectoryName = ".shell"

    /// The one noun this capability owns.
    private static let shellNoun = "shell"

    /// The verbs the capability holds, in the order they render. Each one is a
    /// `Tool.name`, which is the second segment of `tools.<noun>.<verb>`.
    private static let shellVerbs = ["execute", "getLines", "grepHistory"]

    /// The rendered call path of each verb, built from the two segments rather
    /// than written out again, thus the noun and the verbs have one home here.
    private static let shellPaths = shellVerbs.map { "\(shellNoun).\($0)" }

    /// How many verbs the capability renders. eventplan.md § "Consolidation of
    /// the siblings" fixes the count at three: it folds the siblings' run-plane
    /// verbs into the shared engine, and the content plane keeps its two.
    private static let verbCount = 3

    /// The first segment of every path the capability claims, with its
    /// separator. A builder that never registered the capability renders no
    /// path that opens with it.
    private static let shellPathPrefix = "\(shellNoun)."

    /// The two verbs eventplan.md § "Consolidation of the siblings" REMOVED.
    /// `status()` and `cancel(completionToken)` replace them, so neither may
    /// render under the shell noun.
    private static let removedPaths = [
        "\(shellPathPrefix)listProcesses", "\(shellPathPrefix)killProcess",
    ]

    /// The rendered call path of the one tool the off-by-default test registers
    /// instead, which proves that test reads a surface that was really built.
    private static let unrelatedToolPath = "getWeather"

    /// The plain-language goal the discovery test searches for.
    private static let shellTask = "run a shell command and read what it wrote"

    /// What the scripted selection tier answers: every shell verb, by its
    /// rendered path. Built from ``shellPaths`` so a verb added or taken away
    /// moves the reply with it.
    private static var selectionReply: String {
        let ids = shellPaths.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"ids\":[\(ids)]}"
    }

    // MARK: - The ground of one test

    /// A store directory inside a temporary directory this test owns.
    ///
    /// - Returns: A directory no other test shares.
    /// - Throws: When the temporary directory does not create.
    private func makeStoreDirectory() throws -> URL {
        try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
            .appendingPathComponent(Self.shellStoreDirectoryName)
    }

    /// The capability over a store this test owns.
    ///
    /// - Returns: The capability.
    /// - Throws: When the directory or the store does not prepare.
    private func makeCapability() throws -> ShellCapability {
        try ShellCapability(storeDirectory: makeStoreDirectory())
    }

    /// A registry holding the shell capability and nothing else.
    ///
    /// - Returns: The registry.
    /// - Throws: When the store does not prepare, or the surface does not
    ///   render.
    private func makeShellRegistry() throws -> MultiTool.Registry {
        try MultiTool.Builder()
            .withShell(storeDirectory: makeStoreDirectory())
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
        _ kind: Verb.Type, in capability: ShellCapability
    ) throws -> Verb {
        try #require(capability.tools.compactMap { $0 as? Verb }.first)
    }

    // MARK: - The noun and its verbs

    /// eventplan.md § "Registration of capabilities: noun/verb": a capability
    /// is a noun plus its tools, and nothing else. The capability supplies the
    /// first segment one time, and each verb supplies the second.
    @Test("the capability owns the shell noun and holds exactly its three verbs")
    func theCapabilityOwnsTheShellNounAndHoldsItsThreeVerbs() throws {
        let capability = try makeCapability()

        #expect(capability.noun == Self.shellNoun)
        #expect(capability.tools.count == Self.verbCount)
        #expect(capability.tools.map { $0.name } == Self.shellVerbs)
    }

    /// The three verbs answer for one session, because they read and write one
    /// store — the promise each verb's own doc comment makes: "the store it
    /// records into is the store the capability owns". A store for each verb
    /// would make `getLines` blind to what `execute` just wrote.
    @Test("the three verbs read and write one store")
    func theThreeVerbsReadAndWriteOneStore() throws {
        let capability = try makeCapability()

        let execute = try Self.verb(Execute.self, in: capability)
        let getLines = try Self.verb(GetLines.self, in: capability)
        let grepHistory = try Self.verb(GrepHistory.self, in: capability)

        #expect(execute.runner.state === getLines.state)
        #expect(getLines.state === grepHistory.state)
    }

    /// The confinement and the live view of the output reach the run plane
    /// through the runner, which is the whole of what `Execute` is configured
    /// with. A host that gives the capability a sandbox gives it to the spawn.
    @Test("the sandbox and the live view of the output reach the runner of the run-plane verb")
    func theSandboxAndTheLiveViewReachTheRunner() throws {
        let stream = ShellOutputChunkStream()

        let capability = try ShellCapability(
            storeDirectory: makeStoreDirectory(),
            sandbox: UnconfinedSandbox(),
            outputChunkStream: stream)

        let execute = try Self.verb(Execute.self, in: capability)
        #expect(execute.runner.sandbox is UnconfinedSandbox)
        #expect(execute.runner.outputChunkStream === stream)
    }

    // MARK: - The rendered surface

    /// eventplan.md § "Registration of capabilities: noun/verb": each entry is
    /// `tools.<noun>.<verb>`, and it has two segments. `withShell()` is the
    /// short form of `withCapability(ShellCapability(...))`, so it renders the
    /// same three paths that capability holds.
    @Test("withShell renders exactly shell.execute, shell.getLines and shell.grepHistory")
    func withShellRendersExactlyTheThreeVerbs() throws {
        let registry = try makeShellRegistry()

        let paths = registry.surface.entries.map(\.path)

        #expect(paths == Self.shellPaths)
        #expect(Set(paths).count == Self.verbCount)
    }

    /// eventplan.md § "The capability contract": "The modules are opt-in ...
    /// They are off by default." A builder that never asked for the shell
    /// capability claims no part of that namespace.
    @Test("a builder with no withShell renders no entry under the shell noun")
    func aBuilderWithNoWithShellRendersNoShellEntry() throws {
        let surface = try MultiTool.Builder().addTool(WeatherTool()).build()

        // The unrelated tool proves the surface was really built, thus the two
        // expectations below read an answer rather than an empty catalog.
        #expect(surface.entries.map(\.path) == [Self.unrelatedToolPath])
        #expect(!surface.entries.contains { $0.path.hasPrefix(Self.shellPathPrefix) })
        #expect(!surface.entries.contains { $0.path == Self.shellNoun })
    }

    /// eventplan.md § "Consolidation of the siblings" removes the two run-plane
    /// verbs of the sibling shell tool. `status()` and `cancel(completionToken)`
    /// replace them, and neither may come back as a verb of this noun.
    @Test("the shell surface names no listProcesses verb and no killProcess verb")
    func theShellSurfaceNamesNeitherRemovedVerb() throws {
        let registry = try makeShellRegistry()

        let paths = Set(registry.surface.entries.map(\.path))

        for removed in Self.removedPaths {
            #expect(!paths.contains(removed), "the surface was: \(paths.sorted())")
        }
    }

    // MARK: - Discovery

    /// eventplan.md § "Registration of capabilities: noun/verb": "The path, the
    /// `findAPIs` result, the `help()` entry ... all come from the one pair."
    /// `findAPIs` ships as `searchTools`, and the answer it formats carries each
    /// matched entry's verbatim block plus that entry's runnable example,
    /// qualified with the noun so a model can call it as written.
    @Test("searchTools finds each shell verb, with the runnable example of that verb")
    func searchToolsFindsEachShellVerbWithItsRunnableExample() async throws {
        let surface = try MultiTool.Builder()
            .withShell(storeDirectory: makeStoreDirectory())
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
            arguments: SearchToolsArguments(task: Self.shellTask))

        for path in Self.shellPaths {
            let entry = try #require(surface.entries.first { $0.path == path })
            #expect(feedback.contains(entry.block), "feedback was: \(feedback)")
            #expect(feedback.contains("Example: \(entry.qualifiedExample)"))
            #expect(entry.qualifiedExample.hasPrefix("await tools.\(path)("))
        }
    }

    /// `help()` reads the same rendered surface, so it names each verb by its
    /// qualified path.
    @Test("help() renders the three shell verbs")
    func helpRendersTheThreeShellVerbs() async throws {
        let multiTool = MultiTool(registry: try makeShellRegistry())

        let output = try await multiTool.call(arguments: RunCodeArguments(code: "return help();"))

        let paths = try JSONDecoder().decode([String].self, from: Data(output.utf8))
        #expect(paths == Self.shellPaths)
    }

    /// `docs(name)` hands back the entry's own rendered block, unchanged. Thus
    /// a snippet reads the same text discovery read, and the two can never
    /// describe a verb differently.
    @Test("docs() renders the block of each shell verb")
    func docsRendersTheBlockOfEachShellVerb() async throws {
        let registry = try makeShellRegistry()
        let multiTool = MultiTool(registry: registry)

        for path in Self.shellPaths {
            let entry = try #require(registry.surface.entries.first { $0.path == path })

            let output = try await multiTool.call(
                arguments: RunCodeArguments(code: "return docs('\(path)');"))

            let rendered = try JSONDecoder().decode(String.self, from: Data(output.utf8))
            #expect(rendered == entry.block)
        }
    }
}
