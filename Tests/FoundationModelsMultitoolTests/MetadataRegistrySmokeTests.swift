import Foundation
import FoundationModelsMetadataRegistry
import Testing

/// Smoke test for the `FoundationModelsMetadataRegistry` dependency (task
/// 0wf5gad): proves the package actually resolves and links, not merely that
/// `Package.swift` parses. Mirrors the registry README's own git-commands
/// example — a trivial `SearchableMetadata` fixture searched with
/// `MetadataSearcher(items:mode: .retrieval)` — rather than exercising any of
/// this package's own production code.
@Suite("MetadataRegistrySmokeTests")
struct MetadataRegistrySmokeTests {
    /// A trivial `SearchableMetadata` fixture, one git subcommand per item —
    /// verbatim the registry README's example.
    private struct GitCommand: SearchableMetadata {
        let id: String
        let block: String
        func renderBlock() -> String { block }
    }

    @Test("a keyword query ranks the matching git command first")
    func keywordQueryRanksMatchingCommandFirst() async throws {
        let commands = [
            GitCommand(id: "commit", block: "Record staged changes as a new snapshot in the repository history."),
            GitCommand(id: "push", block: "Upload local branch history to a remote server."),
            GitCommand(id: "pull", block: "Download and merge remote branch history."),
            GitCommand(id: "branch", block: "List, create, or delete lines of independent development."),
            GitCommand(id: "stash", block: "Temporarily set aside uncommitted edits to switch tasks."),
        ]

        let searcher = MetadataSearcher(items: commands, mode: .retrieval)
        let matches = try await searcher.search(intent: "commit changes to git", limit: 3)

        #expect(matches.first?.id == "commit")
    }
}
