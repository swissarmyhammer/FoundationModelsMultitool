// `SessionTranscriptExporter` — the Markdown of the transcript of a session,
// which the host gives (D202 (g)).
//
// This package does not link FoundationModelsACP. The session updates and the
// renderer of the Markdown are in FoundationModelsACP, and the history of a
// session is in FoundationModelsACPAgent. Thus the host gives the Markdown
// through this protocol, and the `export session` operation of the
// `sessions` tool and the `sessions` endpoint call it.

import ULID

/// Gives the Markdown of the transcript of a session.
///
/// A host gives one to ``SessionsTool/init(directory:exporter:searcher:sharer:importer:)``
/// and to ``SessionsGraph/endpoint(of:exporter:searcher:sharer:importer:)``. With no exporter, the
/// `export session` operation gives a corrective that names the UI command
/// Export as Markdown….
public protocol SessionTranscriptExporter: Sendable {
    /// The Markdown of the transcript of a session.
    ///
    /// - Parameters:
    ///   - session: The id of the session.
    ///   - includeThoughts: True to include the thoughts of the agent, each
    ///     one as a `<details>` block.
    /// - Returns: The Markdown document.
    /// - Throws: An error when the host does not keep the history of the
    ///   session, or cannot render it.
    func markdown(of session: ULID, includeThoughts: Bool) async throws -> String
}
