// `SnippetRepair` — a few safe repairs of a `runCode` snippet that does not
// parse ("Postel's rule": be liberal in what you accept).
//
// SWE-bench run bench24-1023b, django__django-13964 (child session, seq
// 4702): one missing `:` — `{ pattern "unsaved", ... }` — failed a whole
// snippet of three `grepCode` calls. A snippet that does not parse never
// ran, thus a repair of it can run with no side effect counted twice.
//
// The rule that keeps a repair safe: each repair is one small edit, each is
// tried on its own, and the snippet runs repaired only when EXACTLY ONE
// candidate parses. Two that parse mean the intent is not clear, and the
// parse error goes back as before.

import Foundation

/// The repairs of a snippet that does not parse.
enum SnippetRepair {

    /// The start of the note a repaired run closes with.
    static let notePrefix = "Repaired: "

    /// One repaired snippet, and the note that says what changed.
    struct Candidate: Equatable {
        /// The repaired snippet.
        let code: String
        /// What the repair changed, as the note states it, without
        /// ``SnippetRepair/notePrefix`` and the final period.
        let note: String
    }

    /// The words that cannot be a property name a model forgot the `:`
    /// after: each one starts a statement or an expression of its own.
    private static let keywords: Set<String> = [
        "return", "await", "const", "let", "var", "typeof", "new", "case", "throw", "yield", "delete",
        "void", "in", "of", "instanceof", "else", "do", "if", "for", "while", "function", "async",
    ]

    /// The characters a closing token can be.
    private static let closers: [Character] = [")", "}", "]"]

    /// The one repair that makes `code` parse, or `nil` when none does or
    /// when more than one does.
    ///
    /// - Parameters:
    ///   - code: the snippet that does not parse.
    ///   - parses: whether a source parses; the interpreter's own parser.
    ///   - candidates: the repairs to try, or `nil` for ``candidates(for:)``.
    /// - Returns: the repaired snippet and its note, or `nil`.
    static func repair(
        _ code: String, parses: (String) -> Bool, candidates: [Candidate]? = nil
    ) -> Candidate? {
        var seen: Set<String> = []
        let unique = (candidates ?? Self.candidates(for: code)).filter { seen.insert($0.code).inserted }
        let parsing = unique.filter { parses($0.code) }
        guard parsing.count == 1, let only = parsing.first else { return nil }
        return only
    }

    /// The note a repaired run closes with.
    ///
    /// - Parameter candidate: the repair that ran.
    /// - Returns: the note.
    static func note(for candidate: Candidate) -> String {
        "\(notePrefix)\(candidate.note)."
    }

    /// Each small repair of `code`, in the order the kinds are listed on
    /// the type.
    ///
    /// - Parameter code: the snippet that does not parse.
    /// - Returns: the candidates, which may not parse.
    static func candidates(for code: String) -> [Candidate] {
        missingColonCandidates(code) + missingCommaCandidates(code) + closerCandidates(code)
    }

    /// The 1-based line of the character at `offset` (a UTF-16 offset).
    private static func line(atUTF16Offset offset: Int, in code: String) -> Int {
        let prefix = (code as NSString).substring(to: offset)
        return prefix.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    /// A `:` after an identifier property name that a value follows, inside
    /// an object literal: `{ pattern "x" }` → `{ pattern: "x" }`.
    private static func missingColonCandidates(_ code: String) -> [Candidate] {
        let pattern = #"[{,]\s*([A-Za-z_$][A-Za-z0-9_$]*)[ \t]+(?=["'`\d\[{A-Za-z_$-])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = code as NSString
        return regex.matches(in: code, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let nameRange = match.range(at: 1)
            let name = source.substring(with: nameRange)
            guard !keywords.contains(name) else { return nil }
            let end = nameRange.location + nameRange.length
            let repaired = source.replacingCharacters(in: NSRange(location: end, length: 0), with: ":")
            return Candidate(
                code: repaired,
                note: "added ':' after '\(name)' on line \(line(atUTF16Offset: end, in: code))")
        }
    }

    /// A `,` at the end of a line whose next line starts another property or
    /// item: `pattern: "a"⏎ path: "b"` → `pattern: "a",⏎ path: "b"`.
    private static func missingCommaCandidates(_ code: String) -> [Candidate] {
        var lines = code.components(separatedBy: "\n")
        guard lines.count > 1,
            let nextStart = try? NSRegularExpression(pattern: #"^\s*([A-Za-z_$][A-Za-z0-9_$]*\s*:|["'`\d\[{-])"#)
        else { return [] }
        var candidates: [Candidate] = []
        for index in lines.indices.dropLast() {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let last = trimmed.last, last.isLetter || last.isNumber || "\"'`)]}_$".contains(last),
                let next = lines[(index + 1)...].first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
                nextStart.firstMatch(in: next, range: NSRange(location: 0, length: (next as NSString).length)) != nil
            else { continue }
            let original = lines[index]
            let trailing = original.reversed().prefix { $0 == " " || $0 == "\t" }.count
            lines[index] = String(original.dropLast(trailing)) + "," + String(original.suffix(trailing))
            candidates.append(
                Candidate(code: lines.joined(separator: "\n"), note: "added ',' at the end of line \(index + 1)"))
            lines[index] = original
        }
        return candidates
    }

    /// An extra closer at the end removed, or a missing one added there:
    /// `f({ a: 1 }));` → `f({ a: 1 });`, and `f({ a: 1 }` → `f({ a: 1 })`.
    private static func closerCandidates(_ code: String) -> [Candidate] {
        var body = code
        while let last = body.last, last.isWhitespace { body.removeLast() }
        let semicolon = body.hasSuffix(";")
        if semicolon { body.removeLast() }
        let end = semicolon ? ";" : ""
        var candidates: [Candidate] = []
        if let last = body.last, closers.contains(last) {
            candidates.append(
                Candidate(code: String(body.dropLast()) + end, note: "removed an extra '\(last)' at the end"))
        }
        for closer in closers {
            candidates.append(Candidate(code: body + String(closer) + end, note: "added a missing '\(closer)' at the end"))
        }
        return candidates
    }
}
