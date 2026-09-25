import Foundation
import FoundationModels
import FoundationModelsRouter
import MCPTestServer
import Testing

@testable import FoundationModelsMultitool

/// Coverage for `WebCapability` and for `MultiTool.Builder.withWeb(...)` —
/// web.md § "Mount in code mode".
///
/// The suite has the shape of `FilesCapabilityTests`, and it proves three
/// properties:
///
/// 1. The capability owns ONE noun, `web`, and holds exactly two verbs over
///    one shared `WebContext`.
/// 2. The web capability is OFF by default: a builder with no `withWeb` renders
///    no `web` entry. A second `withWeb` replaces the first, and the last
///    configuration wins. A different owner of the noun fails at
///    `buildRegistry()`.
/// 3. The two verbs reach each discovery surface: `searchTools`, `help()`,
///    and `docs(name)`.
///
/// No test goes to the network. Each capability uses the session
/// configuration of a `WebStub` with no routes, and the `.keyless`
/// configuration, which reads no environment. The inline tests call each verb
/// with a bad argument, thus the verb gives a correction before it sends a
/// request or resolves a host.
@Suite("WebCapabilityTests")
struct WebCapabilityTests {

    /// The one noun this capability owns.
    private static let webNoun = "web"

    /// The verbs the capability holds, in the order they render.
    private static let webVerbs = ["search", "fetch"]

    /// The rendered call path of each verb, made from the two segments.
    private static let webPaths = webVerbs.map { "\(webNoun).\($0)" }

    /// The first segment of each path the capability claims, with its
    /// separator.
    private static let webPathPrefix = "\(webNoun)."

    /// The rendered call path of the one tool the off-by-default test
    /// registers instead. It proves that the test reads a surface that was
    /// really built.
    private static let unrelatedToolPath = "getWeather"

    /// The plain-language goal the discovery test searches for.
    private static let webTask = "search the web and read a page"

    /// A byte limit that no default policy has. The test of the configuration
    /// finds it again in the context of the verbs.
    private static let distinctByteLimit = 4_321

    /// A second byte limit that no default policy has. The test of a second
    /// `withWeb` gives it to the first call, and `distinctByteLimit` to the
    /// last call.
    private static let replacedByteLimit = 1_234

    /// The `url` of the inline fetch test. It is not `http` or `https`, thus
    /// the verb gives a correction and sends no request.
    private static let rejectedURL = "ftp://x"

    /// The `query` of the inline search test. It is empty after the trim,
    /// thus the verb gives a correction and sends no request.
    private static let rejectedQuery = "   "

    /// The stub whose session each capability of the test uses. It has no
    /// routes, thus a request that the test did not expect gets a 404 and
    /// never goes to the network.
    private let stub = WebStub(routes: [:])

    // MARK: - The ground of one test

    /// The capability over the stub session of this test.
    ///
    /// - Parameter configuration: The providers and the fetch policy. The
    ///   default is `.keyless`, which reads no environment.
    /// - Returns: The capability.
    private func makeCapability(configuration: WebConfiguration = .keyless) -> WebCapability {
        WebCapability(configuration: configuration, sessionConfiguration: stub.sessionConfiguration)
    }

    /// A configuration with one keyless provider and a fetch policy with the
    /// byte limit `maxBytes`. It reads no environment.
    ///
    /// - Parameter maxBytes: The byte limit of the fetch policy.
    /// - Returns: The configuration.
    private static func webConfiguration(maxBytes: Int) -> WebConfiguration {
        WebConfiguration(providers: [.duckDuckGoHTML], fetch: WebFetchPolicy(maxBytes: maxBytes))
    }

    /// A builder that holds the web capability and nothing else.
    ///
    /// - Returns: The builder.
    private func makeWebBuilder() -> MultiTool.Builder {
        MultiTool.Builder()
            .withWeb(configuration: .keyless, sessionConfiguration: stub.sessionConfiguration)
    }

    /// The one verb of `capability` that is a `Verb`.
    ///
    /// - Parameters:
    ///   - kind: The verb type to find.
    ///   - capability: The capability to read.
    /// - Returns: That verb.
    /// - Throws: When the capability holds no such verb.
    private static func verb<Verb: Tool>(_ kind: Verb.Type, in capability: WebCapability) throws -> Verb {
        try #require(capability.tools.compactMap { $0 as? Verb }.first)
    }

    /// Mounts `verb` the way the session mounts it, as a synchronous verb.
    ///
    /// - Parameters:
    ///   - verb: The verb to mount.
    ///   - context: The ambient context of the outer run.
    /// - Returns: The mounted verb, with the arguments and the output of
    ///   `verb`.
    /// - Throws: When the mounted tool does not keep the types of `verb`.
    private static func mountedInline<Verb: Tool>(
        _ verb: Verb, in context: ToolContext
    ) throws -> any Tool<Verb.Arguments, Verb.Output> {
        try #require(context.mount(verb, as: .synchronous) as? any Tool<Verb.Arguments, Verb.Output>)
    }

    /// The expectation that `builder` fails at `buildRegistry()` with
    /// `.duplicateNoun` for the noun `web`.
    ///
    /// - Parameter builder: The builder with a second owner of the noun.
    private static func expectDuplicateWebNoun(_ builder: MultiTool.Builder) {
        #expect {
            try builder.buildRegistry()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .duplicateNoun && builderError.name == webNoun
        }
    }

    // MARK: - The noun and its verbs

    /// A capability is a noun plus its tools. The capability gives the first
    /// segment one time, and each verb gives the second.
    @Test("the capability owns the web noun and holds exactly its two verbs")
    func theCapabilityOwnsTheWebNounAndHoldsItsTwoVerbs() {
        let capability = makeCapability()

        #expect(capability.noun == Self.webNoun)
        #expect(capability.tools.map { $0.name } == Self.webVerbs)
    }

    /// The two verbs hold the one context that the capability made, thus
    /// they share one session and one page cache.
    @Test("the two verbs hold one shared context")
    func theTwoVerbsHoldOneSharedContext() throws {
        let capability = makeCapability()

        let search = try Self.verb(Search.self, in: capability)
        let fetch = try Self.verb(Fetch.self, in: capability)

        #expect(search.context === fetch.context)
    }

    /// The configuration of the initializer reaches the one context of the
    /// verbs.
    @Test("the configuration reaches the one context of the verbs")
    func theConfigurationReachesTheOneContext() throws {
        let capability = makeCapability(configuration: Self.webConfiguration(maxBytes: Self.distinctByteLimit))

        let fetch = try Self.verb(Fetch.self, in: capability)
        #expect(fetch.context.fetcher.policy.maxBytes == Self.distinctByteLimit)
    }

    // MARK: - Each verb answers inline

    /// `search` declares no background mount, thus a mounted search answers
    /// its value in band.
    @Test("a search verb mounted by the session answers its value inline")
    func aSearchVerbMountedByTheSessionAnswersInline() async throws {
        let context = try await makeOuterRunContext()
        let search = try Self.mountedInline(Self.verb(Search.self, in: makeCapability()), in: context)

        let result = try await search.call(
            arguments: .init(query: Self.rejectedQuery, count: nil, freshness: nil, site: nil))

        #expect(result.correction != nil)
        #expect(await context.backgroundRuns().isEmpty)
        #expect(stub.requests.isEmpty)
    }

    /// `fetch` declares no background mount, thus a mounted fetch answers
    /// its value in band.
    @Test("a fetch verb mounted by the session answers its value inline")
    func aFetchVerbMountedByTheSessionAnswersInline() async throws {
        let context = try await makeOuterRunContext()
        let fetch = try Self.mountedInline(Self.verb(Fetch.self, in: makeCapability()), in: context)

        let result = try await fetch.call(
            arguments: .init(
                url: Self.rejectedURL, format: nil, offset: nil, maxCharacters: nil, timeout: nil))

        #expect(result.correction != nil)
        #expect(await context.backgroundRuns().isEmpty)
        #expect(stub.requests.isEmpty)
    }

    // MARK: - The rendered surface

    /// `withWeb` is the short form of `withCapability(WebCapability(...))`,
    /// thus it renders the two paths that the capability holds, and nothing
    /// else.
    @Test("withWeb renders exactly the two web verbs")
    func withWebRendersExactlyTheTwoVerbs() throws {
        let registry = try makeWebBuilder().buildRegistry()

        #expect(registry.surface.entries.map(\.path) == Self.webPaths)
    }

    /// The web capability is off by default. A builder that never asked for
    /// it claims no part of the `web` namespace.
    @Test("a builder with no withWeb renders no entry under the web noun")
    func aBuilderWithNoWithWebRendersNoWebEntry() throws {
        let surface = try MultiTool.Builder().addTool(WeatherTool()).build()

        #expect(surface.entries.map(\.path) == [Self.unrelatedToolPath])
        #expect(!surface.entries.contains { $0.path.hasPrefix(Self.webPathPrefix) })
        #expect(!surface.entries.contains { $0.path == Self.webNoun })
    }

    /// A second `withWeb` replaces the first. It is not a second owner of the
    /// noun: one `tools.web` namespace renders, and its verbs hold the
    /// configuration of the last call.
    @Test("a second withWeb replaces the first, and the last configuration wins")
    func aSecondWithWebReplacesTheFirst() throws {
        let registry = try MultiTool.Builder()
            .withWeb(
                configuration: Self.webConfiguration(maxBytes: Self.replacedByteLimit),
                sessionConfiguration: stub.sessionConfiguration)
            .withWeb(
                configuration: Self.webConfiguration(maxBytes: Self.distinctByteLimit),
                sessionConfiguration: stub.sessionConfiguration)
            .buildRegistry()

        #expect(registry.surface.entries.map(\.path) == Self.webPaths)
        let search = try #require(registry.tools[Self.webPaths[0]] as? Search)
        let fetch = try #require(registry.tools[Self.webPaths[1]] as? Fetch)
        #expect(search.context === fetch.context)
        #expect(fetch.context.fetcher.policy.maxBytes == Self.distinctByteLimit)
    }

    /// The replacement keeps the position of the first `withWeb`, thus a
    /// second call does not move the web verbs after a later registration.
    @Test("a second withWeb keeps the position of the first")
    func aSecondWithWebKeepsThePositionOfTheFirst() throws {
        let surface = try makeWebBuilder()
            .addTool(WeatherTool())
            .withWeb(configuration: .keyless, sessionConfiguration: stub.sessionConfiguration)
            .build()

        #expect(surface.entries.map(\.path) == Self.webPaths + [Self.unrelatedToolPath])
    }

    /// A registration of another tool under the noun `web` fails loudly at
    /// `buildRegistry()`.
    @Test("a second registration under the web noun makes buildRegistry() throw duplicateNoun")
    func aSecondRegistrationUnderTheWebNounThrows() {
        Self.expectDuplicateWebNoun(makeWebBuilder().register(noun: Self.webNoun, tool: WeatherTool()))
    }

    /// An MCP server with the name `web`, beside the web capability, fails
    /// loudly at `buildRegistry()`. The server is in memory, thus no request
    /// goes to the network.
    @Test("an MCP server named web beside withWeb makes buildRegistry() throw duplicateNoun")
    func anMCPServerNamedWebBesideWithWebThrows() async throws {
        let (scripted, server) = try await MCPTestSupport.connectedLoopbackMCPServer(
            over: .inMemory, name: Self.webNoun)
        let builder = try await makeWebBuilder().withMCP(servers: [server])

        Self.expectDuplicateWebNoun(builder)
        withExtendedLifetime(scripted) {}
    }

    // MARK: - Discovery

    /// `searchTools` reads the rendered surface. The answer holds the block of
    /// each matched entry and its runnable example, with the noun.
    @Test("searchTools finds each web verb, with the runnable example of that verb")
    func searchToolsFindsEachWebVerbWithItsRunnableExample() async throws {
        let surface = try makeWebBuilder().build()

        let feedback = try await CapabilityDiscoveryProbe.searchToolsFeedback(
            over: surface, selecting: Self.webPaths, task: Self.webTask)

        for path in Self.webPaths {
            let entry = try #require(surface.entries.first { $0.path == path })
            #expect(feedback.contains(entry.block), "feedback was: \(feedback)")
            #expect(feedback.contains("Example: \(entry.qualifiedExample)"))
            #expect(entry.qualifiedExample.hasPrefix("await tools.\(path)("))
        }
    }

    /// `help()` reads the same rendered surface, thus it names each verb by
    /// its qualified path.
    @Test("help() renders the two web verbs")
    func helpRendersTheTwoWebVerbs() async throws {
        let multiTool = MultiTool(registry: try makeWebBuilder().buildRegistry())

        #expect(try await helpPaths(of: multiTool) == Self.webPaths)
    }

    /// `docs(name)` gives the rendered block of the entry, with no change.
    @Test("docs() renders the block of each web verb")
    func docsRendersTheBlockOfEachWebVerb() async throws {
        let registry = try makeWebBuilder().buildRegistry()
        let multiTool = MultiTool(registry: registry)

        for path in Self.webPaths {
            let entry = try #require(registry.surface.entries.first { $0.path == path })
            #expect(try await CapabilityDiscoveryProbe.docsBlock(of: path, in: multiTool) == entry.block)
        }
    }
}
