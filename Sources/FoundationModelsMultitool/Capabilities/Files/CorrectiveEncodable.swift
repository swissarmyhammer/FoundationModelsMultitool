// `CorrectiveEncodable` — the shared wire shape of a two-case verb outcome.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// CorrectiveEncodable.swift`, unchanged in behavior. The sibling declares
// the protocol `public`; this package keeps it internal, the same way
// `PathGuard` and `FileChangeSet` beside it do. The conformers are
// `GlobOutput` (landed with the glob task, ^4cmvjqh) and the wire-shape
// fixture in `CorrectiveVocabularyTests`; the grep output arrives with the
// grep task (^2j06zb7).
//
// eventplan.md § "Consolidation of the siblings": a corrective result stays
// in band, never thrown, and it encodes as a single `corrective` field.

import Foundation

/// The single coding key for a corrective outcome's `corrective` message field.
///
/// Shared by the ``CorrectiveEncodable`` default encoding, thus the
/// corrective wire shape (`{"corrective": "…"}`) is defined in exactly one
/// place.
private enum CorrectiveCodingKey: String, CodingKey {
    /// The corrective-message field.
    case corrective
}

/// A return-don't-throw verb outcome: an inline success result or a corrective message.
///
/// The glob and grep outputs are each a two-case enum — a `content` case
/// carrying the successful result, or a `corrective` case carrying a
/// message the model reads and acts on within the turn — and both encode
/// identically: the result's own fields inline on success, or a single
/// `corrective` field on a recoverable failure. Conforming to this protocol
/// shares that one ``encode(to:)`` (and its `corrective` coding key) rather
/// than copying the switch and its `CodingKeys` into each output type.
///
/// A conformer reports its two mutually exclusive projections —
/// ``successResult`` (non-`nil` for a successful outcome) and
/// ``correctiveMessage`` (non-`nil` for a corrective outcome) — of which
/// exactly one is non-`nil`.
protocol CorrectiveEncodable: Encodable {
    /// The successful result encoded inline.
    associatedtype Success: Encodable

    /// The successful result, or `nil` when this is a corrective outcome.
    var successResult: Success? { get }

    /// The corrective message, or `nil` when this is a successful outcome.
    var correctiveMessage: String? { get }
}

extension CorrectiveEncodable {
    /// Encodes the outcome.
    ///
    /// A successful outcome encodes its ``successResult`` inline (its own
    /// fields at the top level); a corrective outcome encodes a single
    /// `corrective` field carrying the ``correctiveMessage``. Exactly one
    /// projection is non-`nil`, thus the two branches are mutually
    /// exclusive.
    ///
    /// - Parameter encoder: the encoder to write the outcome into.
    /// - Throws: An error if the encoder fails to encode a value.
    func encode(to encoder: Encoder) throws {
        if let correctiveMessage {
            var container = encoder.container(keyedBy: CorrectiveCodingKey.self)
            try container.encode(correctiveMessage, forKey: .corrective)
        } else if let successResult {
            try successResult.encode(to: encoder)
        }
    }
}
