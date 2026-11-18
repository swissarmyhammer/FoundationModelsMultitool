// `SessionsToolUnarchiveTests` — the `unarchive session` operation of the
// `sessions` tool (D204 (c)).
//
// The `id` of `unarchive session` takes `<id>`, `@<id>`, `<short id>`,
// `@<short id>` and `@<slug>` through the one reader of the tool. For this
// operation only, a short id and a slug match only the archived sessions:
// first in the folder of the caller, then in all the sessions. The other
// operations keep the rule that an archived session matches only its id. Each
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

/// Behavioral tests for `unarchive session` of the `sessions` tool.
@Suite("SessionsToolUnarchiveTests", .ownsTemporaryDirectories)
struct SessionsToolUnarchiveTests {

    // MARK: - Constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The op string of the operation under test.
    private static let unarchiveOp = "unarchive session"

    /// The op string of `archive session`.
    private static let archiveOp = "archive session"

    /// A folder that is not the folder of the caller.
    private static let otherFolder = URL(fileURLWithPath: "/work/other")

    /// A second folder that is not the folder of the caller.
    private static let thirdFolder = URL(fileURLWithPath: "/work/third")

    /// The title of each session of the slug cases.
    private static let buildTitle = "Build fix"

    /// The slug of ``buildTitle``.
    private static let buildSlug = "build-fix"

    /// The new title of the rename case.
    private static let newTitle = "Parser review"

    /// The words of the corrective of an ambiguous reference.
    private static let ambiguousWords = "names more than one session"

    /// The words of the corrective of a session that is not archived.
    private static let notArchivedWords = "is not archived"

    /// The code-mode verb name that the corrective of a reference with no
    /// match names.
    private static let listSessionsVerb = "listSessions"

    // MARK: - Helpers

    /// Calls each payload in order as the caller of one stub run.
    ///
    /// - Parameters:
    ///   - payloads: The payloads, in order.
    ///   - directory: The directory of the tool.
    /// - Returns: The answer of each call, in order.
    /// - Throws: What the tool throws.
    private static func answers(
        to payloads: [GeneratedContent], in directory: InMemorySessionDirectory
    ) async throws -> [String] {
        let tool = try SessionsTool(directory: directory)
        return try await Fixtures.asCaller(in: directory) { _ in
            try await payloads.mappedInOrder { payload in try await tool.call(arguments: payload) }
        }
    }

    /// Calls one operation as the caller of a stub run.
    ///
    /// - Parameters:
    ///   - op: The op string.
    ///   - fields: The fields of the operation.
    ///   - directory: The directory of the tool.
    /// - Returns: The answer of the tool.
    /// - Throws: What the tool throws.
    private static func answer(
        _ op: String, _ fields: [(String, any ConvertibleToGeneratedContent)], in directory: InMemorySessionDirectory
    ) async throws -> String {
        try #require(try await answers(to: [Fixtures.payload(op, fields)], in: directory).first)
    }

    /// Archives each session in `sessions` with the directory, as the user.
    ///
    /// - Parameters:
    ///   - sessions: The sessions.
    ///   - directory: The directory.
    /// - Throws: What the directory throws.
    private static func archive(_ sessions: [SessionSummary], in directory: InMemorySessionDirectory) async throws {
        for session in sessions {
            _ = try await directory.archive(session.id, by: .user(clientID: "test"))
        }
    }

    // MARK: - The forms of a reference

    /// The form of a reference to one session, written from its summary.
    struct ReferenceForm: Sendable, CustomTestStringConvertible {
        /// The name of the form in the test report.
        let name: String

        /// The `id` text of the form for a session.
        let text: @Sendable (SessionSummary) -> String

        /// The name of the case in the test report.
        var testDescription: String { name }
    }

    /// Each form of a reference that the card names.
    static let referenceForms: [ReferenceForm] = [
        ReferenceForm(name: "@<slug>") { _ in "@\(buildSlug)" },
        ReferenceForm(name: "<short id>") { $0.shortID },
        ReferenceForm(name: "@<short id>") { "@\($0.shortID)" },
        ReferenceForm(name: "<id>") { $0.id.ulidString },
        ReferenceForm(name: "@<id>") { "@\($0.id.ulidString)" },
    ]

    @Test("archive, then unarchive session by each form of a reference, makes the session idle", arguments: referenceForms)
    func unarchiveSessionByEachFormMakesTheSessionIdle(_ form: ReferenceForm) async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary(title: Self.buildTitle, folder: Self.otherFolder)
        directory.register(target)

        _ = try await Self.answers(
            to: [
                Fixtures.payload(Self.archiveOp, [("id", target.id.ulidString)]),
                Fixtures.payload(Self.unarchiveOp, [("id", form.text(target))]),
            ],
            in: directory)

        #expect(try await Fixtures.summary(of: target.id, in: directory).state == .idle)
    }

    @Test("unarchive session gives the session, its agent and its folder")
    func unarchiveSessionGivesTheIdentity() async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary(folder: Self.otherFolder)
        directory.register(target)
        try await Self.archive([target], in: directory)

        let output = try await Self.answer(Self.unarchiveOp, [("id", target.id.ulidString)], in: directory)

        #expect(output.contains(target.id.ulidString), "output was: \(output)")
        #expect(output.contains(Fixtures.agentID), "output was: \(output)")
        #expect(output.contains(Self.otherFolder.path), "output was: \(output)")
    }

    @Test("unarchive session with @<slug> takes the archived session in the folder of the caller first")
    func unarchiveSessionWithASlugPrefersTheFolderOfTheCaller() async throws {
        let directory = InMemorySessionDirectory()
        let elsewhere = Fixtures.summary(title: Self.buildTitle, folder: Self.otherFolder)
        let local = Fixtures.summary(title: Self.buildTitle)
        directory.register(elsewhere)
        directory.register(local)
        try await Self.archive([elsewhere, local], in: directory)

        _ = try await Self.answer(Self.unarchiveOp, [("id", "@\(Self.buildSlug)")], in: directory)

        #expect(try await Fixtures.summary(of: local.id, in: directory).state == .idle)
        #expect(try await Fixtures.summary(of: elsewhere.id, in: directory).state == .archived)
    }

    @Test("unarchive session with @<slug> passes over a session with that slug that is not archived")
    func unarchiveSessionWithASlugPassesOverALiveSession() async throws {
        let directory = InMemorySessionDirectory()
        let live = Fixtures.summary(title: Self.buildTitle)
        let archived = Fixtures.summary(title: Self.buildTitle, folder: Self.otherFolder)
        directory.register(live)
        directory.register(archived)
        try await Self.archive([archived], in: directory)

        _ = try await Self.answer(Self.unarchiveOp, [("id", "@\(Self.buildSlug)")], in: directory)

        #expect(try await Fixtures.summary(of: archived.id, in: directory).state == .idle)
    }

    // MARK: - Refusals

    @Test("unarchive session with a slug of two archived sessions gives AMBIGUOUS_REFERENCE with each match")
    func unarchiveSessionWithAnAmbiguousSlugListsEachMatch() async throws {
        let directory = InMemorySessionDirectory()
        let first = Fixtures.summary(title: Self.buildTitle, folder: Self.otherFolder)
        let second = Fixtures.summary(title: Self.buildTitle, folder: Self.thirdFolder)
        directory.register(first)
        directory.register(second)
        try await Self.archive([first, second], in: directory)

        let output = try await Self.answer(Self.unarchiveOp, [("id", "@\(Self.buildSlug)")], in: directory)

        #expect(output.contains(Self.ambiguousWords), "output was: \(output)")
        #expect(output.contains(Self.buildTitle), "output was: \(output)")
        for match in [first, second] {
            #expect(output.contains(match.id.ulidString), "output was: \(output)")
            #expect(output.contains(match.workingDirectory.path), "output was: \(output)")
            #expect(try await Fixtures.summary(of: match.id, in: directory).state == .archived)
        }
    }

    @Test("unarchive session of a session that is not archived gives the NOT_ARCHIVED corrective")
    func unarchiveSessionOfASessionThatIsNotArchivedIsACorrective() async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary(folder: Self.otherFolder)
        directory.register(target)

        let output = try await Self.answer(Self.unarchiveOp, [("id", target.id.ulidString)], in: directory)

        #expect(output.contains(Self.notArchivedWords), "output was: \(output)")
        #expect(output.contains(target.id.ulidString), "output was: \(output)")
    }

    @Test("unarchive session with a slug of no archived session gives the corrective that names listSessions")
    func unarchiveSessionWithASlugOfNoArchivedSessionNamesListSessions() async throws {
        let directory = InMemorySessionDirectory()
        let live = Fixtures.summary(title: Self.buildTitle, folder: Self.otherFolder)
        directory.register(live)

        let output = try await Self.answer(Self.unarchiveOp, [("id", "@\(Self.buildSlug)")], in: directory)

        #expect(output.contains(Self.listSessionsVerb), "output was: \(output)")
        #expect(output.contains(Self.buildSlug), "output was: \(output)")
    }

    @Test("rename session with the slug of an archived session still finds no session")
    func renameSessionWithTheSlugOfAnArchivedSessionFindsNoSession() async throws {
        let directory = InMemorySessionDirectory()
        let archived = Fixtures.summary(title: Self.buildTitle, folder: Self.otherFolder)
        directory.register(archived)
        try await Self.archive([archived], in: directory)

        let output = try await Self.answer(
            "rename session", [("id", "@\(Self.buildSlug)"), ("title", Self.newTitle)], in: directory)

        #expect(output.contains(Self.listSessionsVerb), "output was: \(output)")
        #expect(try await Fixtures.summary(of: archived.id, in: directory).title == Self.buildTitle)
    }
}
