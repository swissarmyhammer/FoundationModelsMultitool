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
// parse error goes back as before. The same slip can be on more than one line
// (bench24-1023b, django__django-14672): when no edit parses but exactly one
// moves the parse error to a later line, that edit is kept and the repair
// goes on from it, up to `mostEdits` edits.

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

    /// What the parser says of one source.
    enum ParseCheck: Equatable {
        /// The source parses.
        case parses
        /// The source does not parse; `line` is the line the parser blames,
        /// when it names one.
        case fails(line: Int?)
    }

    /// The most edits one repair makes. The same slip on two lines took two
    /// (bench24-1023b, django__django-14672, seq 17753).
    static let mostEdits = 5

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
        repair(
            code, check: { parses($0) ? .parses : .fails(line: nil) },
            candidates: { candidates ?? Self.candidates(for: $0) })
    }

    /// The repair of one or more edits that makes `code` parse, or `nil`.
    ///
    /// Each step tries every candidate of the code so far. When exactly one
    /// parses, that is the repair. When none parses but exactly one moves the
    /// parse error to a later line, that edit is kept and the next step
    /// starts from it, up to ``mostEdits`` edits. Any other step — two that
    /// parse, or not exactly one that gets further — answers `nil`.
    ///
    /// - Parameters:
    ///   - code: the snippet that does not parse.
    ///   - check: what the interpreter's own parser says of a source.
    ///   - candidates: the repairs to try of a source.
    ///   - mostEdits: the most edits to make.
    /// - Returns: the repaired snippet and the note of every edit, or `nil`.
    static func repair(
        _ code: String, check: (String) -> ParseCheck,
        candidates: (String) -> [Candidate] = candidates(for:), mostEdits: Int = mostEdits
    ) -> Candidate? {
        var current = code
        var notes: [String] = []
        guard case .fails(var failingLine) = check(code) else { return nil }
        for _ in 0..<mostEdits {
            var seen: Set<String> = []
            let checked = candidates(current).filter { seen.insert($0.code).inserted }.map { ($0, check($0.code)) }
            let parsing = checked.filter { $0.1 == .parses }
            if parsing.count == 1, let only = parsing.first?.0 {
                return Candidate(code: only.code, note: joinedNote(notes + [only.note]))
            }
            guard parsing.isEmpty, let line = failingLine else { return nil }
            let further = checked.compactMap { candidate, result -> (Candidate, Int)? in
                guard case .fails(let next?) = result, next > line else { return nil }
                return (candidate, next)
            }
            guard further.count == 1, let (step, next) = further.first else { return nil }
            current = step.code
            notes.append(step.note)
            failingLine = next
        }
        return nil
    }

    /// The notes of several edits as one: the same edit on several lines is
    /// said once, `added '}' before ')' on lines 2 and 3`.
    private static func joinedNote(_ notes: [String]) -> String {
        guard notes.count > 1 else { return notes.first ?? "" }
        let parts = notes.map { note -> (String, String)? in
            guard let range = note.range(of: #"line \d+$"#, options: .regularExpression) else { return nil }
            return (String(note[..<range.lowerBound]), String(note[range].dropFirst("line ".count)))
        }
        let heads = Set(parts.map { $0?.0 })
        guard heads.count == 1, let head = heads.first ?? nil else { return notes.joined(separator: "; ") }
        let lines = parts.compactMap { $0?.1 }
        return "\(head)lines \(lines.dropLast().joined(separator: ", ")) and \(lines.last ?? "")"
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
            + lineCloserCandidates(code) + closerBeforeParenCandidates(code)
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

    /// A missing closer added at the end of one line, before its final `;`
    /// when it has one: `f({ a: 1 };` → `f({ a: 1 });` on any line, not only
    /// the last (bench24-1023b, django__django-14017, seq 7751).
    private static func lineCloserCandidates(_ code: String) -> [Candidate] {
        var lines = code.components(separatedBy: "\n")
        var candidates: [Candidate] = []
        for index in lines.indices {
            let original = lines[index]
            var body = Substring(original)
            while let last = body.last, last.isWhitespace { body.removeLast() }
            guard !body.isEmpty else { continue }
            let tail = original.dropFirst(body.count)
            let semicolon = body.hasSuffix(";")
            if semicolon { body.removeLast() }
            let end = (semicolon ? ";" : "") + tail
            for closer in closers {
                lines[index] = body + String(closer) + end
                candidates.append(
                    Candidate(
                        code: lines.joined(separator: "\n"),
                        note: "added a missing '\(closer)' at the end of line \(index + 1)"))
            }
            lines[index] = original
        }
        return candidates
    }

    /// A missing `}` or `]` added before the last `)` of one line:
    /// `f({ a: 1 );` → `f({ a: 1 });` (bench24-1023b, django__django-14672,
    /// seq 17733).
    private static func closerBeforeParenCandidates(_ code: String) -> [Candidate] {
        var lines = code.components(separatedBy: "\n")
        var candidates: [Candidate] = []
        for index in lines.indices {
            let original = lines[index]
            guard let paren = original.lastIndex(of: ")") else { continue }
            for closer in ["}", "]"] {
                var edited = original
                edited.insert(contentsOf: closer, at: paren)
                lines[index] = edited
                candidates.append(
                    Candidate(code: lines.joined(separator: "\n"), note: "added '\(closer)' before ')' on line \(index + 1)"))
            }
            lines[index] = original
        }
        return candidates
    }
}
