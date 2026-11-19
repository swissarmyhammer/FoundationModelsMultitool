// `SessionSearchQueryParser` — the parse of the text of a session search
// query into a `SessionSearchQuery` (D207 (e), Q64).
//
// The scanner cuts the text into terms: words, phrases in quotes, and
// exclusions. The parser then reads each word as a plain word or as a token.

import Foundation

/// One term of a query: a word or a phrase, and the `-` that excludes it.
struct SessionSearchTerm: Equatable {
    /// The text, with no `-` and no quotes.
    let text: String

    /// True when the term was in quotes.
    let isPhrase: Bool

    /// True when a `-` excludes the term.
    let isExcluded: Bool
}

/// Cuts the text of a query into terms.
///
/// Space separates the words. A quote starts a phrase, and the next quote
/// ends it; a quote with no closing quote makes a phrase to the end of the
/// text. A `-` at the start of a word, or just before a quote, excludes the
/// term. A lone `-` and an empty phrase give no term.
struct SessionSearchScanner {
    /// A phrase whose closing quote the scanner did not read yet.
    private struct OpenPhrase {
        /// The text of the phrase so far.
        var text = ""

        /// True when a `-` excludes the phrase.
        let isExcluded: Bool
    }

    /// What the scanner reads now. Each state holds only its own text.
    private enum ScanState {
        /// The scanner is out of a term: at the start, or after space or a
        /// closing quote.
        case idle

        /// The scanner reads a word. The text has one or more characters.
        case word(String)

        /// The scanner reads a phrase whose closing quote it did not read yet.
        case phrase(OpenPhrase)
    }

    /// The character that starts and ends a phrase.
    private static let quote: Character = "\""

    /// The mark that excludes a term.
    private static let exclusionMark = "-"

    /// The terms that the scanner made.
    private var terms: [SessionSearchTerm] = []

    /// What the scanner reads now.
    private var state = ScanState.idle

    /// The terms of `text`, in their order.
    ///
    /// - Parameter text: The text of a query.
    /// - Returns: The terms.
    static func terms(of text: String) -> [SessionSearchTerm] {
        var scanner = SessionSearchScanner()
        for character in text {
            scanner.read(character)
        }
        scanner.endTerm()
        return scanner.terms
    }

    /// Reads one character of the text.
    ///
    /// - Parameter character: The character.
    private mutating func read(_ character: Character) {
        switch state {
        case .phrase(let phrase):
            readInPhrase(character, phrase: phrase)
        case .idle, .word:
            readOutOfPhrase(character)
        }
    }

    /// Reads one character in a phrase.
    ///
    /// - Parameters:
    ///   - character: The character.
    ///   - phrase: The open phrase.
    private mutating func readInPhrase(_ character: Character, phrase: OpenPhrase) {
        guard character != Self.quote else {
            endTerm()
            return
        }
        var longer = phrase
        longer.text.append(character)
        state = .phrase(longer)
    }

    /// Reads one character out of a phrase.
    ///
    /// - Parameter character: The character.
    private mutating func readOutOfPhrase(_ character: Character) {
        if character == Self.quote {
            startPhrase()
        } else if character.isWhitespace {
            endTerm()
        } else {
            appendToWord(character)
        }
    }

    /// Adds one character to the word, or starts a word with it.
    ///
    /// - Parameter character: The character.
    private mutating func appendToWord(_ character: Character) {
        switch state {
        case .word(let text):
            state = .word(text + String(character))
        case .idle, .phrase:
            state = .word(String(character))
        }
    }

    /// Starts a phrase at a quote. A pending `-` excludes the phrase; other
    /// pending characters end as a word.
    private mutating func startPhrase() {
        let isExcluded: Bool
        if case .word(let text) = state, text == Self.exclusionMark {
            isExcluded = true
        } else {
            isExcluded = false
            endTerm()
        }
        state = .phrase(OpenPhrase(isExcluded: isExcluded))
    }

    /// Ends the term that the scanner reads now, if it has text, and goes
    /// back to ``ScanState/idle``.
    private mutating func endTerm() {
        switch state {
        case .idle:
            break
        case .word(let text):
            addWord(text)
        case .phrase(let phrase):
            addPhrase(phrase)
        }
        state = .idle
    }

    /// Adds a word as a term, if it has text after its `-`.
    ///
    /// - Parameter word: The characters of the word.
    private mutating func addWord(_ word: String) {
        let isExcluded = word.hasPrefix(Self.exclusionMark)
        let text = isExcluded ? String(word.dropFirst()) : word
        guard !text.isEmpty else {
            return
        }
        terms.append(SessionSearchTerm(text: text, isPhrase: false, isExcluded: isExcluded))
    }

    /// Adds a phrase as a term, if it has text. Each run of space in the
    /// phrase becomes one space.
    ///
    /// - Parameter phrase: The phrase.
    private mutating func addPhrase(_ phrase: OpenPhrase) {
        let text = phrase.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else {
            return
        }
        terms.append(SessionSearchTerm(text: text, isPhrase: true, isExcluded: phrase.isExcluded))
    }
}

/// The key of a `key:value` token.
enum SessionSearchKey: String, CaseIterable {
    /// `from:<kind>`: the kind of chunk.
    case from

    /// `after:<date>`: the first day of the chunks.
    case after

    /// `before:<date>`: the day after the last day of the chunks.
    case before

    /// `agent:<name>`: the agent of the session.
    case agent

    /// `folder:<path>`: the folder of the session.
    case folder

    /// `is:archived`: includes the archived sessions.
    case `is`
}

/// What one word of a query is.
enum SessionSearchToken: Equatable {
    /// A plain word.
    case word

    /// `@<session>`, with the text after `@`.
    case session(String)

    /// `#<tag>`, with the text after `#`.
    case tag(String)

    /// `key:value`, with a known key and the text after the first `:`.
    case keyed(SessionSearchKey, value: String)
}

/// Parses the terms of a query into a ``SessionSearchQuery``.
struct SessionSearchQueryParser {
    /// The mark of a session token.
    private static let sessionMark: Character = "@"

    /// The mark of a tag token.
    private static let tagMark: Character = "#"

    /// The character between the key and the value of a token.
    private static let keySeparator: Character = ":"

    /// The one value of the `is:` token.
    static let archivedValue = "archived"

    /// The kinds that a `from:` token can name. A session item does not pass
    /// a `from:` token (D207 (e)), so `session` is not one of them.
    static let fromKinds = SessionSearchHit.Kind.allCases.filter { $0 != .session }

    /// The time zone in which a day of `after:` and `before:` starts.
    private let timeZone: TimeZone

    /// The query so far. Its kinds are the kinds of the `from:` tokens so
    /// far.
    private var query = SessionSearchQuery(kinds: [])

    /// The words and the phrases so far, for the ranking text.
    private var intent: [String] = []

    /// Makes a parser.
    ///
    /// - Parameter timeZone: The time zone in which a day starts.
    private init(timeZone: TimeZone) {
        self.timeZone = timeZone
    }

    /// Parses the text of a query.
    ///
    /// - Parameters:
    ///   - text: The query.
    ///   - timeZone: The time zone in which a day of `after:` and `before:`
    ///     starts.
    /// - Returns: The parsed query.
    /// - Throws: ``SessionsRefusal`` when the query has no term, or when a
    ///   token has a wrong value.
    static func query(of text: String, timeZone: TimeZone) throws(SessionsRefusal) -> SessionSearchQuery {
        let terms = SessionSearchScanner.terms(of: text)
        guard !terms.isEmpty else {
            throw SessionsRefusal(.blankText, SessionsToolText.blankText(SessionsToolText.queryParameter))
        }
        var parser = SessionSearchQueryParser(timeZone: timeZone)
        for term in terms {
            try parser.add(term)
        }
        return parser.finishedQuery()
    }

    /// What one word is.
    ///
    /// - Parameter text: The word.
    /// - Returns: The token, or ``SessionSearchToken/word`` for a plain word.
    static func token(of text: String) -> SessionSearchToken {
        if let reference = marked(text, by: sessionMark) {
            return .session(reference)
        }
        if let tag = marked(text, by: tagMark) {
            return .tag(tag)
        }
        guard let separator = text.firstIndex(of: keySeparator),
            let key = SessionSearchKey(rawValue: text[..<separator].lowercased())
        else {
            return .word
        }
        return .keyed(key, value: String(text[text.index(after: separator)...]))
    }

    /// The text after a mark at the start of `text`.
    ///
    /// - Parameters:
    ///   - text: The word.
    ///   - mark: The mark.
    /// - Returns: The text after the mark, or `nil` when `text` does not start
    ///   with the mark or has nothing after it.
    private static func marked(_ text: String, by mark: Character) -> String? {
        guard text.first == mark, text.count > 1 else {
            return nil
        }
        return String(text.dropFirst())
    }

    /// Adds one term to the query.
    ///
    /// - Parameter term: The term.
    /// - Throws: ``SessionsRefusal`` when the term is a token with a wrong
    ///   value.
    private mutating func add(_ term: SessionSearchTerm) throws(SessionsRefusal) {
        guard !term.isExcluded else {
            query.excluded.append(term.text)
            return
        }
        guard !term.isPhrase else {
            addIntent(term.text, to: \.phrases)
            return
        }
        try add(Self.token(of: term.text), word: term.text)
    }

    /// Adds one word, as what it is.
    ///
    /// - Parameters:
    ///   - token: What the word is.
    ///   - word: The word, as written.
    /// - Throws: ``SessionsRefusal`` when the token has a wrong value.
    private mutating func add(_ token: SessionSearchToken, word: String) throws(SessionsRefusal) {
        switch token {
        case .word:
            addIntent(word, to: \.words)
        case .session(let reference):
            query.sessionReferences.append(reference)
        case .tag(let tag):
            query.tags.append(tag)
        case .keyed(let key, let value):
            try add(key, value: value, token: word)
        }
    }

    /// Adds one `key:value` token.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - value: The text after the `:`.
    ///   - token: The token, as written, for the corrective.
    /// - Throws: ``SessionsRefusal`` when the value is empty or wrong.
    private mutating func add(_ key: SessionSearchKey, value: String, token: String) throws(SessionsRefusal) {
        guard !value.isEmpty else {
            throw SessionsRefusal(.invalidQuery, SessionsToolText.searchTokenWithNoValue(token))
        }
        switch key {
        case .from:
            query.kinds.insert(try Self.kind(of: value, token: token))
        case .after:
            let start = try day(of: value, token: token)
            query.after = max(query.after ?? start, start)
        case .before:
            let start = try day(of: value, token: token)
            query.before = min(query.before ?? start, start)
        case .agent:
            query.agents.append(value)
        case .folder:
            query.folders.append(value)
        case .`is`:
            guard value.lowercased() == Self.archivedValue else {
                throw SessionsRefusal(.invalidQuery, SessionsToolText.unknownSearchState(token))
            }
            query.includesArchived = true
        }
    }

    /// Adds a word or a phrase to its list and to the ranking text.
    ///
    /// - Parameters:
    ///   - text: The word or the phrase.
    ///   - list: The list of the query that gets it.
    private mutating func addIntent(_ text: String, to list: WritableKeyPath<SessionSearchQuery, [String]>) {
        query[keyPath: list].append(text)
        intent.append(text)
    }

    /// The kind that the value of a `from:` token names.
    ///
    /// - Parameters:
    ///   - value: The value, in any letter case.
    ///   - token: The token, for the corrective.
    /// - Returns: The kind.
    /// - Throws: ``SessionsRefusal`` when the value names no kind of
    ///   ``fromKinds``.
    private static func kind(of value: String, token: String) throws(SessionsRefusal) -> SessionSearchHit.Kind {
        guard let kind = SessionSearchHit.Kind(rawValue: value.lowercased()), fromKinds.contains(kind) else {
            throw SessionsRefusal(.invalidQuery, SessionsToolText.unknownSearchKind(token))
        }
        return kind
    }

    /// The first instant of the day of an `after:` or `before:` value.
    ///
    /// - Parameters:
    ///   - value: The date, as `YYYY-MM-DD`.
    ///   - token: The token, for the corrective.
    /// - Returns: The first instant of the day in ``timeZone``.
    /// - Throws: ``SessionsRefusal`` when the value is not a day in the form
    ///   `YYYY-MM-DD`.
    private func day(of value: String, token: String) throws(SessionsRefusal) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let match = value.wholeMatch(of: /([0-9]{4})-([0-9]{2})-([0-9]{2})/) else {
            throw SessionsRefusal(.invalidQuery, SessionsToolText.wrongSearchDate(token))
        }
        let components = DateComponents(year: Int(match.1), month: Int(match.2), day: Int(match.3))
        guard components.isValidDate(in: calendar), let date = calendar.date(from: components) else {
            throw SessionsRefusal(.invalidQuery, SessionsToolText.wrongSearchDate(token))
        }
        return date
    }

    /// The query of the terms: with no `from:` token, the default kinds.
    ///
    /// - Returns: The parsed query.
    private func finishedQuery() -> SessionSearchQuery {
        var finished = query
        if finished.kinds.isEmpty {
            finished.kinds = SessionSearchQuery.defaultKinds
        }
        finished.rankingText = intent.joined(separator: " ")
        return finished
    }
}
