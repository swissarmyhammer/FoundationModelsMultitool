import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for `GitCapability` and for `MultiTool.Builder.withGit(root:)` —
/// git.md § "Proposed shape" and § "Decisions", item 8.
///
/// Three properties carry this suite, and each one is a sentence of
/// eventplan.md § "The capability contract":
///
/// 1. The capability owns ONE noun, `git`. Each verb task adds its verb to
///    `GitCapability.tools` and to ``verbNames``.
/// 2. Git is OFF by default: a builder that never calls `withGit(root:)`
///    renders no entry under that noun, and a second registration of the noun
///    fails loudly at `buildRegistry()`.
/// 3. The capability acquires no resource that can fail at construction: a
///    root in no repository does not throw at build time.
@Suite("GitCapabilityTests")
struct GitCapabilityTests {

    /// The name of the temporary folder of one test. Thus a leaked folder is
    /// traceable to this suite.
    private static let testDirectoryName = "GitCapabilityTests"

    /// The one noun this capability owns.
    private static let gitNoun = "git"

    /// The first segment of every path the capability claims, with its
    /// separator.
    private static let gitPathPrefix = "\(gitNoun)."

    /// The verbs of the capability, in render order.
    private static let verbNames = ["blame", "show", "log", "status", "branches", "changes", "diff"]

    /// The rendered call path of the one tool the off-by-default test
    /// registers instead, which proves that test reads a surface that was
    /// really built.
    private static let unrelatedToolPath = "getWeather"

    // MARK: - The noun

    /// The capability owns the `git` noun, and holds each verb that a verb
    /// task added, in render order.
    @Test("the capability owns the git noun and holds its verbs")
    func theCapabilityOwnsTheGitNounAndHoldsItsVerbs() throws {
        let repository = try TemporaryGitRepository()

        let capability = GitCapability(root: repository.workDirectory)

        #expect(capability.noun == Self.gitNoun)
        #expect(capability.tools.map(\.name) == Self.verbNames)
    }

    /// `withGit(root:)` renders each verb under the `git` noun.
    @Test("withGit renders each verb under the git noun")
    func withGitRendersEachVerbUnderTheGitNoun() throws {
        let repository = try TemporaryGitRepository()

        let surface = try MultiTool.Builder().withGit(root: repository.workDirectory).build()

        #expect(surface.entries.map(\.path) == Self.verbNames.map { Self.gitPathPrefix + $0 })
    }

    /// A host can mount git alone. Then a path of another noun, such as
    /// `tools.files.read`, names a verb that does not exist, and the model
    /// calls it in vain. Thus the text the model reads for each git verb —
    /// its description, each argument guide, and its example — names only
    /// paths under the git noun.
    @Test("with git mounted alone, each git verb names no tool path outside the git noun")
    func eachGitVerbNamesNoToolPathOutsideTheGitNoun() throws {
        let repository = try TemporaryGitRepository()

        let surface = try MultiTool.Builder().withGit(root: repository.workDirectory).build()

        let foreignPathsByVerb = Dictionary(
            uniqueKeysWithValues: surface.entries.map { entry in (entry.path, Self.foreignToolPaths(in: entry.block)) })
        let noForeignPath = Dictionary(
            uniqueKeysWithValues: Self.verbNames.map { verb in (Self.gitPathPrefix + verb, [String]()) })
        #expect(foreignPathsByVerb == noForeignPath)
    }

    /// The capability holds the one context of its root, and that context
    /// found the repository of the root.
    @Test("the capability holds the context of its root")
    func theCapabilityHoldsTheContextOfItsRoot() throws {
        let repository = try TemporaryGitRepository()

        let capability = GitCapability(root: repository.workDirectory)

        #expect(capability.context.root == repository.workDirectory)
        let location = try capability.context.repository.get()
        #expect(location.workDirectory.path == resolvedPath(repository.workDirectory.path))
    }

    // MARK: - The builder short form

    /// `withGit(root:)` claims the whole `tools.git` namespace: a tool that
    /// another registration puts under the noun fails at `buildRegistry()`.
    @Test("withGit claims the git noun, and a second registration under it makes buildRegistry() throw")
    func withGitClaimsTheGitNoun() throws {
        let repository = try TemporaryGitRepository()

        #expect {
            try MultiTool.Builder()
                .withGit(root: repository.workDirectory)
                .register(noun: Self.gitNoun, tool: WeatherTool())
                .buildRegistry()
        } throws: { error in
            Self.isDuplicateGitNoun(error)
        }
    }

    /// A second `withGit(root:)` is a second claim on the same noun. Its verbs
    /// collide path by path, so `buildRegistry()` reports the first path
    /// collision, the same as a second `withFiles(root:)` — loudly, and never
    /// a quiet merge.
    @Test("a second withGit registration makes buildRegistry() throw")
    func aSecondWithGitRegistrationThrows() throws {
        let repository = try TemporaryGitRepository()

        #expect {
            try MultiTool.Builder()
                .withGit(root: repository.workDirectory)
                .withGit(root: repository.workDirectory)
                .buildRegistry()
        } throws: { error in
            guard let builderError = error as? MultiToolBuilderError else { return false }
            return builderError.kind == .duplicateName && builderError.name == Self.verbNames.first
        }
    }

    /// eventplan.md § "The capability contract": "The modules are opt-in ...
    /// They are off by default." A builder that never asked for the git
    /// capability renders nothing under its noun.
    @Test("a builder with no withGit renders no entry under the git noun")
    func aBuilderWithNoWithGitRendersNoGitEntry() throws {
        let surface = try MultiTool.Builder().addTool(WeatherTool()).build()

        // The unrelated tool proves the surface was really built, thus the two
        // expectations below read an answer rather than an empty catalog.
        #expect(surface.entries.map(\.path) == [Self.unrelatedToolPath])
        #expect(!surface.entries.contains { $0.path.hasPrefix(Self.gitPathPrefix) })
        #expect(!surface.entries.contains { $0.path == Self.gitNoun })
    }

    /// A root in no repository does not throw at build time. The verbs answer
    /// the correction in band, call by call.
    @Test("a root outside any repository gives no throw at build time")
    func aRootOutsideAnyRepositoryGivesNoThrowAtBuildTime() throws {
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)

        let registry = try MultiTool.Builder()
            .withGit(root: outside)
            .addTool(WeatherTool())
            .buildRegistry()

        let expectedPaths = Self.verbNames.map { Self.gitPathPrefix + $0 } + [Self.unrelatedToolPath]
        #expect(Set(registry.surface.entries.map(\.path)) == Set(expectedPaths))
    }

    // MARK: - Helpers

    /// The `tools.<noun>.<verb>` paths in `text` whose noun is not `git`.
    ///
    /// - Parameter text: The rendered text of one surface entry.
    /// - Returns: Each such path, in text order.
    private static func foreignToolPaths(in text: String) -> [String] {
        // A `tools.<noun>.<verb>` call path. The capture is the noun.
        let toolPathPattern = /tools\.(\w+)\.\w+/
        return text.matches(of: toolPathPattern)
            .filter { match in match.output.1 != gitNoun }
            .map { match in String(match.output.0) }
    }

    /// Whether `error` is the `.duplicateNoun` failure for the `git` noun.
    ///
    /// - Parameter error: The error that `buildRegistry()` threw.
    /// - Returns: `true` for that failure.
    private static func isDuplicateGitNoun(_ error: any Error) -> Bool {
        guard let builderError = error as? MultiToolBuilderError else { return false }
        return builderError.kind == .duplicateNoun && builderError.name == gitNoun
    }
}
