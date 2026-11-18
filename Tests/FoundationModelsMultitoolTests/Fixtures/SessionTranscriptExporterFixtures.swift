import Foundation
import ULID

@testable import FoundationModelsMultitool

/// One call of ``RecordingTranscriptExporter``: the session and the
/// thoughts option that the exporter got.
struct TranscriptExportRequest: Equatable, Sendable {
    /// The session to export.
    let session: ULID

    /// Whether the call asked for the thoughts of the agent.
    let includeThoughts: Bool
}

/// A fake ``SessionTranscriptExporter``: it gives the same text for each
/// session, and it records each call, so a case can read what the operation
/// asked for.
actor RecordingTranscriptExporter: SessionTranscriptExporter {
    /// The text of each export.
    let text: String

    /// Each call, the oldest first.
    private(set) var requests: [TranscriptExportRequest] = []

    /// Makes the exporter.
    ///
    /// - Parameter text: The text of each export.
    init(text: String) {
        self.text = text
    }

    /// Records the call, and gives ``text``.
    ///
    /// - Parameters:
    ///   - session: The session to export.
    ///   - includeThoughts: Whether the call asked for the thoughts.
    /// - Returns: ``text``.
    func markdown(of session: ULID, includeThoughts: Bool) async throws -> String {
        requests.append(TranscriptExportRequest(session: session, includeThoughts: includeThoughts))
        return text
    }
}

/// The error of ``FailingTranscriptExporter``.
struct TranscriptExportFailure: Error, CustomStringConvertible {
    /// The text of the failure.
    let description: String
}

/// A fake ``SessionTranscriptExporter`` whose each export fails.
struct FailingTranscriptExporter: SessionTranscriptExporter {
    /// The error of each export.
    let failure: TranscriptExportFailure

    /// Throws ``failure``.
    ///
    /// - Parameters:
    ///   - session: The session to export.
    ///   - includeThoughts: Whether the call asked for the thoughts.
    /// - Returns: Never.
    /// - Throws: ``failure``.
    func markdown(of session: ULID, includeThoughts: Bool) async throws -> String {
        throw failure
    }
}
