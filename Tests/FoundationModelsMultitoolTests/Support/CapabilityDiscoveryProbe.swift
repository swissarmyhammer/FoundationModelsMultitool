// `CapabilityDiscoveryProbe` — the reads of the discovery surfaces that a
// suite of one capability makes.
//
// A capability suite proves that each verb of the capability is found by
// `searchTools` and is rendered by `docs(name)`. The two reads have the same
// setup for each capability, thus the setup stands here one time. The
// `help()` read is `helpPaths(of:)` in `Fixtures/HelpSurfaceFixtures.swift`.

import Foundation
import FoundationModelsMetadataRegistry
import FoundationModelsRouter

@testable import FoundationModelsMultitool

/// The discovery reads of a capability suite.
enum CapabilityDiscoveryProbe {

    /// The feedback of one `searchTools` call over a surface.
    ///
    /// The selection tier is scripted: it selects each path of `paths`. Thus
    /// the feedback holds the entries of those paths, and the test reads what
    /// the formatted answer says about each one.
    ///
    /// - Parameters:
    ///   - surface: The rendered surface to search.
    ///   - paths: The call paths that the scripted selection tier selects.
    ///   - task: The plain-language goal of the search.
    /// - Returns: The feedback text of the call.
    /// - Throws: What the `searchTools` call throws.
    static func searchToolsFeedback(
        over surface: APISurface, selecting paths: [String], task: String
    ) async throws -> String {
        let selection = RootSessionRespondCalledDirectlySession(
            forkResponses: [selectionReply(selecting: paths)])
        let searcher = MetadataSearcher(
            items: surface.entries,
            mode: .auto,
            selection: SelectionConfig(model: { _ in selection }, capacityCharacterLimit: .max)
        )
        let searchTools = SearchToolsTool(searcher: searcher, limit: surface.entries.count)
        return try await searchTools.call(arguments: SearchToolsArguments(task: task))
    }

    /// The block that `docs(path)` gives in a snippet run on `runCode`.
    ///
    /// - Parameters:
    ///   - path: The call path of the entry, for example `web.search`.
    ///   - runCode: The tool to run the snippet on.
    /// - Returns: The rendered block.
    /// - Throws: What the run or the decode throws.
    static func docsBlock(of path: String, in runCode: MultiTool) async throws -> String {
        let output = try await runCode.call(arguments: RunCodeArguments(code: "return docs('\(path)');"))
        return try JSONDecoder().decode(String.self, from: Data(output.utf8))
    }

    /// The reply of the scripted selection tier: the ids of `paths`.
    ///
    /// - Parameter paths: The call paths to select.
    /// - Returns: The JSON reply, for example `{"ids":["web.search"]}`.
    private static func selectionReply(selecting paths: [String]) -> String {
        let ids = paths.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"ids\":[\(ids)]}"
    }
}
