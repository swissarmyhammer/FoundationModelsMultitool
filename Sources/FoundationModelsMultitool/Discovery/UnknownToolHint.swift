import Foundation
import FoundationModelsMetadataRegistry

/// Builds the did-you-mean repair hint appended to a `runCode` error when a
/// snippet called a `tools.*` path that does not exist.
///
/// The wrong-guess moment is the highest-leverage point in the whole
/// search-then-call interaction: a model that invents `tools.getItinerary`
/// and receives only JavaScriptCore's bare `TypeError` routinely gives up —
/// narrating a plan or fabricating an answer instead of repairing. This
/// type turns that dead end into a ramp: it extracts the failed path from
/// the exception message, ranks the catalog's real entries against it, and
/// renders the closest matches in the same signature-plus-example block
/// format `findAPIs` results use — so the repair material is already in the
/// exact shape the model knows how to call.
///
/// Ranking runs in two tiers, in this order:
///
/// 1. **Name resemblance** — case-insensitive containment in either
///    direction, with character-trigram overlap as its own fallback. Exact
///    and free, and it settles the common guess: `getWeatherForecast`
///    contains `getWeather`, `getTemperature.getCurrent` contains
///    `getTemperature`.
/// 2. **Catalog relevance** — the same `MetadataSearcher` ranking `findAPIs`
///    matches an intent to tools with, over the same entries. This tier
///    exists because name resemblance has a hard ceiling: a guess can be a
///    perfectly reasonable synonym of a real entry and still share almost no
///    characters with it. `getItinerary` against a catalog holding `getTrip`
///    is the worked case — containment fails in both directions and trigram
///    Jaccard is ≈0.07, so tier 1 rejects it as noise, while the entry's
///    rendered block — which is what the searcher ranks — says "the cities on
///    the user's current trip, in itinerary order". Lowering tier 1's
///    threshold to reach that would admit genuine noise everywhere else;
///    ranking by what an entry is *for* reaches it directly.
///
///    The evidence originally recorded here was a real gated run guessing
///    `getTrip` against a `tripCities` fixture. The human ruling of
///    2026-08-07 (task `tkrdwb8`) reclassified that run: ten of the twelve
///    tools mounted alongside it were verbNoun, so the model was inferring
///    the catalog's convention correctly and the fixture was the outlier.
///    That specific evidence is withdrawn. The tier stands on the general
///    case above — real host catalogs do mix conventions, and a synonym is
///    not a spelling mistake.
///
/// Tier 2 runs only when tier 1 finds nothing, so every guess that already
/// resolved by name resolves identically, and it runs retrieval-only — no
/// selection tier, no embedder — so repairing a wrong guess costs no model
/// call and no tokens.
enum UnknownToolHint {
    /// The maximum number of name-resemblance matches a hint shows.
    private static let resemblanceSuggestionLimit = 3

    /// The number of catalog-relevance matches a hint shows — exactly the
    /// best one.
    ///
    /// This limit is the cut, not a description of what the ranking produces.
    /// Asked for its full ranking, the searcher answers a `getItinerary` guess
    /// against a five-tool travel catalog with `["getTrip", "getWeather"]` and
    /// nothing further, however high the limit goes (measured 2026-08-07): the
    /// right entry first, then one that has nothing to do with looking up a
    /// trip. Passing 1 here is what drops the runner-up, so a hint built from
    /// this tier names one entry — which is what
    /// `catalogRelevanceHintNamesOnlyItsBestMatch` asserts.
    ///
    /// Tier 1 can afford a list because every entry it returns cleared
    /// `similarityThreshold`; tier 2's ranking is relative, with no absolute
    /// floor, so its runners-up are simply whatever ranked at all — and naming
    /// them hands a model that just guessed a function name more names to
    /// guess.
    private static let relevanceSuggestionLimit = 1

    /// The minimum name-resemblance score for an entry to count as a close
    /// match at all — below this, tier 1 has nothing and ranking falls
    /// through to catalog relevance.
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
    ///   - searcher: the catalog-relevance ranker, which must be indexing
    ///     exactly `surface.entries` — otherwise tier 2 can suggest a path
    ///     the snippet's own `tools.*` glue does not define.
    /// - Returns: the hint text, or nil when no unknown path was referenced.
    static func hint(
        message: String,
        surface: APISurface,
        searcher: MetadataSearcher<APISurface.Entry>
    ) async -> String? {
        let knownPaths = Set(surface.entries.map(\.path))
        guard let failedPath = firstUnknownPath(in: message, knownPaths: knownPaths) else {
            return nil
        }

        let suggestions = await closestEntries(to: failedPath, in: surface, using: searcher)
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

    /// Ranks the catalog's entries against `failedPath`, best match first.
    ///
    /// Runs the two tiers described on the type: name resemblance first,
    /// catalog relevance only when name resemblance found nothing.
    ///
    /// - Parameters:
    ///   - failedPath: the unknown dotted path the snippet called.
    ///   - surface: the catalog to rank.
    ///   - searcher: the catalog-relevance ranker over `surface.entries`.
    /// - Returns: the entries to suggest, best match first, or empty when
    ///   neither tier found anything worth naming.
    private static func closestEntries(
        to failedPath: String,
        in surface: APISurface,
        using searcher: MetadataSearcher<APISurface.Entry>
    ) async -> [APISurface.Entry] {
        let byName = entriesResemblingName(of: failedPath, in: surface)
        guard byName.isEmpty else { return byName }
        return await entriesRelevantTo(failedPath, using: searcher)
    }

    /// Ranks the catalog's entries by name resemblance to `failedPath` and
    /// returns the closest few above `similarityThreshold` — the hint's
    /// tier 1.
    ///
    /// Resemblance is deterministic and dependency-free: case-insensitive
    /// containment in either direction (an invented `getCitiesVisited`
    /// contains the real `getCities`; an invented
    /// `getTemperature.getCurrent` contains the real `getTemperature`)
    /// scores highest, with character-trigram overlap as the
    /// general fallback for guesses that share word stems without
    /// containing each other.
    ///
    /// - Parameters:
    ///   - failedPath: the unknown dotted path the snippet called.
    ///   - surface: the catalog to rank.
    /// - Returns: up to `resemblanceSuggestionLimit` entries, best match
    ///   first.
    private static func entriesResemblingName(
        of failedPath: String,
        in surface: APISurface
    ) -> [APISurface.Entry] {
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
            .prefix(resemblanceSuggestionLimit)
            .map(\.entry)
    }

    /// Ranks the catalog's entries by how relevant they are to what
    /// `failedPath` was reaching for — the hint's tier 2.
    ///
    /// Forwards to the same `MetadataSearcher` ranking `findAPIs` answers
    /// with, so a wrong guess is resolved by the one ranking the catalog
    /// already trusts rather than by a second, hint-only notion of "close".
    /// The searcher's contract is a plain-language intent, so the identifier
    /// is spelled out as words first (see `intent(spelling:)`).
    ///
    /// A ranking failure yields no suggestions rather than propagating: the
    /// hint is decoration on an already-repairable error, and turning a
    /// snippet the model can fix into a thrown tool error would lose the
    /// repair entirely. Unreachable in practice — `search(intent:limit:)`
    /// only throws when asked for a selection tier that was never configured,
    /// and this searcher is retrieval-only.
    ///
    /// - Parameters:
    ///   - failedPath: the unknown dotted path the snippet called.
    ///   - searcher: the catalog-relevance ranker.
    /// - Returns: the `relevanceSuggestionLimit` best-ranked entries.
    private static func entriesRelevantTo(
        _ failedPath: String,
        using searcher: MetadataSearcher<APISurface.Entry>
    ) async -> [APISurface.Entry] {
        let intent = intent(spelling: failedPath)
        let matches = try? await searcher.search(intent: intent, limit: relevanceSuggestionLimit)
        return (matches ?? []).map(\.item)
    }

    /// Spells a dotted, camel-cased `tools.*` path out as the plain-language
    /// intent the searcher's ranking signals tokenize.
    ///
    /// `getItinerary` is an identifier, not a query: as one token it shares
    /// nothing with an entry whose description reads "the cities on the
    /// user's current trip, in itinerary order", while `get itinerary`
    /// matches on `itinerary` directly.
    /// This is query formulation for the searcher's documented input, not a
    /// scoring rule of its own — the ranking stays entirely the searcher's.
    ///
    /// - Parameter failedPath: the unknown dotted path the snippet called.
    /// - Returns: the path's words, lowercased and space-separated.
    private static func intent(spelling failedPath: String) -> String {
        var words: [String] = []
        var word = ""
        for character in failedPath {
            if character == "." || character == "_" || character == "$" {
                words.append(word)
                word = ""
            } else if character.isUppercase, !word.isEmpty {
                words.append(word)
                word = String(character)
            } else {
                word.append(character)
            }
        }
        words.append(word)
        return words.filter { !$0.isEmpty }.joined(separator: " ").lowercased()
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
