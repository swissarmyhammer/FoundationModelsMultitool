// `SessionsToolShareTests` — the `share session`, `update share` and
// `stop sharing` operations of the `sessions` tool (D208 (k)), and the host
// protocol `SessionSharer`.
//
// Each case uses its own `InMemorySessionDirectory` and its own fake sharer
// from the fixtures. Each case reads the calls of the fake after the call of
// the tool, so it proves what the tool asked the sharer to do, and not only
// the text of the answer. No case waits for a time.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing
import ULID

@testable import FoundationModelsMultitool

/// Behavioral tests for the share operations of ``SessionsTool``.
@Suite("SessionsToolShareTests", .ownsTemporaryDirectories)
struct SessionsToolShareTests {

    // MARK: - Constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The op string of `share session`.
    private static let shareOp = "share session"

    /// The op string of `update share`.
    private static let updateOp = "update share"

    /// The op string of `stop sharing`.
    private static let stopOp = "stop sharing"

    /// The title of the session that the reference cases name.
    private static let otherTitle = "Parser review"

    /// The words of the corrective of a session with no share.
    private static let notSharedWords = "has no share"

    /// The text of the failure of the failing sharer.
    private static let failureText = "the iCloud account is signed out"

    /// The options of a share that has all four options different from the
    /// defaults of `share session`.
    private static let otherOptions = SessionShareOptions(
        includeThoughts: false, includeToolOutput: false, anyoneWithLink: false, keepUpdated: true)

    /// The fields of `share session` that ask for ``otherOptions``.
    private static var otherOptionFields: [(String, any ConvertibleToGeneratedContent)] {
        [("thoughts", false), ("toolOutput", false), ("anyoneWithLink", false), ("keepUpdated", true)]
    }

    // MARK: - Helpers

    /// Calls one operation as the caller.
    ///
    /// - Parameters:
    ///   - op: The op string.
    ///   - fields: The fields of the operation.
    ///   - sharer: The sharer of the tool, or `nil` for none.
    ///   - directory: The directory of the tool.
    /// - Returns: The answer of the tool.
    /// - Throws: What the tool throws.
    private static func callAsCaller(
        _ op: String,
        _ fields: [(String, any ConvertibleToGeneratedContent)] = [],
        sharer: (any SessionSharer)?,
        in directory: InMemorySessionDirectory = InMemorySessionDirectory()
    ) async throws -> String {
        let tool = try SessionsTool(directory: directory, sharer: sharer)
        return try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(arguments: Fixtures.payload(op, fields))
        }
    }

    /// Calls one operation as the caller, after the caller session got a
    /// share with `options`.
    ///
    /// - Parameters:
    ///   - op: The op string.
    ///   - fields: The fields of the operation.
    ///   - options: The options of the existing share of the caller.
    ///   - sharer: The sharer of the tool, with no share at the start.
    /// - Returns: The caller id and the answer of the tool.
    /// - Throws: What the tool throws.
    private static func callAsSharedCaller(
        _ op: String,
        _ fields: [(String, any ConvertibleToGeneratedContent)] = [],
        options: SessionShareOptions = .defaults,
        sharer: RecordingSessionSharer
    ) async throws -> (callerID: ULID, output: String) {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory, sharer: sharer)
        return try await Fixtures.asCaller(in: directory) { callerID in
            _ = try await sharer.share(callerID, options: options)
            return (callerID, try await tool.call(arguments: Fixtures.payload(op, fields)))
        }
    }

    // MARK: - share session

    @Test("share session with no id shares the caller session")
    func shareWithNoIDSharesTheCaller() async throws {
        let directory = InMemorySessionDirectory()
        let sharer = RecordingSessionSharer()
        let tool = try SessionsTool(directory: directory, sharer: sharer)

        let callerID = try await Fixtures.asCaller(in: directory) { callerID in
            _ = try await tool.call(arguments: Fixtures.payload(Self.shareOp))
            return callerID
        }

        #expect(await sharer.calls == [.share(callerID, .defaults)])
    }

    @Test("the defaults of share session: the thoughts, the tool output, anyone with the link, and not kept updated")
    func theDefaultsOfShareSession() {
        #expect(
            SessionShareOptions.defaults
                == SessionShareOptions(
                    includeThoughts: true, includeToolOutput: true, anyoneWithLink: true, keepUpdated: false))
    }

    @Test("share session with each option gives the options to the sharer")
    func shareWithEachOptionGivesTheOptions() async throws {
        let sharer = RecordingSessionSharer()

        _ = try await Self.callAsCaller(
            Self.shareOp,
            Self.otherOptionFields,
            sharer: sharer)

        #expect(await sharer.calls.map(\.options) == [Self.otherOptions])
    }

    @Test("share session with the id, @<short id> or @<slug> shares that session", arguments: SessionReferenceForm.allCases)
    func shareWithAReferenceSharesThatSession(_ form: SessionReferenceForm) async throws {
        let directory = InMemorySessionDirectory()
        let other = Fixtures.summary(title: Self.otherTitle)
        directory.register(other)
        let sharer = RecordingSessionSharer()

        _ = try await Self.callAsCaller(Self.shareOp, [("id", form.text(for: other))], sharer: sharer, in: directory)

        #expect(await sharer.calls == [.share(other.id, .defaults)])
    }

    @Test("share session of a session that has a share makes no new share")
    func shareOfASharedSessionMakesNoNewShare() async throws {
        let sharer = RecordingSessionSharer()

        let (callerID, _) = try await Self.callAsSharedCaller(
            Self.shareOp, [("keepUpdated", true)], options: Self.otherOptions, sharer: sharer)

        #expect(await sharer.calls == [.share(callerID, Self.otherOptions)])
    }

    @Test("share session of a session that has a share gives the existing share")
    func shareOfASharedSessionGivesTheExistingShare() async throws {
        let sharer = RecordingSessionSharer()

        let (callerID, output) = try await Self.callAsSharedCaller(
            Self.shareOp, options: Self.otherOptions, sharer: sharer)

        let existing = RecordingSessionSharer.share(of: callerID, options: Self.otherOptions)
        #expect(output == SessionsToolText.shareAnswer(existing, of: callerID, change: .existing))
    }

    // MARK: - The answer

    @Test("the answer of share session gives the URL of the share")
    func theAnswerGivesTheURL() async throws {
        let sharer = RecordingSessionSharer()

        let (callerID, output) = try await Self.callAsSharedCaller(Self.updateOp, sharer: sharer)

        #expect(output.contains(RecordingSessionSharer.url(of: callerID).absoluteString), "output was: \(output)")
    }

    /// One fact of the state of a share, and the words of the answer that
    /// tell it for ``SessionsToolShareTests/otherOptions``.
    enum ShareStateFact: String, CaseIterable, Sendable {
        /// Only the invited people can open the share.
        case access = "Who can open it: only the invited people."
        /// The share has no thoughts.
        case thoughts = "Thoughts: not in the share."
        /// The share has no tool output.
        case toolOutput = "Tool output: not in the share."
        /// The share is kept updated.
        case keepUpdated = "Keep Updated: on."
    }

    @Test("the answer of share session gives the state of the share", arguments: ShareStateFact.allCases)
    func theAnswerGivesTheState(_ fact: ShareStateFact) async throws {
        let output = try await Self.callAsCaller(
            Self.shareOp,
            Self.otherOptionFields,
            sharer: RecordingSessionSharer())

        #expect(output.contains(fact.rawValue), "output was: \(output)")
    }

    @Test("the answer of share session does not give the content of the share")
    func theAnswerDoesNotGiveTheContent() async throws {
        let output = try await Self.callAsCaller(Self.shareOp, sharer: RecordingSessionSharer())

        #expect(!output.contains(RecordingSessionSharer.content), "output was: \(output)")
    }

    // MARK: - update share

    @Test("update share with keepUpdated changes only the switch of the share")
    func updateWithKeepUpdatedChangesTheSwitch() async throws {
        let sharer = RecordingSessionSharer()

        let (callerID, _) = try await Self.callAsSharedCaller(
            Self.updateOp, [("keepUpdated", false)], options: Self.otherOptions, sharer: sharer)

        var expected = Self.otherOptions
        expected.keepUpdated = false
        #expect(await sharer.calls.last == .update(callerID, expected))
    }

    @Test("update share with no keepUpdated updates the share with its options")
    func updateWithNoKeepUpdatedKeepsTheOptions() async throws {
        let sharer = RecordingSessionSharer()

        let (callerID, _) = try await Self.callAsSharedCaller(
            Self.updateOp, options: Self.otherOptions, sharer: sharer)

        #expect(await sharer.calls.last == .update(callerID, Self.otherOptions))
    }

    @Test("update share of a session with no share gives NOT_SHARED and updates nothing")
    func updateWithNoShareIsNotShared() async throws {
        let sharer = RecordingSessionSharer()

        let output = try await Self.callAsCaller(Self.updateOp, sharer: sharer)

        #expect(output.contains(Self.notSharedWords), "output was: \(output)")
        #expect(await sharer.calls.isEmpty)
    }

    // MARK: - stop sharing

    @Test("stop sharing stops the share of the caller session")
    func stopSharingStopsTheShare() async throws {
        let sharer = RecordingSessionSharer()

        let (callerID, _) = try await Self.callAsSharedCaller(Self.stopOp, sharer: sharer)

        #expect(await sharer.calls.last == .stop(callerID))
    }

    @Test("stop sharing of a session with no share gives NOT_SHARED and stops nothing")
    func stopWithNoShareIsNotShared() async throws {
        let sharer = RecordingSessionSharer()

        let output = try await Self.callAsCaller(Self.stopOp, sharer: sharer)

        #expect(output.contains(Self.notSharedWords), "output was: \(output)")
        #expect(await sharer.calls.isEmpty)
    }

    @Test("the shared stop of a session with no share throws the code NOT_SHARED")
    func theSharedStopThrowsNotShared() async throws {
        let refusal = await #expect(throws: SessionsRefusal.self) {
            try await SessionsToolContext.stopSharing(ULID(), with: RecordingSessionSharer())
        }

        #expect(refusal?.code == "NOT_SHARED")
    }

    // MARK: - No sharer and a failing sharer

    @Test(
        "each share operation with no sharer gives the corrective of SHARING_UNAVAILABLE",
        arguments: [shareOp, updateOp, stopOp])
    func eachOperationWithNoSharerIsUnavailable(_ op: String) async throws {
        let output = try await Self.callAsCaller(op, sharer: nil)

        #expect(output == SessionsToolText.noSharer)
    }

    @Test("the shared check of no sharer throws the code SHARING_UNAVAILABLE")
    func theSharedCheckThrowsSharingUnavailable() throws {
        let refusal = #expect(throws: SessionsRefusal.self) {
            try SessionsToolContext.requiredSharer(nil)
        }

        #expect(refusal?.code == "SHARING_UNAVAILABLE")
    }

    @Test("each share operation with a failing sharer gives a corrective that names the failure", arguments: [shareOp, updateOp, stopOp])
    func eachOperationWithAFailingSharerIsACorrective(_ op: String) async throws {
        let sharer = FailingSessionSharer(failure: SessionSharerFailure(description: Self.failureText))

        let output = try await Self.callAsCaller(op, sharer: sharer)

        #expect(output.contains(Self.failureText), "output was: \(output)")
    }

    @Test("the shared share with a failing sharer throws the code SHARE_FAILED")
    func theSharedShareThrowsShareFailed() async throws {
        let sharer = FailingSessionSharer(failure: SessionSharerFailure(description: Self.failureText))

        let refusal = await #expect(throws: SessionsRefusal.self) {
            try await SessionsToolContext.share(ULID(), options: .defaults, with: sharer)
        }

        #expect(refusal?.code == "SHARE_FAILED")
    }

    @Test("share session with no caller session gives a corrective and shares nothing")
    func shareWithNoCallerIsACorrective() async throws {
        let sharer = RecordingSessionSharer()
        let tool = try SessionsTool(directory: InMemorySessionDirectory(), sharer: sharer)

        _ = try await tool.call(arguments: Fixtures.payload(Self.shareOp))

        #expect(await sharer.calls.isEmpty)
    }

    // MARK: - Aliases

    @Test("the verb publish is an alias of share")
    func publishIsAnAliasOfShare() async throws {
        let sharer = RecordingSessionSharer()

        _ = try await Self.callAsCaller("publish session", sharer: sharer)

        #expect(await sharer.calls.count == 1)
    }

    @Test("the verb refresh is an alias of update")
    func refreshIsAnAliasOfUpdate() async throws {
        let sharer = RecordingSessionSharer()

        let (callerID, _) = try await Self.callAsSharedCaller("refresh share", sharer: sharer)

        #expect(await sharer.calls.last == .update(callerID, .defaults))
    }

    @Test("the parameter includeThoughts is an alias of thoughts")
    func includeThoughtsIsAnAliasOfThoughts() async throws {
        let sharer = RecordingSessionSharer()

        _ = try await Self.callAsCaller(Self.shareOp, [("includeThoughts", false)], sharer: sharer)

        #expect(await sharer.calls.map(\.options?.includeThoughts) == [false])
    }

    // MARK: - The host API

    @Test("a tool with no sharer uses the sharer that the endpoint of its directory keeps")
    func aToolWithNoSharerUsesTheSharerOfTheEndpoint() async throws {
        let directory = InMemorySessionDirectory()
        let sharer = RecordingSessionSharer()
        let endpoint = SessionsGraph.endpoint(of: directory, sharer: sharer)

        _ = try await Self.callAsCaller(Self.shareOp, sharer: nil, in: directory)
        withExtendedLifetime(endpoint) {}

        #expect(await sharer.calls.count == 1)
    }

    @Test("the default stream of the share changes finishes with no element")
    func theDefaultShareChangesFinishWithNoElement() async {
        let sharer = FailingSessionSharer(failure: SessionSharerFailure(description: Self.failureText))

        let first = await sharer.shareChanges().first { _ in true }

        #expect(first == nil)
    }
}

extension SessionSharerCall {
    /// The options of a share or an update call, or `nil` for a stop.
    var options: SessionShareOptions? {
        switch self {
        case .share(_, let options), .update(_, let options):
            options
        case .stop:
            nil
        }
    }
}
