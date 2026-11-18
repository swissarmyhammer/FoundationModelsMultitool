// `SessionsToolReferenceTests` — the session reference of the `id` of
// `check session` and of each change operation of the `sessions` tool
// (D200 (e)).
//
// The `id` takes `<id>`, `@<id>`, `<short id>`, `@<short id>` and `@<slug>`,
// through the one reader that `send message` uses too (D199 (d), D100). Each
// case uses its own `InMemorySessionDirectory`, and reads the state of the
// directory after the call, so it proves the change and not only the text of
// the answer. No case waits.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing
import ULID

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the session reference of the `id` of the operations
/// of the `sessions` tool that act on one session.
@Suite("SessionsToolReferenceTests", .ownsTemporaryDirectories)
struct SessionsToolReferenceTests {

    // MARK: - Constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// A folder that is not the folder of the caller.
    private static let otherFolder = URL(fileURLWithPath: "/work/other")

    /// A second folder that is not the folder of the caller.
    private static let thirdFolder = URL(fileURLWithPath: "/work/third")

    /// The title of each session of the slug cases.
    private static let apiTitle = "Fix the API tests"

    /// The slug of ``apiTitle``.
    private static let apiSlug = "fix-the-api-tests"

    /// The new title of the rename cases.
    private static let newTitle = "Parser review"

    /// The tag of the tag case.
    private static let reviewTag = "review"

    /// The name of an agent folder, and the slug of a reference that names no
    /// session.
    private static let travelName = "travel"

    /// The code-mode verb name that the corrective of a reference with no
    /// match names.
    private static let listSessionsVerb = "listSessions"

    /// The words of the corrective of an ambiguous reference.
    private static let ambiguousWords = "names more than one session"

    /// The sentence of the corrective of an ambiguous reference to a session
    /// operation.
    private static let notChangedWords = "Nothing changed."

    // MARK: - Helpers

    /// Calls one operation as the caller of a stub run.
    ///
    /// - Parameters:
    ///   - op: The op string.
    ///   - fields: The fields of the operation.
    ///   - directory: The directory of the tool.
    /// - Returns: The answer of the tool.
    /// - Throws: What the tool throws.
    private static func callAsCaller(
        _ op: String, _ fields: [(String, any ConvertibleToGeneratedContent)], in directory: InMemorySessionDirectory
    ) async throws -> String {
        let tool = try SessionsTool(directory: directory)
        return try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(arguments: Fixtures.payload(op, fields))
        }
    }

    // MARK: - The forms of a reference

    @Test("rename session with a short id renames that session")
    func renameSessionWithAShortIDRenamesTheSession() async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary(folder: Self.otherFolder)
        directory.register(target)

        _ = try await Self.callAsCaller(
            "rename session", [("id", target.shortID), ("title", Self.newTitle)], in: directory)

        #expect(try await SessionsToolFixtures.summary(of: target.id, in: directory).title == Self.newTitle)
    }

    @Test("pin session with @<slug> pins that session")
    func pinSessionWithASlugPinsTheSession() async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary(title: Self.apiTitle, folder: Self.otherFolder)
        directory.register(target)

        _ = try await Self.callAsCaller("pin session", [("id", "@\(Self.apiSlug)")], in: directory)

        #expect(try await SessionsToolFixtures.summary(of: target.id, in: directory).isPinned)
    }

    @Test("archive session with @<short id> archives that session")
    func archiveSessionWithAnAtShortIDArchivesTheSession() async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary(folder: Self.otherFolder)
        directory.register(target)

        _ = try await Self.callAsCaller("archive session", [("id", "@\(target.shortID)")], in: directory)

        #expect(try await SessionsToolFixtures.summary(of: target.id, in: directory).state == .archived)
    }

    /// The form of a full session id, written from the id.
    struct FullIDForm: Sendable, CustomTestStringConvertible {
        /// The name of the form in the test report.
        let name: String

        /// The `id` text of the form for a session id.
        let text: @Sendable (ULID) -> String

        /// The name of the case in the test report.
        var testDescription: String { name }
    }

    /// Each form of a full session id.
    static let fullIDForms: [FullIDForm] = [
        FullIDForm(name: "<id>") { $0.ulidString },
        FullIDForm(name: "@<id>") { "@\($0.ulidString)" },
    ]

    @Test("check session with a full id, with and without @, gives the facts of that session", arguments: fullIDForms)
    func checkSessionWithAFullIDGivesTheFacts(_ form: FullIDForm) async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary(title: Self.apiTitle, folder: Self.otherFolder)
        directory.register(target)

        let output = try await Self.callAsCaller("check session", [("id", form.text(target.id))], in: directory)

        #expect(output.contains(Self.apiTitle), "output was: \(output)")
    }

    @Test("tag session with @<slug> tags the session with the slug in the folder of the caller first")
    func tagSessionWithASlugPrefersTheFolderOfTheCaller() async throws {
        let directory = InMemorySessionDirectory()
        let elsewhere = Fixtures.summary(title: Self.apiTitle, folder: Self.otherFolder)
        let local = Fixtures.summary(title: Self.apiTitle)
        directory.register(elsewhere)
        directory.register(local)

        _ = try await Self.callAsCaller(
            "tag session", [("id", "@\(Self.apiSlug)"), ("tags", [Self.reviewTag])], in: directory)

        #expect(try await SessionsToolFixtures.summary(of: local.id, in: directory).tags == [Self.reviewTag])
        #expect(try await SessionsToolFixtures.summary(of: elsewhere.id, in: directory).tags.isEmpty)
    }

    // MARK: - Refusals

    @Test("rename session with an ambiguous slug gives the corrective with each match and changes nothing")
    func renameSessionWithAnAmbiguousSlugListsEachMatch() async throws {
        let directory = InMemorySessionDirectory()
        let first = Fixtures.summary(title: Self.apiTitle, folder: Self.otherFolder)
        let second = Fixtures.summary(title: Self.apiTitle, folder: Self.thirdFolder)
        directory.register(first)
        directory.register(second)

        let output = try await Self.callAsCaller(
            "rename session", [("id", "@\(Self.apiSlug)"), ("title", Self.newTitle)], in: directory)

        #expect(output.contains(Self.ambiguousWords), "output was: \(output)")
        #expect(output.contains(Self.notChangedWords), "output was: \(output)")
        #expect(output.contains(Self.apiTitle), "output was: \(output)")
        for match in [first, second] {
            #expect(output.contains(match.id.ulidString), "output was: \(output)")
            #expect(output.contains(match.workingDirectory.path), "output was: \(output)")
            #expect(try await SessionsToolFixtures.summary(of: match.id, in: directory).title == Self.apiTitle)
        }
    }

    @Test(
        "pin session with a slug that names no session gives the corrective that names listSessions, and starts no agent"
    )
    func pinSessionWithAnUnknownSlugNamesListSessions() async throws {
        let directory = Fixtures.directoryWithLauncher(agentIDs: [Self.travelName])

        let output = try await Self.callAsCaller("pin session", [("id", "@\(Self.travelName)")], in: directory)

        let sessions = try await directory.sessions(matching: SessionQuery(includesRecorded: true))
        #expect(output.contains(Self.listSessionsVerb), "output was: \(output)")
        #expect(output.contains(Self.travelName), "output was: \(output)")
        #expect(sessions.allSatisfy { $0.agentID != Self.travelName })
    }

    @Test("a slug of a session that the caller cannot see is not a match")
    func aSlugOfAHiddenSessionIsNotAMatch() async throws {
        let directory = InMemorySessionDirectory()
        let owned = Fixtures.summary()
        let hidden = Fixtures.summary(title: Self.apiTitle, folder: Self.otherFolder)
        directory.register(owned)
        directory.register(hidden)
        let sessions = SessionsVisibility(
            directory: directory, viewer: GraphQLViewer.external(owning: [owned.id.ulidString]))

        let error = await #expect(throws: SessionsRefusal.self) {
            try await sessions.sessionID(referencedBy: "@\(Self.apiSlug)", lookupFolder: nil)
        }

        #expect(error?.kind == .invalidSessionID)
    }
}
