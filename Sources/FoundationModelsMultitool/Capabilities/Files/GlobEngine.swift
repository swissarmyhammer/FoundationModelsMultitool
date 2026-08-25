// `GlobEngine` — the pattern validation, the bounded git-aware walk, and
// the newest-first order behind the `tools.files.glob` verb.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// GlobEngine.swift`, unchanged in behavior. One name changes: the sibling
// calls the success payload `GlobResult`, and this package gives that name
// to the verb's flat result (the Shell verbs name their flat results
// `<Verb>Result`), thus the engine's success payload is `GlobMatches`
// here. The sibling declares the types `public`; this package keeps them
// internal, the same way `FileWalker` and `PathGuard` beside them do.
//
// eventplan.md § "Consolidation of the siblings": the glob and grep verbs
// resolve, bound, and enumerate a search root through the shared
// `FileWalker`, and a corrective result stays in band, never thrown.

import Foundation

/// The successful matches of one glob: the matching paths, newest first.
///
/// The ``files`` are paths relative to the session root, sorted by
/// modification time with the most recently modified first; ``total`` is the
/// full count of matching files found (before any cap), and ``capped``
/// reports whether that total exceeded the engine's result cap so ``files``
/// is a strict prefix of the matches rather than the whole set. When
/// ``capped`` is `true`, ``files`` carries exactly the cap's worth of the
/// newest matches.
struct GlobMatches: Encodable, Sendable {
    /// The glob pattern that produced these matches.
    let pattern: String

    /// The matching paths relative to the session root, most recently modified first.
    let files: [String]

    /// The total number of matching files found, before any cap is applied.
    let total: Int

    /// Whether ``total`` exceeded the result cap, so ``files`` is a truncated prefix.
    let capped: Bool
}

/// The outcome of one glob: either the matches or a corrective message.
///
/// The engine follows the upstream *return-don't-throw* convention (the same
/// convention ``PathViolation`` and ``ParseFailure`` embody): an over-length
/// pattern, an invalid glob, an unscoped broad pattern, a rejected search
/// root, or a missing directory is surfaced as a ``corrective(_:)`` message
/// the model reads and acts on within the turn, never thrown. A thrown error
/// is fatal to the turn, so every recoverable condition returns a value
/// instead.
enum GlobOutput: CorrectiveEncodable, Sendable {
    /// A successful glob carrying the ``GlobMatches``.
    case content(GlobMatches)

    /// A recoverable failure carrying a corrective message for the model.
    case corrective(String)

    /// The successful ``GlobMatches`` (encoded inline), or `nil` for a corrective outcome.
    var successResult: GlobMatches? {
        if case .content(let matches) = self { return matches }
        return nil
    }

    /// The corrective message, or `nil` for a successful outcome.
    var correctiveMessage: String? {
        if case .corrective(let message) = self { return message }
        return nil
    }
}

/// Finds files whose relative path matches a glob pattern, newest first.
///
/// The engine validates the pattern (length, syntax, and — when the walk is
/// unscoped by a `path` — the broad-pattern guard), resolves and bounds the
/// search root through the context's ``PathGuard`` (refusing the filesystem
/// root), enumerates candidate files (via `git ls-files` when a repository is
/// present and gitignore is respected, else a plain `FileManager` walk),
/// matches each candidate against the pattern, and returns the matches
/// relative to the session root sorted by modification time with the newest
/// first.
///
/// The result cap is injected through ``init(maxResults:)`` so tests can
/// drive the capping path with a small value; when the number of matches
/// exceeds the cap, exactly the cap's worth of the newest matches is
/// returned and ``GlobMatches/capped`` is set. Every recoverable failure is
/// returned as ``GlobOutput/corrective(_:)``; nothing here throws.
struct GlobEngine: Sendable {
    // MARK: Configuration

    /// The default maximum number of matching files returned, matching the Rust `files` tool.
    static let defaultMaximumResults = 10_000

    /// The maximum accepted pattern length in characters, matching the Rust `files` tool.
    private static let maximumPatternLength = 1000

    /// The maximum number of matching files this engine returns before capping.
    private let maximumResults: Int

    /// Creates a glob engine with a result cap.
    ///
    /// - Parameter maxResults: the maximum number of matching files to return;
    ///   defaults to the 10,000-file cap of the Rust `files` tool. This is the
    ///   injectable seam tests use with a small value to exercise capping.
    init(maxResults: Int = defaultMaximumResults) {
        self.maximumResults = maxResults
    }

    // MARK: Execution

    /// Finds the files matching `pattern` and returns them newest first, or a corrective message.
    ///
    /// Validates the pattern length, the pattern syntax, and — when `path` is
    /// `nil` — the broad-pattern guard; resolves and bounds the search root
    /// through `context`'s ``PathGuard`` (refusing the filesystem root and a
    /// nonexistent directory); enumerates candidate files; matches each against
    /// the pattern (filename-only for a pattern with no `/` and no `**`, else the
    /// relative path); and returns the matches relative to the session root
    /// sorted by modification time, newest first, capped at ``init(maxResults:)``.
    ///
    /// - Parameters:
    ///   - pattern: the glob pattern to match.
    ///   - path: the directory to search, or `nil` to search the session root.
    ///   - caseSensitive: whether matching is case-sensitive; defaults to `false`.
    ///   - respectGitIgnore: whether a present repository's ignore rules are
    ///     honored (via `git ls-files`); defaults to `true`.
    ///   - context: the shared session context supplying the path guard and root.
    /// - Returns: the ``GlobOutput/content(_:)`` matches on success, or a
    ///   ``GlobOutput/corrective(_:)`` message the model can act on.
    func run(
        pattern: String,
        path: String? = nil,
        caseSensitive: Bool = false,
        respectGitIgnore: Bool = true,
        in context: FileContext
    ) -> GlobOutput {
        Self.prepare(pattern: pattern, path: path, in: context)
            .resolve(corrective: GlobOutput.corrective) { prepared in
                let matches = Self.collectMatches(
                    compiled: prepared.compiled,
                    caseSensitive: caseSensitive,
                    respectGitIgnore: respectGitIgnore,
                    walkRoot: prepared.walkRoot,
                    sessionRoot: FileWalker.canonicalDirectory(context.root)
                )

                let total = matches.count
                let capped = total > maximumResults
                let files = (capped ? Array(matches.prefix(maximumResults)) : matches).map(\.relativePath)
                return .content(GlobMatches(pattern: pattern, files: files, total: total, capped: capped))
            }
    }

    // MARK: Input validation

    /// A pre-search rejection, carrying the corrective message to hand back.
    ///
    /// Every pre-search check produces the same thing — one corrective string —
    /// so they share one error type. Conforming it to ``CorrectiveFailure`` is
    /// what lets ``run(pattern:path:caseSensitive:respectGitIgnore:in:)`` unwrap
    /// them through the shared ``Swift/Result/resolve(corrective:then:)`` rather
    /// than its own `switch`. ``PathViolation`` is deliberately not reused: only
    /// one of these rejections is about a path.
    private struct Rejection: CorrectiveFailure {
        /// The corrective message the model reads and acts on.
        let correctiveMessage: String
    }

    /// The validated inputs of one search: the compiled pattern and where to walk.
    private struct PreparedSearch {
        /// The compiled glob pattern to match candidates against.
        let compiled: GlobPattern

        /// The canonical directory the walk starts from.
        let walkRoot: URL
    }

    /// Validates and compiles the pattern and resolves the search root, or rejects.
    ///
    /// Holds *all* of the pre-search branching — the length cap, the
    /// broad-pattern guard, glob compilation, and search-root resolution — so
    /// the caller is left with a single success/failure fork ahead of the walk
    /// rather than four checks interleaved with it.
    ///
    /// Checks run in that order and stop at the first failure, because a
    /// corrective is one message: reporting the length cap *and* a bad search
    /// root would be one message the model cannot act on cleanly.
    ///
    /// - Parameters:
    ///   - pattern: the raw glob pattern.
    ///   - path: the requested search directory, or `nil` for the session root.
    ///   - context: the shared session context supplying the path guard and root.
    /// - Returns: `.success` with the ``PreparedSearch``, or `.failure` with the
    ///   first ``Rejection``.
    private static func prepare(
        pattern: String,
        path: String?,
        in context: FileContext
    ) -> Result<PreparedSearch, Rejection> {
        guard pattern.count <= maximumPatternLength else {
            return .failure(Rejection(correctiveMessage: patternTooLongMessage))
        }
        guard path != nil || !isBroad(pattern) else {
            return .failure(Rejection(correctiveMessage: broadPatternMessage(pattern)))
        }
        guard let compiled = try? GlobPattern(pattern) else {
            return .failure(Rejection(correctiveMessage: invalidPatternMessage(pattern)))
        }
        return resolveSearchRoot(path: path, in: context)
            .mapError { Rejection(correctiveMessage: $0.correctiveMessage) }
            .map { PreparedSearch(compiled: compiled, walkRoot: $0) }
    }

    // MARK: Search-root resolution

    /// Resolves and bounds the search root, returning the canonical directory URL or a corrective message.
    ///
    /// A given `path` is validated through the context's ``PathGuard`` (which
    /// enforces the workspace boundary); an absent `path` searches the session
    /// root directly. The resolved root is then refused if it is the filesystem
    /// root and rejected if it does not name an existing directory.
    ///
    /// - Parameters:
    ///   - path: the requested search directory, or `nil` for the session root.
    ///   - context: the shared session context supplying the path guard and root.
    /// - Returns: `.success` with the canonical search-root URL, or `.failure`
    ///   with a corrective ``PathViolation``.
    private static func resolveSearchRoot(path: String?, in context: FileContext) -> Result<URL, PathViolation> {
        FileWalker.resolveRequestedPath(path, in: context) { context.pathGuard.validate($0, for: .directory) }
            .flatMap { resolved in FileWalker.boundDirectory(resolved, in: context) }
            .flatMap { canonical in
                FileWalker.isDirectory(canonical.path)
                    ? .success(canonical)
                    : .failure(PathViolation(directoryMissingMessage(path ?? canonical.path)))
            }
    }

    // MARK: Matching

    /// A matching file: its path relative to the session root and its modification date.
    private struct Match {
        /// The matching file's path relative to the session root.
        let relativePath: String

        /// The matching file's modification date, used to order results.
        let modificationDate: Date
    }

    /// Collects and orders the files under `walkRoot` matching the compiled pattern.
    ///
    /// Enumerates candidate files, matches each against the pattern relative to
    /// `walkRoot` (filename-only or full relative path per the pattern's shape),
    /// keeps the matches as paths relative to `sessionRoot` paired with their
    /// modification dates, and sorts them by date descending with a path
    /// tie-break so the order is deterministic.
    ///
    /// - Parameters:
    ///   - compiled: the compiled glob pattern.
    ///   - caseSensitive: whether matching is case-sensitive.
    ///   - respectGitIgnore: whether a present repository's ignore rules are honored.
    ///   - walkRoot: the canonical search root.
    ///   - sessionRoot: the canonical session root the returned paths are relative to.
    /// - Returns: the matches sorted newest first.
    private static func collectMatches(
        compiled: GlobPattern,
        caseSensitive: Bool,
        respectGitIgnore: Bool,
        walkRoot: URL,
        sessionRoot: URL
    ) -> [Match] {
        var matches = FileWalker.walkAndFilter(
            walkRoot: walkRoot,
            sessionRoot: sessionRoot,
            respectGitIgnore: respectGitIgnore,
            accept: { _, relativeToWalk in
                compiled.matches(relativePath: relativeToWalk, caseSensitive: caseSensitive)
            },
            build: { absolute, relativeToSession -> Match? in
                guard let date = modificationDate(ofAbsolute: absolute) else { return nil }
                return Match(relativePath: relativeToSession, modificationDate: date)
            }
        )
        matches.sort { lhs, rhs in
            lhs.modificationDate == rhs.modificationDate
                ? lhs.relativePath < rhs.relativePath
                : lhs.modificationDate > rhs.modificationDate
        }
        return matches
    }

    // MARK: Filesystem probes

    /// The modification date of a file, or `nil` when it cannot be read.
    ///
    /// - Parameter path: the absolute path of the file.
    /// - Returns: the modification date, or `nil` when the file is missing or
    ///   its attributes cannot be read.
    private static func modificationDate(ofAbsolute path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    // MARK: Broad-pattern guard

    /// The literal prefix of the broad `**/*.ext` bare-extension pattern shape.
    private static let broadExtensionPrefix = "**/*."

    /// The glob metacharacters that, if present in a bare extension, disqualify the broad shape.
    private static let globMetacharacters: Set<Character> = ["*", "?", "[", "]", "/"]

    /// A broad-pattern rule: either an exact literal or the `**/*.ext` bare-extension shape.
    ///
    /// The broad set is expressed as data — a table of these rules interpreted by
    /// the single ``isBroad(_:)`` code path — rather than parallel branches, so a
    /// new broad shape is one table entry, not another `if`.
    private enum BroadPatternRule {
        /// A pattern equal to a fixed literal (for example `*` or `**/*`).
        case exact(String)

        /// A pattern of the `**/*.ext` shape: a bare, wildcard-free extension.
        case bareExtension

        /// Whether `pattern` is broad under this rule.
        ///
        /// - Parameter pattern: the pattern to test.
        /// - Returns: `true` when `pattern` is broad under this rule.
        func matches(_ pattern: String) -> Bool {
            switch self {
            case .exact(let literal):
                return pattern == literal
            case .bareExtension:
                return GlobEngine.isBareExtensionGlob(pattern)
            }
        }
    }

    /// The broad patterns rejected when the walk is unscoped by a `path`.
    ///
    /// The literals plus the bare-extension shape are the set refused without a
    /// scoping `path`. A bare `**` is included alongside `**/*` because it too
    /// matches every file under the walk root (``GlobPattern`` reduces a lone
    /// recursive component to "match anything"), so leaving it out would let the
    /// broadest possible pattern slip past a guard whose whole purpose is to
    /// prevent whole-session walks.
    private static let broadPatternRules: [BroadPatternRule] = [
        .exact("*"),
        .exact(GlobPattern.recursiveComponent),
        .exact("**/*"),
        .exact("*.*"),
        .bareExtension,
    ]

    /// Whether a pattern is too broad to search an unscoped session root.
    ///
    /// - Parameter pattern: the raw pattern to test.
    /// - Returns: `true` when any ``broadPatternRules`` entry matches.
    private static func isBroad(_ pattern: String) -> Bool {
        broadPatternRules.contains { $0.matches(pattern) }
    }

    /// Whether a pattern is the broad `**/*.ext` shape: `**/*.` then a bare, wildcard-free extension.
    ///
    /// - Parameter pattern: the raw pattern to test.
    /// - Returns: `true` when `pattern` is `**/*.` followed by a non-empty run of
    ///   characters containing no glob metacharacter.
    private static func isBareExtensionGlob(_ pattern: String) -> Bool {
        guard pattern.hasPrefix(broadExtensionPrefix) else { return false }
        let ext = pattern.dropFirst(broadExtensionPrefix.count)
        guard !ext.isEmpty else { return false }
        return !ext.contains(where: globMetacharacters.contains)
    }

    // MARK: Corrective messages

    /// The corrective message naming the pattern-length cap.
    private static var patternTooLongMessage: String {
        "The `pattern` parameter must be at most \(maximumPatternLength) characters."
    }

    /// A corrective message telling the caller to scope a broad pattern with a `path`.
    ///
    /// - Parameter pattern: the rejected broad pattern.
    /// - Returns: the corrective message.
    private static func broadPatternMessage(_ pattern: String) -> String {
        "The pattern `\(pattern)` is too broad to search the whole session; provide a `path` to scope the search."
    }

    /// A corrective message for a pattern that is not valid glob syntax.
    ///
    /// - Parameter pattern: the rejected pattern.
    /// - Returns: the corrective message.
    private static func invalidPatternMessage(_ pattern: String) -> String {
        "The `pattern` is not a valid glob pattern: \(pattern)"
    }

    /// A corrective message for a search directory that does not exist.
    ///
    /// - Parameter path: the requested search directory.
    /// - Returns: the corrective message.
    private static func directoryMissingMessage(_ path: String) -> String {
        "The search directory does not exist: \(path)"
    }
}

/// A rejected glob pattern, thrown while compiling invalid syntax.
///
/// The only recoverable condition inside the engine that is expressed as a
/// thrown error rather than a returned value: it is absorbed at the single
/// ``GlobPattern`` construction site in ``GlobEngine`` — the `try?` in
/// ``GlobEngine/prepare(pattern:path:in:)`` — and turned into a corrective
/// message there, keeping the engine's public surface faithful to the
/// *return-don't-throw* convention.
struct GlobPatternError: Error {}

/// A compiled glob pattern that matches a relative path or a filename.
///
/// A direct port of the Rust `glob` crate's semantics the `files` tool relies
/// on: `*` matches any run of characters within one path component, `?` matches
/// one such character, `[...]` matches a character class (with `!` or `^`
/// negation and `a-z` ranges), and a `**` component matches any number of path
/// components including zero. A pattern with no `/` and no `**` is
/// ``isFilenameOnly`` and matches against the candidate's filename alone; any
/// other pattern matches against the whole path relative to the search root.
struct GlobPattern {
    /// The `**` glob component that matches any number of path components, including zero.
    static let recursiveComponent = "**"

    /// One path-separated component of a compiled pattern.
    private enum Component {
        /// A `**` component, matching any number of path components including zero.
        case recursive

        /// A single-component pattern, matching exactly one path component.
        case segment([Token])
    }

    /// One token within a single-component pattern.
    private enum Token {
        /// The `*` wildcard, matching any run of characters within the component.
        case anyRun

        /// The `?` wildcard, matching exactly one character within the component.
        case singleCharacter

        /// A literal character, matched with the requested case sensitivity.
        case literal(Character)

        /// A `[...]` character class.
        case characterClass(CharacterClass)
    }

    /// A parsed `[...]` character class: its members, ranges, and negation.
    private struct CharacterClass {
        /// Whether the class is negated (`[!...]` or `[^...]`).
        let negated: Bool

        /// The individual member characters.
        let characters: [Character]

        /// The inclusive character ranges, each a `(low, high)` pair.
        let ranges: [(Character, Character)]

        /// Whether a character is a member of this class, under the requested case sensitivity.
        ///
        /// - Parameters:
        ///   - character: the character to test.
        ///   - caseSensitive: whether membership is case-sensitive.
        /// - Returns: `true` when `character` is in the class (accounting for negation).
        func contains(_ character: Character, caseSensitive: Bool) -> Bool {
            var hit = characters.contains { GlobPattern.charactersEqual($0, character, caseSensitive: caseSensitive) }
            if !hit {
                hit = ranges.contains {
                    GlobPattern.character(character, inRange: $0.0, through: $0.1, caseSensitive: caseSensitive)
                }
            }
            return negated ? !hit : hit
        }
    }

    /// The compiled path components of the pattern.
    private let components: [Component]

    /// Whether the pattern targets the filename alone (no `/` and no `**`).
    let isFilenameOnly: Bool

    /// Compiles a raw glob pattern.
    ///
    /// - Parameter pattern: the raw glob pattern.
    /// - Throws: ``GlobPatternError`` when the pattern contains invalid syntax
    ///   (currently an unterminated `[` character class).
    init(_ pattern: String) throws {
        isFilenameOnly = !pattern.contains("/") && !pattern.contains(Self.recursiveComponent)
        var compiled: [Component] = []
        for part in pattern.split(separator: "/", omittingEmptySubsequences: false) {
            if String(part) == Self.recursiveComponent {
                compiled.append(.recursive)
            } else {
                compiled.append(.segment(try Self.compileSegment(part)))
            }
        }
        components = compiled.isEmpty ? [.segment([])] : compiled
    }

    /// Whether a relative path matches this pattern under the requested case sensitivity.
    ///
    /// A ``isFilenameOnly`` pattern matches against the path's last component; any
    /// other pattern matches against the whole path split into components.
    ///
    /// - Parameters:
    ///   - relativePath: the candidate path relative to the search root.
    ///   - caseSensitive: whether matching is case-sensitive.
    /// - Returns: `true` when the path matches.
    func matches(relativePath: String, caseSensitive: Bool) -> Bool {
        let pathComponents = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        if isFilenameOnly {
            guard case .segment(let tokens) = components[0], let filename = pathComponents.last else { return false }
            return Self.segmentMatches(tokens, Array(filename), caseSensitive: caseSensitive)
        }
        return Self.componentsMatch(components[...], pathComponents[...], caseSensitive: caseSensitive)
    }

    // MARK: Component matching

    /// Whether the pattern components match the path components, handling `**` recursion.
    ///
    /// A `**` component matches zero or more path components by trying every
    /// suffix; a segment component matches exactly one path component.
    ///
    /// - Parameters:
    ///   - patternComponents: the remaining pattern components.
    ///   - pathComponents: the remaining path components.
    ///   - caseSensitive: whether matching is case-sensitive.
    /// - Returns: `true` when the components match.
    private static func componentsMatch(
        _ patternComponents: ArraySlice<Component>,
        _ pathComponents: ArraySlice<Substring>,
        caseSensitive: Bool
    ) -> Bool {
        guard let first = patternComponents.first else { return pathComponents.isEmpty }
        switch first {
        case .recursive:
            return tryRecursiveMatches(patternComponents.dropFirst(), pathComponents, caseSensitive: caseSensitive)
        case .segment(let tokens):
            guard let head = pathComponents.first,
                segmentMatches(tokens, Array(head), caseSensitive: caseSensitive)
            else {
                return false
            }
            return componentsMatch(
                patternComponents.dropFirst(), pathComponents.dropFirst(), caseSensitive: caseSensitive)
        }
    }

    /// Whether a `**` component followed by `rest` matches `pathComponents`.
    ///
    /// A `**` matches any number of path components including zero, so this
    /// tries `rest` against every suffix of `pathComponents` — from the whole
    /// slice down to the empty tail — and succeeds as soon as one suffix
    /// matches. Extracting this backtracking loop keeps ``componentsMatch(_:_:caseSensitive:)``
    /// shallow rather than nesting the loop inside its `switch`.
    ///
    /// - Parameters:
    ///   - rest: the pattern components following the `**`.
    ///   - pathComponents: the path components the `**` and `rest` must cover.
    ///   - caseSensitive: whether matching is case-sensitive.
    /// - Returns: `true` when `rest` matches some suffix of `pathComponents`.
    private static func tryRecursiveMatches(
        _ rest: ArraySlice<Component>,
        _ pathComponents: ArraySlice<Substring>,
        caseSensitive: Bool
    ) -> Bool {
        var suffix = pathComponents
        while true {
            if componentsMatch(rest, suffix, caseSensitive: caseSensitive) { return true }
            guard !suffix.isEmpty else { return false }
            suffix = suffix.dropFirst()
        }
    }

    /// Whether a single-component token sequence matches a component's characters.
    ///
    /// Backtracks over `*` runs; `?`, literals, and character classes each consume
    /// one character. Filenames are short, so the simple backtracking match is
    /// adequate.
    ///
    /// - Parameters:
    ///   - tokens: the compiled tokens of one pattern component.
    ///   - characters: the candidate component's characters.
    ///   - caseSensitive: whether matching is case-sensitive.
    /// - Returns: `true` when the tokens match the characters exactly.
    private static func segmentMatches(_ tokens: [Token], _ characters: [Character], caseSensitive: Bool) -> Bool {
        segmentMatch(tokens, characters, tokenIndex: 0, characterIndex: 0, caseSensitive: caseSensitive)
    }

    /// Whether the tokens from `tokenIndex` match the characters from `characterIndex`.
    ///
    /// The recursive core of ``segmentMatches(_:_:caseSensitive:)``: a `*` run
    /// delegates its backtracking to ``tryAnyRunMatch(_:_:tokenIndex:characterIndex:caseSensitive:)``,
    /// while `?`, a literal, and a character class each consume exactly one
    /// character before recursing on the remaining tokens.
    ///
    /// - Parameters:
    ///   - tokens: the compiled tokens of one pattern component.
    ///   - characters: the candidate component's characters.
    ///   - tokenIndex: the index of the token to match next.
    ///   - characterIndex: the index of the character to match next.
    ///   - caseSensitive: whether matching is case-sensitive.
    /// - Returns: `true` when the remaining tokens match the remaining characters exactly.
    private static func segmentMatch(
        _ tokens: [Token],
        _ characters: [Character],
        tokenIndex: Int,
        characterIndex: Int,
        caseSensitive: Bool
    ) -> Bool {
        guard tokenIndex < tokens.count else { return characterIndex == characters.count }
        switch tokens[tokenIndex] {
        case .anyRun:
            return tryAnyRunMatch(
                tokens, characters, tokenIndex: tokenIndex, characterIndex: characterIndex, caseSensitive: caseSensitive
            )
        case .singleCharacter:
            return characterIndex < characters.count
                && segmentMatch(
                    tokens, characters, tokenIndex: tokenIndex + 1, characterIndex: characterIndex + 1,
                    caseSensitive: caseSensitive)
        case .literal(let expected):
            return characterIndex < characters.count
                && charactersEqual(expected, characters[characterIndex], caseSensitive: caseSensitive)
                && segmentMatch(
                    tokens, characters, tokenIndex: tokenIndex + 1, characterIndex: characterIndex + 1,
                    caseSensitive: caseSensitive)
        case .characterClass(let characterClass):
            return characterIndex < characters.count
                && characterClass.contains(characters[characterIndex], caseSensitive: caseSensitive)
                && segmentMatch(
                    tokens, characters, tokenIndex: tokenIndex + 1, characterIndex: characterIndex + 1,
                    caseSensitive: caseSensitive)
        }
    }

    /// Whether a `*` run at `tokenIndex` followed by the rest matches from `characterIndex`.
    ///
    /// A `*` matches any run of characters within the component, so this tries
    /// the tokens after the `*` against every position from `characterIndex` to
    /// the end of the component, succeeding as soon as one matches. Extracting
    /// this backtracking loop keeps ``segmentMatch(_:_:tokenIndex:characterIndex:caseSensitive:)``
    /// shallow rather than nesting the loop inside its `switch`.
    ///
    /// - Parameters:
    ///   - tokens: the compiled tokens of one pattern component.
    ///   - characters: the candidate component's characters.
    ///   - tokenIndex: the index of the `*` run token.
    ///   - characterIndex: the earliest character index the run may start consuming from.
    ///   - caseSensitive: whether matching is case-sensitive.
    /// - Returns: `true` when the tokens after the `*` match some suffix from `characterIndex`.
    private static func tryAnyRunMatch(
        _ tokens: [Token],
        _ characters: [Character],
        tokenIndex: Int,
        characterIndex: Int,
        caseSensitive: Bool
    ) -> Bool {
        var next = characterIndex
        while true {
            if segmentMatch(
                tokens, characters, tokenIndex: tokenIndex + 1, characterIndex: next, caseSensitive: caseSensitive)
            {
                return true
            }
            guard next < characters.count else { return false }
            next += 1
        }
    }

    // MARK: Compilation

    /// Compiles one path component into a token sequence.
    ///
    /// Collapses consecutive `*` into a single ``Token/anyRun`` so the backtracking
    /// matcher does not branch redundantly.
    ///
    /// - Parameter part: the raw component text.
    /// - Returns: the compiled tokens.
    /// - Throws: ``GlobPatternError`` when a `[` character class is unterminated.
    private static func compileSegment(_ part: Substring) throws -> [Token] {
        let characters = Array(part)
        var tokens: [Token] = []
        var index = 0
        while index < characters.count {
            switch characters[index] {
            case "*":
                if case .anyRun = tokens.last {} else { tokens.append(.anyRun) }
                index += 1
            case "?":
                tokens.append(.singleCharacter)
                index += 1
            case "[":
                let (characterClass, nextIndex) = try parseCharacterClass(characters, from: index)
                tokens.append(.characterClass(characterClass))
                index = nextIndex
            default:
                tokens.append(.literal(characters[index]))
                index += 1
            }
        }
        return tokens
    }

    /// Parses a `[...]` character class starting at the opening bracket.
    ///
    /// Honors a leading `!` or `^` negation, treats a `]` immediately after the
    /// opening (or negation) as a literal member, and reads `a-z` ranges.
    ///
    /// - Parameters:
    ///   - characters: the component's characters.
    ///   - start: the index of the opening `[`.
    /// - Returns: the parsed class and the index just past the closing `]`.
    /// - Throws: ``GlobPatternError`` when no closing `]` is found.
    private static func parseCharacterClass(
        _ characters: [Character],
        from start: Int
    ) throws -> (CharacterClass, Int) {
        var index = start + 1
        var negated = false
        if index < characters.count, characters[index] == "!" || characters[index] == "^" {
            negated = true
            index += 1
        }

        var members: [Character] = []
        var ranges: [(Character, Character)] = []
        if index < characters.count, characters[index] == "]" {
            members.append("]")
            index += 1
        }

        while index < characters.count, characters[index] != "]" {
            let dashIndex = index + 1
            let highIndex = dashIndex + 1
            if highIndex < characters.count, characters[dashIndex] == "-", characters[highIndex] != "]" {
                ranges.append((characters[index], characters[highIndex]))
                index = highIndex + 1
            } else {
                members.append(characters[index])
                index += 1
            }
        }

        guard index < characters.count, characters[index] == "]" else { throw GlobPatternError() }
        return (CharacterClass(negated: negated, characters: members, ranges: ranges), index + 1)
    }

    // MARK: Case-aware comparison

    /// Whether two characters are equal under the requested case sensitivity.
    ///
    /// - Parameters:
    ///   - lhs: the first character.
    ///   - rhs: the second character.
    ///   - caseSensitive: whether the comparison is case-sensitive.
    /// - Returns: `true` when the characters are equal (case-folded when insensitive).
    private static func charactersEqual(_ lhs: Character, _ rhs: Character, caseSensitive: Bool) -> Bool {
        caseSensitive ? lhs == rhs : lhs.lowercased() == rhs.lowercased()
    }

    /// Whether a character falls within an inclusive range under the requested case sensitivity.
    ///
    /// Compares by the first Unicode scalar; when case-insensitive, both the
    /// lowercase and uppercase forms of the character are tried against the range.
    ///
    /// - Parameters:
    ///   - character: the character to test.
    ///   - low: the inclusive low bound.
    ///   - high: the inclusive high bound.
    ///   - caseSensitive: whether the comparison is case-sensitive.
    /// - Returns: `true` when the character is within the range.
    private static func character(
        _ character: Character,
        inRange low: Character,
        through high: Character,
        caseSensitive: Bool
    ) -> Bool {
        func scalarInRange(_ candidate: Character) -> Bool {
            guard
                let value = candidate.unicodeScalars.first?.value,
                let lowValue = low.unicodeScalars.first?.value,
                let highValue = high.unicodeScalars.first?.value
            else {
                return false
            }
            return value >= lowValue && value <= highValue
        }
        if scalarInRange(character) { return true }
        guard !caseSensitive else { return false }
        return scalarInRange(Character(character.lowercased())) || scalarInRange(Character(character.uppercased()))
    }
}
