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
/// format `searchTools` results use — so the repair material is already in the
/// exact shape the model knows how to call.
///
/// Ranking runs in two tiers, in this order:
///
/// 1. **Name resemblance** — case-insensitive containment in either
///    direction, with character-trigram overlap as its own fallback. Exact
///    and free, and it settles the common guess: `getWeatherForecast`
///    contains `getWeather`, `getTemperature.getCurrent` contains
///    `getTemperature`.
/// 2. **Catalog relevance** — the same `MetadataSearcher` ranking `searchTools`
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
///
/// Alongside the suggestions, a resolution carries a ``RepairDirective`` —
/// what the error's closing line should tell the model to do next. The
/// suggestions answer "which function did you mean"; the directive answers
/// the prior question, "is guessing again worth anything here at all". See
/// `repairDirective(tier:snippet:knownPaths:)`.
enum UnknownToolHint {
    /// How every hint says a `tools.*` path is not in the catalog.
    ///
    /// The only place the phrase is written. Both branches of
    /// ``text(forFailed:suggesting:directive:)`` build their opening from it,
    /// and `SampleSnippet`'s unknown-path feedback uses it too, so a reword
    /// moves all three together. `UnknownToolHintTests` negates against it
    /// rather than restating it: a copy in the test would go on satisfying
    /// `!output.contains(_:)` after a reword, passing for the wrong reason —
    /// the same trap this file already documents for the two closing lines.
    static let missingPathPhrase = "does not exist"

    /// Which of the two ranking tiers answered a guess.
    enum SuggestionTier: String {
        /// Tier 1 answered it — some catalog name resembles the guess.
        case nameResemblance = "resemblance"

        /// Tier 1 found nothing and tier 2 answered it — no catalog name
        /// resembles the guess, but an entry's rendered block does.
        case catalogRelevance = "relevance"

        /// Neither tier answered it, so the hint steers back to `searchTools`.
        case noMatch = "none"
    }

    /// One unknown-`tools.*`-path detection: what the model reached for,
    /// what the catalog offered back, and the text that carries the offer.
    struct Resolution {
        /// The `tools.*` path the model invented, without its `tools.`
        /// prefix.
        let imaginedPath: String

        /// Which tier answered `imaginedPath`.
        let tier: SuggestionTier

        /// The catalog paths the hint names, best match first — empty when
        /// `tier` is `noMatch`.
        let suggestedPaths: [String]

        /// What the repairable error's closing line should tell the model to
        /// do next — see `repairDirective(tier:snippet:knownPaths:)`.
        let directive: RepairDirective

        /// The hint text appended to the model's repairable error.
        let text: String

        /// This detection rendered as one greppable log line.
        ///
        /// A host's log is where the synonym corpus accumulates, so the
        /// shape is a parsing contract rather than prose: a fixed leading
        /// token, then `key=value` fields in a fixed order. Every value is
        /// delimiter-free by construction — a `tools.*` path is identifier
        /// characters and dots (`referencedToolPaths(in:)`'s pattern), a
        /// catalog path is the same, and a tier is one of three
        /// fixed words — so a reader can split on spaces and `=` and get
        /// `(imagined, suggested, tier)` back without a regex. The
        /// suggestion list is bracketed so that "no suggestion" reads as an
        /// empty list rather than as a missing field.
        var logMessage: String {
            "\(UnknownToolHint.logPrefix) imagined=\(imaginedPath) tier=\(tier.rawValue) "
                + "suggested=[\(suggestedPaths.joined(separator: ","))]"
        }
    }

    /// The leading token every imagined-tool log line carries, so one `grep`
    /// picks the corpus out of a host's whole log.
    static let logPrefix = "imaginedTool"

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

    /// The character-window width `trigrams(of:)` splits a name into — the
    /// "tri" in trigram, and what makes `trigramSimilarity(_:_:)` a trigram
    /// overlap rather than an n-gram overlap at some other width.
    private static let trigramLength = 3

    /// The characters that separate words inside a `tools.*` path: the dotted
    /// path's own separator, plus the two non-alphanumeric characters a
    /// JavaScript identifier may contain (`referencedToolPaths(in:)`'s
    /// pattern).
    private static let wordSeparators: Set<Character> = [".", "_", "$"]

    /// Resolves one failed snippet's unknown `tools.*` path, or nil when the
    /// failure has nothing to do with an unknown path.
    ///
    /// Scans `message` for `tools.<path>` references and hints on the first
    /// one naming a path the catalog does not contain. A message whose every
    /// `tools.*` reference is a real path (e.g. a mis-called existing tool)
    /// produces no hint — that error is already repairable as rendered.
    ///
    /// The result carries the ranking's own account of itself (which path
    /// was imagined, which tier answered it, what it offered) alongside the
    /// text, because a caller wants both: the text goes back to the model,
    /// and the account goes to the host's log.
    ///
    /// - Parameters:
    ///   - message: the thrown JS exception's message text.
    ///   - snippet: the model's own `runCode` source, without the `tools.*`
    ///     glue preamble — read to decide the directive, never to rank.
    ///   - surface: the catalog to rank suggestions from.
    ///   - searcher: the catalog-relevance ranker, which must be indexing
    ///     exactly `surface.entries` — otherwise tier 2 can suggest a path
    ///     the snippet's own `tools.*` glue does not define.
    /// - Returns: the resolution, or nil when no unknown path was
    ///   referenced.
    static func hint(
        message: String,
        snippet: String,
        surface: APISurface,
        searcher: MetadataSearcher<APISurface.Entry>
    ) async -> Resolution? {
        // The two sibling paths are real bindings the preamble installs, not
        // catalog entries, so the surface alone does not know them. Without
        // this a snippet that reaches for `tools.searchTools` — which the
        // model does unprompted (task `bwk7knm`) — is told the path it just
        // used successfully does not exist.
        let knownPaths = Set(surface.entries.map(\.path)).union(MultiTool.siblingToolPaths)
        guard let failedPath = firstUnknownPath(in: message, knownPaths: knownPaths) else {
            return nil
        }

        let ranked = await closestEntries(to: failedPath, in: surface, using: searcher)
        let directive = repairDirective(tier: ranked.tier, snippet: snippet, knownPaths: knownPaths)
        return Resolution(
            imaginedPath: failedPath,
            tier: ranked.tier,
            suggestedPaths: ranked.entries.map(\.path),
            directive: directive,
            text: text(forFailed: failedPath, suggesting: ranked.entries, directive: directive)
        )
    }

    /// Decides what the repairable error should tell the model to do next.
    ///
    /// Discovery is named only where repairing cannot work: a guess no tier
    /// could answer, written in a snippet that reached for nothing the
    /// catalog defines. Both halves are load-bearing. A guess that resolved
    /// to a near match already has its repair material in hand, and a snippet
    /// that also names a real path proves the model is holding real names
    /// already — in both cases the snippet is the thing to fix, and steering
    /// to `searchTools` would send a working session backwards.
    ///
    /// Note what this does *not* read: whether `searchTools` was actually called
    /// this session. `SearchToolsTool` is a separate `Tool` a host mounts (or
    /// does not mount) independently, holding no session state and touching
    /// no `ToolContext`, so that fact is not reachable here without new
    /// cross-tool coupling. The snippet's own paths are the observable
    /// proxy — weaker, because a model can hold a real name without having
    /// searched, and that is exactly the case this leaves alone.
    ///
    /// - Parameters:
    ///   - tier: which tier answered the failed guess.
    ///   - snippet: the model's own `runCode` source.
    ///   - knownPaths: every valid `APISurface.Entry.path`.
    /// - Returns: the directive the error's closing line renders.
    private static func repairDirective(
        tier: SuggestionTier,
        snippet: String,
        knownPaths: Set<String>
    ) -> RepairDirective {
        guard tier == .noMatch else { return .repairSnippet }
        let reached = referencedToolPaths(in: snippet).contains { knownPaths.contains($0) }
        return reached ? .repairSnippet : .discoverFunctions
    }

    /// Renders the hint text handed back to the model.
    ///
    /// - Parameters:
    ///   - failedPath: the unknown dotted path the snippet called.
    ///   - suggestions: the entries to name, best match first, or empty when
    ///     no tier could answer the guess.
    ///   - directive: what the error's closing line will already tell the
    ///     model to do, so the no-suggestion branches lead into that closing
    ///     line instead of competing with it.
    /// - Returns: the hint text.
    private static func text(
        forFailed failedPath: String,
        suggesting suggestions: [APISurface.Entry],
        directive: RepairDirective
    ) -> String {
        guard !suggestions.isEmpty else {
            let opening = "tools.\(failedPath) \(missingPathPhrase), and nothing close matches. "
            switch directive {
            case .repairSnippet:
                return opening + "Call searchTools for the real path, then rewrite that call."
            case .discoverFunctions:
                return opening + "No function name this snippet used is in the catalog."
            }
        }

        let blocks = suggestions.map { entry in
            "\(entry.block)\nExample: \(entry.qualifiedExample)"
        }
        let instruction = suggestions.count == 1
            ? "Call tools.\(suggestions[0].path) instead."
            : "Call tools.\(suggestions[0].path) instead, or one of the others listed."
        return "tools.\(failedPath) \(missingPathPhrase). \(instruction)\n\n"
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
        referencedToolPaths(in: message).first { !knownPaths.contains($0) }
    }

    /// Extracts every `tools.<path>` reference in `text`, in the order they
    /// appear, without their `tools.` prefix.
    ///
    /// Lexical, and deliberately so: it reads the same way whether it is
    /// handed a thrown exception's message or the model's own snippet source,
    /// which is what lets one pattern answer both "which path failed" and
    /// "did this snippet reach for anything real".
    ///
    /// Internal (not `private`), rather than duplicated, because the same
    /// question — "which `tools.*` paths does this text name" — is what
    /// `SampleSnippet`'s gate asks of a generated candidate before it will
    /// hand it to the model. One pattern, one answer, whether the text is a
    /// thrown message, the model's own snippet, or a generated one.
    ///
    /// - Parameter text: the exception message or snippet source to scan.
    /// - Returns: the referenced dotted paths, duplicates included.
    static func referencedToolPaths(in text: String) -> [String] {
        let pattern = /tools\.([A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*)/
        return text.matches(of: pattern).map { String($0.1) }
    }

    /// Ranks the catalog's entries against `failedPath`, best match first,
    /// and reports which tier produced the ranking.
    ///
    /// Runs the two tiers described on the type: name resemblance first,
    /// catalog relevance only when name resemblance found nothing.
    ///
    /// - Parameters:
    ///   - failedPath: the unknown dotted path the snippet called.
    ///   - surface: the catalog to rank.
    ///   - searcher: the catalog-relevance ranker over `surface.entries`.
    /// - Returns: the answering tier and the entries to suggest, best match
    ///   first — `noMatch` and an empty list when neither tier found
    ///   anything worth naming.
    private static func closestEntries(
        to failedPath: String,
        in surface: APISurface,
        using searcher: MetadataSearcher<APISurface.Entry>
    ) async -> (tier: SuggestionTier, entries: [APISurface.Entry]) {
        let byName = entriesResemblingName(of: failedPath, in: surface)
        guard byName.isEmpty else { return (.nameResemblance, byName) }
        let byRelevance = await entriesRelevantTo(failedPath, using: searcher)
        return (byRelevance.isEmpty ? .noMatch : .catalogRelevance, byRelevance)
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
    /// Forwards to the same `MetadataSearcher` ranking `searchTools` answers
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
            switch wordBoundary(at: character, continuing: word) {
            case .separator:
                words.append(word)
                word = ""
            case .wordStart:
                words.append(word)
                word = String(character)
            case .continuation:
                word.append(character)
            }
        }
        words.append(word)
        return words.filter { !$0.isEmpty }.joined(separator: " ").lowercased()
    }

    /// What one character of a dotted, camel-cased `tools.*` path does to the
    /// word `intent(spelling:)` is accumulating.
    private enum WordBoundary {
        /// A `wordSeparators` character: it closes the word before it and is
        /// part of no word itself.
        case separator

        /// The first character of a new word — where camel case splits.
        case wordStart

        /// A character that continues the word being accumulated.
        case continuation
    }

    /// Classifies one character of a dotted, camel-cased path by the word
    /// boundary it introduces.
    ///
    /// Separate from `intent(spelling:)`'s loop so that deciding *what* a
    /// character is stays apart from acting on it: the loop reads as the three
    /// things that can happen to the word being accumulated, and this reads as
    /// the classification alone.
    ///
    /// - Parameters:
    ///   - character: the character to classify.
    ///   - word: the word accumulated so far, which is what decides whether an
    ///     uppercase character starts a new word or is simply the first
    ///     character of the current one.
    /// - Returns: the boundary `character` introduces.
    private static func wordBoundary(at character: Character, continuing word: String) -> WordBoundary {
        if wordSeparators.contains(character) { return .separator }
        return character.isUppercase && !word.isEmpty ? .wordStart : .continuation
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

    /// Splits `text` into its set of `trigramLength`-character substrings.
    ///
    /// - Parameter text: the (lowercased) name to split.
    /// - Returns: every consecutive `trigramLength`-character window in `text`.
    private static func trigrams(of text: String) -> Set<String> {
        let characters = Array(text)
        guard characters.count >= trigramLength else { return [] }
        return Set(
            (0...(characters.count - trigramLength)).map {
                String(characters[$0..<($0 + trigramLength)])
            }
        )
    }
}
