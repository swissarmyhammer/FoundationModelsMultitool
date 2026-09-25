// `Search` — the `tools.web.search` verb (web.md § "The surface" and
// § "Corrections, not throws").
//
// The verb is a plain `FoundationModels.Tool` that holds the `WebContext` of
// the web capability, in the pattern of `Capabilities/Files/Read.swift`. The
// capability supplies the noun, thus the verb's `name` is the bare `search`
// and the surface path renders as `tools.web.search`.
//
// The verb checks its arguments, then gives one query to the search chain of
// the context. It never fetches a page (web.md § "Decisions", item 2). It is
// synchronous and does not conform to `BackgroundTool` (item 3).
//
// A bad argument and a failed search stay IN BAND, as a `correction` beside
// no results. The verb never throws for them: each one is a mistake that the
// model corrects inside the turn, and a thrown error would end the turn.

import Foundation
import FoundationModels

/// The arguments of `tools.web.search`: the query, the number of results,
/// the age limit, and the one host of the results.
@Generable
struct SearchArguments {
    /// The text to search for.
    @Guide(description: "The text to search for, 1 to 500 characters.")
    var query: String

    /// The number of results, or `nil` for 10.
    @Guide(description: "The number of results, 1 to 20. Omit it to get 10 results.")
    var count: Int?

    /// The age limit name, or `nil` for no age limit.
    @Guide(description: "The age limit of the results: day, week, month, or year. Omit it for no age limit.")
    var freshness: String?

    /// The one host name that the results must come from, or `nil` for all hosts.
    @Guide(description: "One host name that each result must come from, for example developer.apple.com.")
    var site: String?
}

/// The result of `tools.web.search`: the ranked hits, or the correction that
/// says why there are none.
///
/// `correction` and the hits are exclusive. A search that gives hits has no
/// correction, and a correction has no provider, no hit, and no note.
@Generable(description: "the ranked hits of a web search, or the correction that says why there are none.")
struct SearchResult {
    /// The provider that gave the hits, for example `braveHTML`. Empty on a
    /// correction.
    var provider: String

    /// The hits, with rank 1 first. Empty on a correction.
    var results: [WebHit]

    /// The providers that the search skipped and the arguments that the
    /// provider ignored, or `nil` when there are none.
    var notes: [String]?

    /// Why the search gave no hits, or `nil` when the hits stand.
    var correction: String?
}

extension Search {
    // MARK: Bounds

    /// The largest number of characters in a query, after the trim.
    private static let maximumQueryLength = 500

    /// The number of results of a search that omits `count`.
    private static let defaultCount = 10

    /// The largest accepted `count`.
    private static let maximumCount = 20

    /// The bound on `count`: a result count from 1 to ``maximumCount``.
    private static let countBound = BoundParameter(
        parameterName: "count", typeDescription: "result count", minimum: 1, maximum: maximumCount)

    /// The characters of a host name other than the ASCII letters and
    /// digits.
    private static let hostNamePunctuation: Set<Character> = ["-", "."]

    // MARK: Corrective messages

    /// The correction for a query that is empty or too long after the trim.
    private static let queryCorrection =
        "The `query` parameter must have 1 to \(maximumQueryLength) characters after the white space at each "
        + "end is removed."

    /// The correction for an unknown `freshness`, with the accepted names.
    private static let freshnessCorrection = EnumParameter.unknownValueMessage(
        validNames: SearchFreshness.allCases.map(\.rawValue), parameterName: "freshness")

    /// The correction for a `site` that is not one host name.
    ///
    /// - Parameter site: The rejected value.
    /// - Returns: The correction, with the value at the end.
    private static func siteCorrection(_ site: String) -> String {
        "The `site` parameter must be one host name, for example developer.apple.com: \(site)"
    }

    // MARK: Execution

    /// Checks the arguments, searches, and gives the hits, or the correction
    /// that says why there are none.
    ///
    /// - Parameter arguments: The query, the count, the age limit, and the
    ///   site.
    /// - Returns: The hits of the first provider that gave hits, or the
    ///   correction. Nothing here throws for a bad argument or a failed
    ///   search.
    func call(arguments: SearchArguments) async throws -> SearchResult {
        let limit = arguments.count ?? Self.defaultCount
        return await Self.query(from: arguments).resolveAsync(corrective: Self.corrective) { query in
            Self.result(of: await context.searchChain.search(query), limit: limit)
        }
    }

    /// Checks the arguments and makes the query of the chain.
    ///
    /// The checks run in the order of the arguments and stop at the first
    /// failure, because a correction is one message.
    ///
    /// - Parameter arguments: The arguments of the call.
    /// - Returns: The query, or the rejection with its correction.
    private static func query(from arguments: SearchArguments) -> Result<SearchQuery, CorrectiveRejection> {
        let text = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...maximumQueryLength).contains(text.count) else {
            return .failure(CorrectiveRejection(correctiveMessage: queryCorrection))
        }
        if let message = countBound.violation(arguments.count) {
            return .failure(CorrectiveRejection(correctiveMessage: message))
        }
        return freshness(named: arguments.freshness).flatMap { freshness in
            if let site = arguments.site, !isHostName(site) {
                return .failure(CorrectiveRejection(correctiveMessage: siteCorrection(site)))
            }
            return .success(SearchQuery(text: text, count: arguments.count, freshness: freshness, site: arguments.site))
        }
    }

    /// Finds the age limit of a `freshness` name. The lookup ignores case.
    ///
    /// - Parameter name: The name, or `nil` when the call omits `freshness`.
    /// - Returns: The age limit, or `nil` for no name; else the rejection
    ///   that names the accepted values.
    private static func freshness(named name: String?) -> Result<SearchFreshness?, CorrectiveRejection> {
        guard let name else { return .success(nil) }
        guard let freshness = SearchFreshness(rawValue: name.lowercased()) else {
            return .failure(CorrectiveRejection(correctiveMessage: freshnessCorrection))
        }
        return .success(freshness)
    }

    /// Tells if a text is one host name: not empty, and only ASCII letters,
    /// ASCII digits, `-`, and `.`. Thus a scheme, a path, a port, and a space
    /// are each refused.
    ///
    /// - Parameter text: The value of `site`.
    /// - Returns: `true` when the text is one host name.
    private static func isHostName(_ text: String) -> Bool {
        !text.isEmpty
            && text.allSatisfy { character in
                (character.isASCII && (character.isLetter || character.isNumber))
                    || hostNamePunctuation.contains(character)
            }
    }

    /// Makes the result of an outcome of the chain.
    ///
    /// - Parameters:
    ///   - outcome: The hits and the notes, or the correction.
    ///   - limit: The maximum number of hits. A provider with no count field
    ///     can give more hits than the call asked for.
    /// - Returns: The result. An empty list of notes becomes `nil`.
    private static func result(of outcome: SearchOutcome, limit: Int) -> SearchResult {
        switch outcome {
        case .hits(let provider, let hits, let notes):
            SearchResult(
                provider: provider, results: Array(hits.prefix(limit)), notes: notes.isEmpty ? nil : notes,
                correction: nil)
        case .correction(let message):
            corrective(message)
        }
    }

    /// A result that holds only a correction: no provider, no hit, no note.
    ///
    /// - Parameter message: The correction that the model reads and acts on.
    /// - Returns: The corrective result.
    private static func corrective(_ message: String) -> SearchResult {
        SearchResult(provider: "", results: [], notes: nil, correction: message)
    }
}

/// Searches the web, and gives ranked hits: rank, title, URL, and snippet.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const found = await tools.web.search({ query: "swift concurrency", count: 3 });
/// ```
///
/// The verb never fetches a page. The search chain of the context tries the
/// providers in order, and the first provider that gives hits wins. A bad
/// argument and a failed search each come back as a `correction`, not as an
/// error. The context is the context that the web capability owns, thus
/// `search` and `fetch` of one capability share one session.
struct Search: Tool {
    /// The verb that this tool renders as, after the web noun:
    /// `tools.web.search`.
    let name = "search"

    /// The usage instructions, as the model reads them.
    let description = """
        search finds pages on the web. Use it when the answer is not in the files or in what you \
        know, or to find the URL of a page. It gives ranked hits: rank, title, url, and snippet. It \
        never fetches a page. The normal pattern is tools.web.search then tools.web.fetch in one \
        snippet: search, keep the best hits, and fetch them. Promise.all fetches pages in parallel, \
        for example await Promise.all(found.results.map(hit => tools.web.fetch({ url: hit.url }))). \
        query has 1 to 500 characters. count is 1 to 20 (default 10). freshness is day, week, month, \
        or year. site limits the hits to one host name, for example developer.apple.com. notes tell \
        which providers were skipped and which arguments were ignored. A bad argument or a failed \
        search comes back as a correction rather than as an error — read it, correct the call, and \
        ask again.
        """

    /// The web context that this verb searches with, which the web
    /// capability owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Search(context:)`.
    let context: WebContext
}
