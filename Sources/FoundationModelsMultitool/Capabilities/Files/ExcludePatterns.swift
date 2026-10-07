// `ExcludePatterns` — the host exclude patterns of the files capability, in
// gitignore syntax.
//
// Why this matcher exists: the files capability has no gitignore matcher of
// its own. For `.gitignore`, `FileWalker` asks git (`git ls-files
// --exclude-standard`), and git applies the rules. Git cannot apply the host
// patterns on each walk. `git ls-files --exclude` applies to untracked files
// only, thus a tracked file under an excluded folder stays in the list. And
// the plain `FileManager` walk (no repository, or `respectGitIgnore: false`)
// does not run git at all. Thus the host patterns go through this one
// in-process matcher, which `FileWalker.walkAndFilter` applies to each file
// of each walk.
//
// The matcher follows the gitignore rules of one `.gitignore` file at the
// session root, and it reuses `GlobPattern` for the wildcards (`*`, `?`,
// `[...]`, `**`). Git on a macOS volume sets `core.ignorecase`, thus the
// matcher compares without regard to case, the same as git does there for
// `.gitignore`.

import Foundation

/// The host exclude patterns of one file session, in gitignore syntax.
///
/// The host gives the patterns when it composes the files capability. Each
/// search verb that walks a folder tree (`tools.files.glob` and
/// `tools.files.grep`) skips a file that the patterns exclude, the same way
/// it skips a file that `.gitignore` ignores. A verb that takes one explicit
/// path (a read, a write, or a grep of one file) does not use the patterns.
///
/// The rules are those of one `.gitignore` file at the session root:
///
/// - A blank line, and a line that starts with `#`, is not a pattern. A
///   leading `\` makes a leading `#` or `!` a literal character. The spaces
///   at the end of a line are not part of the pattern.
/// - A leading `!` negates the pattern: it puts back a path that an earlier
///   pattern excludes. The last pattern that matches a path decides.
/// - A trailing `/` makes the pattern match a folder only.
/// - A pattern with a `/` at its start or in its middle is anchored to the
///   session root. Each other pattern matches a name at each depth.
/// - `*`, `?`, `[...]` and `**` work as in gitignore. A trailing `/**`
///   matches each path in the folder, but not the folder itself.
/// - A file in an excluded folder stays excluded. A negated pattern cannot
///   put it back, because git does not look into an excluded folder.
/// - A pattern that does not compile (for example an unterminated `[`)
///   matches nothing, the same as in git.
/// - The match is not sensitive to case, the same as git with
///   `core.ignorecase`, which git sets on a macOS volume.
///
/// A backslash at a position other than the start of a pattern is a literal
/// backslash here, and a backslash does not keep a space at the end of a line.
struct ExcludePatterns: Sendable {

    /// The compiled patterns, in the order the host gave them.
    private let rules: [Rule]

    /// Compiles the host exclude patterns.
    ///
    /// - Parameter lines: the patterns in gitignore syntax, one for each
    ///   element, in the order of a `.gitignore` file. An empty list
    ///   excludes nothing.
    init(_ lines: [String]) {
        rules = lines.compactMap(Rule.init(line:))
    }

    /// Whether the patterns exclude a file.
    ///
    /// The file is excluded when the patterns exclude one of its parent
    /// folders, or else when they exclude the file itself.
    ///
    /// - Parameter relativePath: the path of a regular file, relative to the
    ///   session root, with `/` between its components.
    /// - Returns: `true` when a search walk must skip the file.
    func excludes(relativePath: String) -> Bool {
        // With no pattern, a walk does no more work than before.
        guard !rules.isEmpty else { return false }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        let folderPaths = components.indices.dropFirst().map { components[..<$0].joined(separator: "/") }
        return folderPaths.contains { isExcluded($0, isFolder: true) }
            || isExcluded(relativePath, isFolder: false)
    }

    /// Whether the last pattern that matches a path excludes it.
    ///
    /// - Parameters:
    ///   - path: the path relative to the session root.
    ///   - isFolder: whether the path names a folder.
    /// - Returns: `true` when the last matching pattern is not negated;
    ///   `false` when it is negated or when no pattern matches.
    private func isExcluded(_ path: String, isFolder: Bool) -> Bool {
        guard let decidingRule = rules.last(where: { $0.matches(path, isFolder: isFolder) }) else { return false }
        return !decidingRule.isNegated
    }
}

extension ExcludePatterns {

    /// One compiled pattern line.
    private struct Rule: Sendable {

        /// The character that starts a comment line.
        private static let commentMarker = "#"

        /// The character that negates a pattern.
        private static let negationMarker = "!"

        /// The character that makes the next character a literal.
        private static let escapeMarker = "\\"

        /// The path separator, which also marks a folder pattern at the end.
        private static let separator = "/"

        /// The space that the end of a line can carry.
        private static let trailingSpace = " "

        /// The trailing `/**` that matches each path in a folder.
        private static let folderContentSuffix = separator + GlobPattern.recursiveComponent

        /// What the rule adds after a trailing `/**`, thus the folder itself
        /// does not match.
        private static let oneMoreComponent = separator + "*"

        /// The prefix that makes an unanchored pattern match at each depth.
        private static let anyDepthPrefix = GlobPattern.recursiveComponent + separator

        /// The pattern matches are not sensitive to case (see the type).
        private static let caseSensitive = false

        /// The compiled wildcard pattern, matched against the whole path.
        let pattern: GlobPattern

        /// Whether the line starts with `!`.
        let isNegated: Bool

        /// Whether the line ends with `/`, thus it matches folders only.
        let matchesFoldersOnly: Bool

        /// Compiles one pattern line, or answers `nil` for a line that is
        /// not a pattern or that does not compile.
        ///
        /// - Parameter line: one line in gitignore syntax.
        init?(line: String) {
            var body = Self.trimmingTrailingSpaces(Substring(line))
            guard !body.isEmpty, !body.hasPrefix(Self.commentMarker) else { return nil }

            isNegated = body.hasPrefix(Self.negationMarker)
            if isNegated { body = body.dropFirst() }
            if body.hasPrefix(Self.escapeMarker) { body = body.dropFirst() }

            matchesFoldersOnly = body.hasSuffix(Self.separator)
            if matchesFoldersOnly { body = body.dropLast() }
            guard !body.isEmpty else { return nil }

            guard let pattern = try? GlobPattern(Self.globText(of: body), matchesWholePath: true) else { return nil }
            self.pattern = pattern
        }

        /// Whether the rule matches a path.
        ///
        /// - Parameters:
        ///   - path: the path relative to the session root.
        ///   - isFolder: whether the path names a folder.
        /// - Returns: `true` when the pattern matches and the kind of path agrees.
        func matches(_ path: String, isFolder: Bool) -> Bool {
            guard isFolder || !matchesFoldersOnly else { return false }
            return pattern.matches(relativePath: path, caseSensitive: Self.caseSensitive)
        }

        /// The glob text that matches the whole path, for a pattern body
        /// with no negation and no trailing `/`.
        ///
        /// A body with a `/` is anchored to the session root, and its
        /// leading `/` goes. Each other body gets a leading `**/`, thus it
        /// matches at each depth. A trailing `/**` gets one more component,
        /// thus the folder itself does not match.
        ///
        /// - Parameter body: the pattern body.
        /// - Returns: the glob text for ``GlobPattern``.
        private static func globText(of body: Substring) -> String {
            let isAnchored = body.contains(separator)
            let anchoredBody = body.hasPrefix(separator) ? body.dropFirst() : body
            let completedBody =
                anchoredBody.hasSuffix(folderContentSuffix)
                ? String(anchoredBody) + oneMoreComponent : String(anchoredBody)
            return isAnchored ? completedBody : anyDepthPrefix + completedBody
        }

        /// A line without the spaces at its end.
        ///
        /// - Parameter line: the raw line.
        /// - Returns: the line without its trailing spaces.
        private static func trimmingTrailingSpaces(_ line: Substring) -> Substring {
            var trimmed = line
            while trimmed.hasSuffix(trailingSpace) {
                trimmed = trimmed.dropLast()
            }
            return trimmed
        }
    }
}
