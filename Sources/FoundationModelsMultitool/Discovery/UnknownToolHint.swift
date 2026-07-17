import Foundation

/// Builds the did-you-mean repair hint appended to a `runCode` error when a
/// snippet called a `tools.*` path that does not exist.
///
/// The wrong-guess moment is the highest-leverage point in the whole
/// search-then-call interaction: a model that invents `tools.getTrip` and
/// receives only JavaScriptCore's bare `TypeError` routinely gives up —
/// narrating a plan or fabricating an answer instead of repairing. This
/// type turns that dead end into a ramp: it extracts the failed path from
/// the exception message, ranks the catalog's real entries by name
/// similarity, and renders the closest matches in the same
/// signature-plus-example block format `findAPIs` results use — so the
/// repair material is already in the exact shape the model knows how to
/// call.
enum UnknownToolHint {
    /// The maximum number of closest-match entries a hint shows.
    private static let suggestionLimit = 3

    /// The minimum trigram-similarity score for an entry to count as a
    /// close match at all — below this, every candidate is noise and the
    /// hint steers back to `findAPIs` instead of suggesting a wrong turn.
    private static let similarityThreshold = 0.2

    /// Builds the hint for one failed snippet, or nil when the failure has
    /// nothing to do with an unknown `tools.*` path.
    ///
    /// Scans `message` for `tools.<path>` references and hints on the first
    /// one naming a path the catalog does not contain. A message whose every
    /// `tools.*` reference is a real path (e.g. a mis-called existing tool)
    /// produces no hint — that error is already repairable as rendered.
    ///
    /// - Parameters:
    ///   - message: the thrown JS exception's message text.
    ///   - surface: the catalog to rank suggestions from.
    /// - Returns: the hint text, or nil when no unknown path was referenced.
    static func hint(message: String, surface: APISurface) -> String? {
        let knownPaths = Set(surface.entries.map(\.path))
        guard let failedPath = firstUnknownPath(in: message, knownPaths: knownPaths) else {
            return nil
        }

        let suggestions = closestEntries(to: failedPath, in: surface)
        guard !suggestions.isEmpty else {
            return "tools.\(failedPath) does not exist, and nothing close matches. "
                + "Call findAPIs to discover the available functions."
        }

        let blocks = suggestions.map { entry in
            "\(entry.block)\nExample: \(entry.qualifiedExample)"
        }
        return "tools.\(failedPath) does not exist. Closest available functions:\n\n"
            + blocks.joined(separator: "\n\n")
    }

    /// Extracts the first `tools.<path>` reference in `message` whose path
    /// is not a known catalog entry, or nil when every reference is real
    /// (or there are none).
    ///
    /// - Parameters:
    ///   - message: the exception message to scan.
    ///   - knownPaths: every valid `APISurface.Entry.path`.
    /// - Returns: the first unknown dotted path, without its `tools.` prefix.
    private static func firstUnknownPath(in message: String, knownPaths: Set<String>) -> String? {
        let pattern = /tools\.([A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*)/
        for match in message.matches(of: pattern) {
            let path = String(match.1)
            if !knownPaths.contains(path) {
                return path
            }
        }
        return nil
    }

    /// Ranks the catalog's entries by name similarity to `failedPath` and
    /// returns the closest few above `similarityThreshold`.
    ///
    /// Similarity is deterministic and dependency-free: case-insensitive
    /// containment in either direction (an invented `getCities` contains
    /// the real `cities`; an invented `temp.getCurrent` contains the real
    /// `temp`) scores highest, with character-trigram overlap as the
    /// general fallback for guesses that share word stems without
    /// containing each other.
    ///
    /// - Parameters:
    ///   - failedPath: the unknown dotted path the snippet called.
    ///   - surface: the catalog to rank.
    /// - Returns: up to `suggestionLimit` entries, best match first.
    private static func closestEntries(to failedPath: String, in surface: APISurface) -> [APISurface.Entry] {
        let failed = failedPath.lowercased()
        let scored: [(entry: APISurface.Entry, score: Double)] = surface.entries.compactMap { entry in
            let candidate = entry.path.lowercased()
            let containment = failed.contains(candidate) || candidate.contains(failed) ? 1.0 : 0.0
            let score = max(containment, trigramSimilarity(failed, candidate))
            return score >= similarityThreshold ? (entry, score) : nil
        }
        return
            scored
            .sorted { $0.score > $1.score }
            .prefix(suggestionLimit)
            .map(\.entry)
    }

    /// Computes the Jaccard similarity of the two strings' character
    /// trigram sets, in 0...1.
    ///
    /// - Parameters:
    ///   - a: one lowercased name.
    ///   - b: the other lowercased name.
    /// - Returns: `|trigrams(a) ∩ trigrams(b)| / |trigrams(a) ∪ trigrams(b)|`,
    ///   or 0 when either name is too short to have a trigram.
    private static func trigramSimilarity(_ a: String, _ b: String) -> Double {
        let trigramsA = trigrams(of: a)
        let trigramsB = trigrams(of: b)
        guard !trigramsA.isEmpty, !trigramsB.isEmpty else { return 0 }
        let intersection = trigramsA.intersection(trigramsB).count
        let union = trigramsA.union(trigramsB).count
        return Double(intersection) / Double(union)
    }

    /// Splits `text` into its set of 3-character substrings.
    ///
    /// - Parameter text: the (lowercased) name to split.
    /// - Returns: every consecutive 3-character window in `text`.
    private static func trigrams(of text: String) -> Set<String> {
        let characters = Array(text)
        guard characters.count >= 3 else { return [] }
        return Set((0...(characters.count - 3)).map { String(characters[$0..<($0 + 3)]) })
    }
}
