// `SessionSearchQueryTests` — the parse of the query of a session search
// (D207 (e), Q64), and the value types of `SessionTranscriptSearcher`
// (^r2mc120).

import Foundation
import FoundationModelsExtras
import Testing
import ULID

@testable import FoundationModelsMultitool

/// The parse of a session search query: the words, the phrases, the
/// exclusions, the tokens, the dates and the ranking text.
@Suite("SessionSearchQueryTests")
struct SessionSearchQueryTests {

    /// The time zone of each parse, so that no test depends on the zone of the
    /// machine.
    private static let zone = TimeZone.gmt

    /// The first instant of a day in ``zone``.
    ///
    /// - Parameters:
    ///   - year: The year.
    ///   - month: The month, 1 to 12.
    ///   - day: The day of the month.
    /// - Returns: The date at midnight of that day.
    private static func midnight(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    /// Parses `text` in ``zone``.
    ///
    /// - Parameter text: The query.
    /// - Returns: The parsed query.
    private static func parse(_ text: String) throws -> SessionSearchQuery {
        try SessionSearchQuery(parsing: text, timeZone: zone)
    }

    /// The refusal that the parse of `text` throws.
    ///
    /// - Parameter text: The query.
    /// - Returns: The refusal.
    private static func refusal(of text: String) throws -> SessionsRefusal {
        let error = #expect(throws: SessionsRefusal.self) {
            try parse(text)
        }
        return try #require(error)
    }

    // MARK: - Words, phrases and exclusions

    /// Plain words are the words of the query.
    @Test func plainWordsAreTheWords() throws {
        #expect(try Self.parse("retry budget").words == ["retry", "budget"])
    }

    /// A text in quotes is a phrase.
    @Test func aQuotedTextIsAPhrase() throws {
        #expect(try Self.parse("\"retry budget\" timeout").phrases == ["retry budget"])
    }

    /// A phrase is not a word.
    @Test func aPhraseIsNotAWord() throws {
        #expect(try Self.parse("\"retry budget\" timeout").words == ["timeout"])
    }

    /// The space in a phrase becomes one space.
    @Test func thePhraseSpaceBecomesOneSpace() throws {
        #expect(try Self.parse("\"  retry \t budget  \"").phrases == ["retry budget"])
    }

    /// A quote with no closing quote makes a phrase to the end of the query.
    @Test func anUnclosedQuoteRunsToTheEnd() throws {
        #expect(try Self.parse("timeout \"retry budget").phrases == ["retry budget"])
    }

    /// A pair of quotes with no text is no phrase.
    @Test func anEmptyPhraseIsDropped() throws {
        #expect(try Self.parse("timeout \"\"").phrases.isEmpty)
    }

    /// `-word` excludes the word.
    @Test func aDashWordIsExcluded() throws {
        #expect(try Self.parse("retry -flaky").excluded == ["flaky"])
    }

    /// An excluded word is not a word.
    @Test func anExcludedWordIsNotAWord() throws {
        #expect(try Self.parse("retry -flaky").words == ["retry"])
    }

    /// `-"two words"` excludes the phrase.
    @Test func aDashPhraseIsExcluded() throws {
        #expect(try Self.parse("retry -\"flaky test\"").excluded == ["flaky test"])
    }

    /// A lone `-` is no word and no exclusion.
    @Test func aLoneDashIsDropped() throws {
        let query = try Self.parse("retry -")

        #expect(query.words == ["retry"] && query.excluded.isEmpty, "query: \(query)")
    }

    /// A dash inside a word does not exclude it.
    @Test func aDashInsideAWordIsAWord() throws {
        #expect(try Self.parse("follow-up").words == ["follow-up"])
    }

    // MARK: - Kinds

    /// With no `from:` token, the kinds are each kind but `thought` (Q64).
    @Test func theDefaultKindsAreEachKindButThought() throws {
        let expected = Set(SessionSearchHit.Kind.allCases).subtracting([.thought])

        #expect(try Self.parse("retry").kinds == expected)
    }

    /// `from:thought` keeps only the thoughts.
    @Test func fromThoughtKeepsTheThoughts() throws {
        #expect(try Self.parse("retry from:thought").kinds == [.thought])
    }

    /// Two `from:` tokens keep the two kinds.
    @Test func twoFromTokensKeepTheTwoKinds() throws {
        #expect(try Self.parse("from:user from:tool").kinds == [.user, .tool])
    }

    /// Each `from:` value names its kind.
    @Test(arguments: [
        ("user", SessionSearchHit.Kind.user),
        ("agent", .agent),
        ("message", .message),
        ("tool", .tool),
        ("plan", .plan),
        ("thought", .thought),
    ])
    func eachFromValueNamesItsKind(value: String, kind: SessionSearchHit.Kind) throws {
        #expect(try Self.parse("from:\(value)").kinds == [kind])
    }

    /// The key and the value of a `from:` token can be in any letter case.
    @Test func aFromTokenIgnoresLetterCase() throws {
        #expect(try Self.parse("FROM:Thought").kinds == [.thought])
    }

    /// A `from:` token is not a word.
    @Test func aFromTokenIsNotAWord() throws {
        #expect(try Self.parse("retry from:user").words == ["retry"])
    }

    /// A `from:` value that names no kind is a corrective with the token.
    @Test func anUnknownFromValueNamesTheToken() throws {
        let refusal = try Self.refusal(of: "retry from:robot")

        #expect(refusal.message.contains("from:robot"), "message: \(refusal.message)")
    }

    /// `from:session` is a corrective: a session item does not pass a `from:`
    /// token (D207 (e)).
    @Test func fromSessionIsRefused() throws {
        #expect(try Self.refusal(of: "from:session").kind == .invalidQuery)
    }

    // MARK: - Dates

    /// `after:` gives the first instant of the day.
    @Test func afterGivesTheStartOfTheDay() throws {
        #expect(try Self.parse("after:2026-11-19").after == Self.midnight(2026, 11, 19))
    }

    /// `before:` gives the first instant of the day.
    @Test func beforeGivesTheStartOfTheDay() throws {
        #expect(try Self.parse("before:2026-01-02").before == Self.midnight(2026, 1, 2))
    }

    /// The day starts in the time zone of the parse.
    @Test func theDayStartsInTheTimeZoneOfTheParse() throws {
        let zone = try #require(TimeZone(secondsFromGMT: 3600))
        let query = try SessionSearchQuery(parsing: "after:2026-11-19", timeZone: zone)

        #expect(query.after == (try Self.midnight(2026, 11, 19)).addingTimeInterval(-3600))
    }

    /// Of two `after:` tokens, the later date is kept.
    @Test func twoAfterTokensKeepTheLaterDate() throws {
        #expect(try Self.parse("after:2026-11-19 after:2026-01-01").after == Self.midnight(2026, 11, 19))
    }

    /// Of two `before:` tokens, the earlier date is kept.
    @Test func twoBeforeTokensKeepTheEarlierDate() throws {
        #expect(try Self.parse("before:2026-11-19 before:2026-01-01").before == Self.midnight(2026, 1, 1))
    }

    /// The key of a date token can be in any letter case.
    @Test func aDateKeyIgnoresLetterCase() throws {
        #expect(try Self.parse("AFTER:2026-11-19").after == Self.midnight(2026, 11, 19))
    }

    /// A wrong date is a corrective with the token.
    @Test(arguments: [
        "after:yesterday", "before:2026-02-30", "after:2026-13-01", "after:26-11-19", "after:2026-1-9",
        "before:2026-11-19x", "after:2026-11-19T08:30:00Z",
    ])
    func aWrongDateNamesTheToken(token: String) throws {
        let refusal = try Self.refusal(of: "retry \(token)")

        #expect(refusal.message.contains(token), "message: \(refusal.message)")
    }

    /// A wrong date has the code `INVALID_QUERY`.
    @Test func aWrongDateHasTheInvalidQueryCode() throws {
        #expect(try Self.refusal(of: "after:yesterday").code == "INVALID_QUERY")
    }

    // MARK: - Directory tokens

    /// `@<session>` is a session reference, with no `@`.
    @Test func anAtTokenIsASessionReference() throws {
        #expect(try Self.parse("retry @fix-login").sessionReferences == ["fix-login"])
    }

    /// `#tag` is a tag, with no `#`.
    @Test func aHashTokenIsATag() throws {
        #expect(try Self.parse("retry #release").tags == ["release"])
    }

    /// `agent:` names an agent, in the letter case of the query.
    @Test func anAgentTokenNamesTheAgent() throws {
        #expect(try Self.parse("Agent:Claude").agents == ["Claude"])
    }

    /// `folder:` names a folder; `folder:.` is the folder of the tab.
    @Test func aFolderTokenNamesTheFolder() throws {
        #expect(try Self.parse("folder:. folder:/Users/me/app").folders == [".", "/Users/me/app"])
    }

    /// `is:archived` includes the archived sessions.
    @Test func isArchivedIncludesTheArchivedSessions() throws {
        #expect(try Self.parse("retry IS:Archived").includesArchived)
    }

    /// With no `is:archived` token, the archived sessions are not included.
    @Test func theArchivedSessionsAreNotIncludedByDefault() throws {
        #expect(try !Self.parse("retry").includesArchived)
    }

    /// An `is:` value other than `archived` is a corrective with the token.
    @Test func anUnknownIsValueNamesTheToken() throws {
        let refusal = try Self.refusal(of: "is:pinned")

        #expect(refusal.message.contains("is:pinned"), "message: \(refusal.message)")
    }

    /// A known key with no value is a corrective with the token.
    @Test func aKnownKeyWithNoValueNamesTheToken() throws {
        let refusal = try Self.refusal(of: "retry agent:")

        #expect(refusal.message.contains("agent:"), "message: \(refusal.message)")
    }

    /// A directory token is not a word.
    @Test func aDirectoryTokenIsNotAWord() throws {
        #expect(try Self.parse("@fix #release agent:claude folder:. is:archived retry").words == ["retry"])
    }

    /// A lone `@` or `#` is a plain word.
    @Test func aLoneMarkIsAPlainWord() throws {
        #expect(try Self.parse("@ #").words == ["@", "#"])
    }

    /// An unknown `key:` token is a plain word.
    @Test func anUnknownKeyIsAPlainWord() throws {
        #expect(try Self.parse("color:red").words == ["color:red"])
    }

    /// A token in quotes is a phrase, not a token.
    @Test func aQuotedTokenIsAPhrase() throws {
        #expect(try Self.parse("\"from:user\"").phrases == ["from:user"])
    }

    // MARK: - Ranking text

    /// The ranking text has the words and the phrases in the order of the
    /// query, with no tokens, no quotes and no exclusions.
    @Test func theRankingTextHasOnlyTheWordsAndThePhrases() throws {
        let query = try Self.parse(
            "retry \"token budget\" -flaky from:tool after:2026-01-01 @fix #release agent:claude folder:. "
                + "is:archived color:red")

        #expect(query.rankingText == "retry token budget color:red")
    }

    // MARK: - Queries with no words

    /// A query with only tokens is valid, and its ranking text is empty.
    @Test func aQueryWithOnlyTokensHasNoRankingText() throws {
        #expect(try Self.parse("from:tool #release after:2026-01-01").rankingText.isEmpty)
    }

    /// A query with only tokens keeps its tokens.
    @Test func aQueryWithOnlyTokensKeepsItsTokens() throws {
        let query = try Self.parse("from:tool #release")

        #expect(query.kinds == [.tool] && query.tags == ["release"], "query: \(query)")
    }

    /// An empty query is a corrective.
    @Test(arguments: ["", "   ", "-", "\"\""])
    func anEmptyQueryIsRefused(text: String) throws {
        #expect(try Self.refusal(of: text).kind == .blankText)
    }

    // MARK: - Value types

    /// A page goes through JSON and back with no change.
    @Test func aPageRoundTripsThroughJSON() throws {
        let hit = SessionSearchHit(
            entryID: "tool-1", kind: .tool, author: "claude", date: try Self.midnight(2026, 11, 19),
            snippet: "the retry budget", ranges: [4..<9], terms: ["retry"])
        let page = SessionSearchPage(
            sessions: [SessionSearchResult(session: ULID(), score: 0.5, hitCount: 3, hits: [hit])],
            nextCursor: "next", unavailableFolders: [URL(filePath: "/Users/me/app")])

        let decoded = try JSONDecoder().decode(SessionSearchPage.self, from: JSONEncoder().encode(page))

        #expect(decoded == page)
    }

    /// A request goes through JSON and back with no change.
    @Test func aRequestRoundTripsThroughJSON() throws {
        let request = SessionSearchRequest(
            query: try Self.parse("retry from:tool"), sessions: [ULID()], includeArchived: true,
            preferredFolder: URL(filePath: "/Users/me/app"), session: nil, limit: 20, cursor: nil)

        let decoded = try JSONDecoder().decode(SessionSearchRequest.self, from: JSONEncoder().encode(request))

        #expect(decoded == request)
    }
}
