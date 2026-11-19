import Foundation
import FoundationModels
import FoundationModelsExtras
import ULID

@testable import FoundationModelsMultitool

/// The error of a fake importer.
struct SessionImporterFailure: Error, CustomStringConvertible {
    /// The text of the failure.
    let description: String
}

/// A fake ``SessionImporter`` over an `InMemorySessionDirectory`.
///
/// It keeps a fixed list of source sessions. `importSession(_:)` makes a real
/// session in the directory with the provenance of the source, as the
/// importer of FoundationModelsACPAgent does. `importable(_:)` reads the
/// earlier imports of each source from the provenance of the sessions of the
/// directory, so a case sees each import that it made.
///
/// The fake records each request and each order, so a case proves what the
/// tool asked the importer to do.
actor RecordingSessionImporter: SessionImporter {
    /// The number of records that each import of the fake does not read.
    static let skippedRecordCount = 3

    /// The fixed time of each import of the fake.
    static let importedAt = Date(timeIntervalSince1970: SessionsToolFixtures.fixedSecondsSince1970)

    /// The directory that gets the new sessions.
    private let directory: InMemorySessionDirectory

    /// The source sessions that the fake can import, with no earlier import.
    private let sources: [ImportableSession]

    /// The agents whose sessions the fake cannot read.
    private let unreadableSources: [String]

    /// The folders in which the fake cannot make a session.
    private let unavailableFolders: [URL]

    /// Each request of `importable(_:)`, the oldest first.
    private(set) var requests: [ImportableSessionsRequest] = []

    /// Each order of `importSession(_:)`, the oldest first.
    private(set) var orders: [SessionImportOrder] = []

    /// Makes the importer.
    ///
    /// - Parameters:
    ///   - directory: The directory that gets the new sessions.
    ///   - sources: The source sessions that the fake can import.
    ///   - unreadableSources: The agents whose sessions the fake cannot read.
    ///     The default is none.
    ///   - unavailableFolders: The folders in which the fake cannot make a
    ///     session. The default is none.
    init(
        directory: InMemorySessionDirectory, sources: [ImportableSession], unreadableSources: [String] = [],
        unavailableFolders: [URL] = []
    ) {
        self.directory = directory
        self.sources = sources
        self.unreadableSources = unreadableSources
        self.unavailableFolders = unavailableFolders
    }

    /// A source session of `agent` in `folder`, with no earlier import.
    ///
    /// - Parameters:
    ///   - agent: The source agent.
    ///   - sourceID: The id of the source session.
    ///   - title: The title of the source session, or `nil`.
    ///   - folder: The working folder of the source session.
    ///   - turnCount: The number of turns.
    /// - Returns: The source session, whose last record is at the fixed date.
    static func source(
        agent: String, sourceID: String, title: String?, folder: URL, turnCount: Int
    ) -> ImportableSession {
        ImportableSession(
            agent: agent, sourceID: sourceID, sourcePath: "/sources/\(agent)/\(sourceID).jsonl", title: title,
            folder: folder, lastDate: SessionsToolFixtures.fixedDate, turnCount: turnCount, previousImports: [])
    }

    /// Records the request, and gives each source of its agent and its folder
    /// with its earlier imports.
    ///
    /// - Parameter request: The request.
    /// - Returns: The page, with the agents that the fake cannot read.
    /// - Throws: Each error of the directory.
    func importable(_ request: ImportableSessionsRequest) async throws -> ImportableSessionsPage {
        requests.append(request)
        let imported = try await directory.sessions(matching: SessionQuery(includesRecorded: true))
        let matching = sources.filter { source in
            (request.agent ?? source.agent) == source.agent && (request.folder ?? source.folder) == source.folder
        }
        return ImportableSessionsPage(
            sessions: matching.prefix(request.limit).map { Self.withImports($0, among: imported) }, nextCursor: nil,
            unreadableSources: unreadableSources)
    }

    /// Records the order, and makes a new session of the source in the
    /// directory.
    ///
    /// - Parameter order: The order.
    /// - Returns: The new session.
    /// - Throws: ``SessionImportError`` for an agent that the fake cannot
    ///   read and for a folder in which it cannot make a session;
    ///   ``SessionImporterFailure`` for a source that it does not have.
    func importSession(_ order: SessionImportOrder) async throws -> SessionImportResult {
        orders.append(order)
        if unreadableSources.contains(order.agent) {
            throw SessionImportError.sourceUnreadable(agent: order.agent)
        }
        let source = try self.source(of: order)
        let folder = order.folder ?? source.folder ?? SessionsToolFixtures.workingFolder
        if unavailableFolders.contains(folder) {
            throw SessionImportError.folderUnavailable(folder)
        }
        let summary = try await directory.importSession(
            Self.request(for: source, folder: folder, name: order.name), transcript: Transcript())
        return SessionImportResult(
            session: summary.id, name: summary.title ?? "", skippedRecordCount: Self.skippedRecordCount)
    }

    /// The source that an order names by its id.
    ///
    /// - Parameter order: The order.
    /// - Returns: The source.
    /// - Throws: ``SessionImporterFailure`` when no source has the agent and
    ///   the id of the order.
    private func source(of order: SessionImportOrder) throws -> ImportableSession {
        let source = sources.first { $0.agent == order.agent && $0.sourceID == order.source }
        return try source ?? { throw SessionImporterFailure(description: "no source \(order.source)") }()
    }

    /// The import request of the directory for a source.
    ///
    /// - Parameters:
    ///   - source: The source session.
    ///   - folder: The working folder of the new session.
    ///   - name: The name of the order, or `nil`.
    /// - Returns: The request, with the provenance of the source.
    private static func request(for source: ImportableSession, folder: URL, name: String?) -> SessionImportRequest {
        SessionImportRequest(
            workingDirectory: folder, title: name ?? source.title ?? "\(source.agent)-import",
            provenance: SessionImportProvenance(
                agent: source.agent, sourceID: source.sourceID, sourcePath: source.sourcePath,
                sourceLastDate: source.lastDate, importedAt: importedAt, skippedRecordCount: skippedRecordCount))
    }

    /// A source with each import of it among the sessions of the directory.
    ///
    /// - Parameters:
    ///   - source: The source session.
    ///   - sessions: The sessions of the directory.
    /// - Returns: The source with its earlier imports.
    private static func withImports(_ source: ImportableSession, among sessions: [SessionSummary]) -> ImportableSession
    {
        var source = source
        source.previousImports = sessions.compactMap { summary in
            summary.importedFrom.flatMap { provenance in
                provenance.agent == source.agent && provenance.sourceID == source.sourceID
                    ? SessionPreviousImport(session: summary.id, importedAt: provenance.importedAt) : nil
            }
        }
        return source
    }
}

/// A fake ``SessionImporter`` whose each call fails.
struct FailingSessionImporter: SessionImporter {
    /// The error of each call.
    let failure: SessionImporterFailure

    /// Throws ``failure``.
    ///
    /// - Parameter request: The request.
    /// - Returns: Never.
    /// - Throws: ``failure``.
    func importable(_ request: ImportableSessionsRequest) async throws -> ImportableSessionsPage {
        throw failure
    }

    /// Throws ``failure``.
    ///
    /// - Parameter order: The order.
    /// - Returns: Never.
    /// - Throws: ``failure``.
    func importSession(_ order: SessionImportOrder) async throws -> SessionImportResult {
        throw failure
    }
}
