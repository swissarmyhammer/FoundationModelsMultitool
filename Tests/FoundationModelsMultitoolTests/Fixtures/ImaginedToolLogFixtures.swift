import Logging
import TelemetryTestSupport

@testable import FoundationModelsMultitool

/// One `imaginedTool` log record, read back from its metadata into the triple
/// that the synonym-mining use needs.
///
/// The read here is the other half of the contract that `UnknownToolHint
/// .Resolution.logMetadata` writes: the record is only useful if a later
/// script can turn it back into `(imagined, suggested, tier)`. Thus the tests
/// read the record back through its metadata keys, and not through the text of
/// a message.
struct ImaginedToolLogRecord: Equatable {
    /// The `tools.*` path the model invented, without its `tools.` prefix.
    let imagined: String

    /// Which ranking tier answered the guess — `UnknownToolHint
    /// .SuggestionTier`'s raw value.
    let tier: String

    /// The catalog paths the hint offered, in the order it offered them.
    let suggested: [String]
}

extension ImaginedToolLogRecord {
    /// Reads one `imaginedTool` record back from its metadata, or fails when
    /// the metadata does not hold the three values of the record.
    ///
    /// - Parameter metadata: The metadata of one log record, or the
    ///   `logMetadata` of one `UnknownToolHint.Resolution`.
    init?(metadata: Logger.Metadata) {
        guard case .string(let imagined)? = metadata[MultitoolTelemetry.LogMetadataKey.imaginedPath.rawValue],
            case .string(let tier)? = metadata[MultitoolTelemetry.LogMetadataKey.suggestionTier.rawValue],
            case .array(let suggested)? = metadata[MultitoolTelemetry.LogMetadataKey.suggestedPaths.rawValue]
        else {
            return nil
        }
        self.init(imagined: imagined, tier: tier, suggested: suggested.map { "\($0)" })
    }

    /// Every `imaginedTool` record that `context` holds, in the order of the
    /// calls.
    ///
    /// - Parameter context: The capture that holds the records.
    /// - Returns: The records at the `.notice` level, read back from their
    ///   metadata.
    static func records(in context: TelemetryCapture.Context) -> [ImaginedToolLogRecord] {
        LogReadback.records(.imaginedTool, in: context)
            .filter { $0.level == .notice }
            .compactMap { ImaginedToolLogRecord(metadata: $0.metadata) }
    }
}
