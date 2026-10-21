import Foundation
import FoundationModels
import FoundationModelsExtras
import ULID

@testable import FoundationModelsMultitool

/// The shared fixtures of the ``SessionsTool`` tests: the facts of each
/// registered session, the `op` payload of a call, and the caller session of a
/// stub run.
enum SessionsToolFixtures {
    /// The seconds from 1970 to ``fixedDate``: a time in January 2027.
    static let fixedSecondsSince1970: TimeInterval = 1_800_000_000

    /// The fixed time of each summary of a case.
    static let fixedDate = Date(timeIntervalSince1970: fixedSecondsSince1970)

    /// The working folder of each registered session.
    static let workingFolder = URL(fileURLWithPath: "/work/project")

    /// The agent id of each registered session.
    static let agentID = "coder"

    /// The display name of the agent of each registered session.
    static let agentName = "Coder"

    /// The folder that the launcher of ``directoryWithLauncher(agentIDs:)``
    /// gives a start with no folder and no starter.
    static let launcherFolder = URL(fileURLWithPath: "/work/agents")

    /// A directory whose launcher knows `agentIDs` and the default agent, with
    /// a fixed clock, so two directories stamp the same times.
    ///
    /// - Parameter agentIDs: The agent ids that the launcher knows, each as it
    ///   is written. ``agentID`` when not given.
    /// - Returns: The directory.
    static func directoryWithLauncher(agentIDs: [String] = [agentID]) -> InMemorySessionDirectory {
        InMemorySessionDirectory(
            launcher: InMemorySessionDirectory.Launcher(agentIDs: agentIDs, defaultWorkingDirectory: launcherFolder),
            now: { fixedDate })
    }

    /// A live, idle session, by default a root session of ``agentID`` in
    /// ``workingFolder``.
    ///
    /// - Parameters:
    ///   - id: The session id.
    ///   - tags: The tags of the session.
    ///   - title: The title of the session.
    ///   - agent: The agent id of the session, as it is written.
    ///   - folder: The working folder of the session.
    ///   - kind: The kind of the session. The default is a root session.
    ///   - parentID: The parent of a subagent, or the original of a fork.
    ///   - startedBy: The session that started this root session.
    /// - Returns: The summary.
    static func summary(
        id: ULID = ULID(),
        tags: Set<String> = [],
        title: String? = nil,
        agent: String = agentID,
        folder: URL = workingFolder,
        kind: SessionKind = .root,
        parentID: ULID? = nil,
        startedBy: ULID? = nil
    ) -> SessionSummary {
        SessionSummary(
            id: id, agentID: agent, agentName: agentName, workingDirectory: folder, title: title, tags: tags,
            kind: kind, state: .idle, parentID: parentID, startedBy: startedBy, origin: .client, createdAt: fixedDate,
            updatedAt: fixedDate, isLive: true)
    }

    /// The `op` payload of one operation with its fields.
    ///
    /// - Parameters:
    ///   - op: The op string.
    ///   - fields: The fields of the operation.
    /// - Returns: The payload.
    static func payload(_ op: String, _ fields: [(String, any ConvertibleToGeneratedContent)] = [])
        -> GeneratedContent
    {
        GeneratedContent(properties: [("op", op)] + fields, uniquingKeysWith: { _, new in new })
    }

    /// Runs `body` with the context of a stub run bound, after it registers a
    /// session with the id of that run in `directory`.
    ///
    /// - Parameters:
    ///   - directory: The directory that gets the caller session.
    ///   - body: The work that runs as the caller, given the caller id.
    /// - Returns: What `body` returned.
    /// - Throws: What the stub run or `body` throws.
    static func asCaller<Result>(
        in directory: InMemorySessionDirectory, _ body: (ULID) async throws -> Result
    ) async throws -> Result {
        try await withOuterRunContext { context in
            directory.register(summary(id: context.sessionID))
            return try await ToolContext.$current.withValue(context) { try await body(context.sessionID) }
        }
    }
}
