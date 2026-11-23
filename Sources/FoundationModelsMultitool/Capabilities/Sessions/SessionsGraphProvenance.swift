// The `SessionImportProvenance` type of the `sessions` GraphQL endpoint: the
// `importedFrom` field of a session tells where an imported session came
// from (D209). The directory keeps the provenance of each imported session,
// for example of a session that `continueExternalSession` made from a
// session of another agent (D212).

import Foundation
import FoundationModelsExtras
import Graphiti

/// The `SessionImportProvenance` type: where an imported session came from
/// (D209).
struct SessionsGraphImportProvenance: Sendable {
    /// The agent that recorded the source session.
    let agent: String

    /// The id of the source session in the store of that agent.
    let sourceId: String

    /// The path of the file of the source session.
    let sourcePath: String

    /// The title that the source reader found for the source session, or
    /// `nil` when the reader found no title.
    let sourceTitle: String?

    /// The time of the last record of the source session, or `nil` when the
    /// source gives no time.
    let sourceLastDate: DateTime?

    /// The time of the import.
    let importedAt: DateTime

    /// The number of records of the source that the import did not read.
    let skippedRecordCount: Int

    /// Makes the object of a provenance of the directory.
    ///
    /// - Parameter provenance: The provenance.
    init(_ provenance: SessionImportProvenance) {
        agent = provenance.agent
        sourceId = provenance.sourceID
        sourcePath = provenance.sourcePath
        sourceTitle = provenance.sourceTitle
        sourceLastDate = provenance.sourceLastDate.map(DateTime.init)
        importedAt = DateTime(provenance.importedAt)
        skippedRecordCount = provenance.skippedRecordCount
    }
}

extension SessionsGraphAPI {
    /// The `SessionImportProvenance` type.
    ///
    /// - Returns: The type.
    static func importProvenanceType() -> SchemaType {
        Type(SessionsGraphImportProvenance.self, as: "SessionImportProvenance") {
            Field("agent", at: \.agent).description("The agent that recorded the source session, for example codex.")
            Field("sourceId", at: \.sourceId).description("The id of the source session in the store of that agent.")
            Field("sourcePath", at: \.sourcePath).description("The path of the file of the source session.")
            Field("sourceTitle", at: \.sourceTitle)
                .description(
                    "The title of the source session that the import found, for example from a summary record or from "
                        + "the first prompt, or null when the import found no title.")
            Field("sourceLastDate", at: \.sourceLastDate)
                .description(
                    "The time of the last record of the source session, or null when the source gives no time.")
            Field("importedAt", at: \.importedAt).description("The time of the import.")
            Field("skippedRecordCount", at: \.skippedRecordCount)
                .description("The number of records of the source session that the import did not read.")
        }
        .description(
            "Where an imported session came from. It stays when the file of the source session is no longer there.")
    }
}
