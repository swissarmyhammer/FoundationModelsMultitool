import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolCLI

/// The tests of the `--web` flag of `multitool-cli`. They are in an extension,
/// thus each part of the suite stays short, and
/// `swift test --filter CLIArgumentTests` runs them with the other CLI tests.
///
/// No test here uses the network. `withWeb()` reads the environment when the
/// registry builds, and it sends no request until a verb is called.
extension CLIArgumentTests {
    // MARK: - `--web` parsing

    /// The command of the `--mcp` option in the tests below. It is an
    /// executable that exists, so a case fails on the parse alone.
    private static let webCaseCommand = "/usr/bin/true"

    /// The noun of the `--mcp` option in the tests below.
    private static let webCaseServerNoun = "echo"

    /// `--web` and one `--mcp` option, in each of the two orders.
    private static let webAndMCPOrders = [
        ["--web", "--mcp", "\(webCaseServerNoun)=\(webCaseCommand)"],
        ["--mcp", "\(webCaseServerNoun)=\(webCaseCommand)", "--web"],
    ]

    /// The noun that the web capability owns.
    private static let webNoun = "web"

    /// The two paths that `withWeb()` renders, in render order.
    private static let webPaths = ["\(webNoun).search", "\(webNoun).fetch"]

    @Test("parsing --web sets web, and no other flag")
    func parseWeb() throws {
        let parsed = try CLIRunner.parse(["--web"])
        #expect(parsed.web)
        #expect(!parsed.direct)
        #expect(!parsed.help)
        #expect(parsed.mcpServers.isEmpty)
    }

    @Test("parsing no arguments leaves web off")
    func parseDefaultsLeaveWebOff() throws {
        let parsed = try CLIRunner.parse([])
        #expect(!parsed.web)
    }

    @Test(
        "parsing --web with --mcp in either order sets web and reads the server with no arguments",
        arguments: CLIArgumentTests.webAndMCPOrders)
    func parseWebWithMCP(arguments: [String]) throws {
        let parsed = try CLIRunner.parse(arguments)
        #expect(parsed.web)
        #expect(
            parsed.mcpServers == [
                MCPServerSpec(name: Self.webCaseServerNoun, command: Self.webCaseCommand, arguments: [])
            ])
    }

    @Test("the usage text lists --web with the two verbs it mounts and the key variables")
    func usageTextListsTheWebFlag() {
        let usage = CLIRunner.usageText
        #expect(usage.contains("[--web]"))
        let webLine = usage.split(separator: "\n").first { $0.hasPrefix("  --web ") }
        #expect(webLine != nil, "usage was: \(usage)")
        #expect(usage.contains("tools.web.search"))
        #expect(usage.contains("tools.web.fetch"))
        #expect(usage.contains("BRAVE_SEARCH_API_KEY"))
        #expect(usage.contains("SEARXNG_URL"))
    }

    // MARK: - `--web`: the demo registry

    @Test("the demo registry of a --web run renders web.search and web.fetch")
    func webDemoRegistryHasTheTwoWebEntries() async throws {
        let demo = try await CLIRunner.makeDemoRegistry(direct: false, web: true, mcpServers: [])
        let paths = demo.registry.surface.entries.map(\.path)
        await demo.pool.shutdownAll()

        #expect(paths.filter { $0.hasPrefix("\(Self.webNoun).") } == Self.webPaths, "paths were: \(paths)")
    }

    @Test("the demo registry of a run with no --web renders no web entry")
    func demoRegistryWithoutWebHasNoWebEntry() async throws {
        let demo = try await CLIRunner.makeDemoRegistry(direct: false, web: false, mcpServers: [])
        let paths = demo.registry.surface.entries.map(\.path)
        await demo.pool.shutdownAll()

        #expect(!paths.isEmpty)
        #expect(!paths.contains { $0 == Self.webNoun || $0.hasPrefix("\(Self.webNoun).") }, "paths were: \(paths)")
    }
}
