// `ShadowedTools` — a snippet that declares its own `tools` still reaches the
// tool namespace ("Postel's rule": be liberal in what you accept).
//
// SWE-bench run bench24-1023b, django__django-14787 (seq 19546): the model
// wrote `const tools = await tools.files.list({ path: "Tools" })`. A `const`
// named `tools` puts the global in the temporal dead zone for the whole
// snippet, thus every `tools.*` call failed with "Cannot access 'tools'
// before initialization."
//
// The model's binding keeps its name; only the calls on the namespace are
// rewritten to `globalThis.tools`, which no binding of the snippet can hide.
// A use is a call on the namespace when it comes before the declaration
// (there it can only mean the global), or when it reads
// `tools.<group>.<verb>(` for a verb the surface holds. Any other use —
// `tools.entries.slice(...)`, a `tools:` key, `{ tools }` — is the model's
// own value and stays. The scan reads tokens, thus a `tools` inside a
// string, a template's text, a comment, or a regular expression is never
// touched. The insertion is on the same line, thus each line number holds.

import Foundation

/// The rewrite of the namespace calls of a snippet that binds `tools`.
enum ShadowedTools {

    /// The note a rewritten run closes with.
    static let note =
        "Your snippet declares its own `tools`, which hides the tool namespace; its `tools.<group>.<verb>(…)` calls ran on the namespace as `globalThis.tools`."

    /// The name that the namespace calls are rewritten to start with.
    private static let namespacePrefix = "globalThis."

    /// The keywords that declare the name after them.
    private static let declaringKeywords: Set<String> = ["const", "let", "var", "function", "class"]

    /// The keywords that start a destructuring declaration.
    private static let patternKeywords: Set<String> = ["const", "let", "var"]

    /// `code` with each namespace call on `globalThis.tools`, or `nil` when
    /// the snippet binds no `tools` or calls nothing on the namespace.
    ///
    /// - Parameters:
    ///   - code: the snippet.
    ///   - paths: the `group.verb` paths of the surface.
    /// - Returns: the rewritten snippet, or `nil`.
    static func rewrite(_ code: String, paths: [String]) -> String? {
        var scanner = JSTokenScanner(code)
        let tokens = scanner.scan()
        guard let declaration = declarationIndex(in: tokens) else { return nil }
        let known = Set(paths.map { $0.lowercased() })
        var offsets: [Int] = []
        for (index, token) in tokens.enumerated() where token.isIdentifier && token.text == "tools" {
            let previous = index > 0 ? tokens[index - 1].text : ""
            guard previous != ".", previous != "?.", text(at: index + 1, in: tokens) == "." else { continue }
            if index < declaration {
                offsets.append(token.offset)
                continue
            }
            let group = text(at: index + 2, in: tokens)
            let verb = text(at: index + 4, in: tokens)
            guard text(at: index + 3, in: tokens) == ".", text(at: index + 5, in: tokens) == "(",
                known.contains("\(group).\(verb)".lowercased())
            else { continue }
            offsets.append(token.offset)
        }
        guard !offsets.isEmpty else { return nil }
        var characters = Array(code)
        for offset in offsets.reversed() { characters.insert(contentsOf: namespacePrefix, at: offset) }
        return String(characters)
    }

    /// The text of the token at `index`, or `""` past the end.
    private static func text(at index: Int, in tokens: [JSToken]) -> String {
        tokens.indices.contains(index) ? tokens[index].text : ""
    }

    /// The index of the first token that binds `tools`, or `nil`.
    private static func declarationIndex(in tokens: [JSToken]) -> Int? {
        for (index, token) in tokens.enumerated() where token.isIdentifier {
            if token.text == "tools", index > 0, tokens[index - 1].isIdentifier,
                declaringKeywords.contains(tokens[index - 1].text)
            {
                return index
            }
            if patternKeywords.contains(token.text), let open = tokens[safe: index + 1], open.text == "{" || open.text == "[",
                let bound = patternBinding(in: tokens, from: index + 1)
            {
                return bound
            }
        }
        return nil
    }

    /// The index of a `tools` that the destructuring pattern opened at
    /// `start` binds, or `nil`: a `tools` that is not a key (`tools:`) and
    /// not an object it reads from (`tools.`).
    private static func patternBinding(in tokens: [JSToken], from start: Int) -> Int? {
        var depth = 0
        var index = start
        while index < tokens.count {
            let token = tokens[index]
            switch token.text {
            case "{", "[", "(": depth += 1
            case "}", "]", ")":
                depth -= 1
                if depth == 0 { return nil }
            default:
                if token.isIdentifier, token.text == "tools" {
                    let next = text(at: index + 1, in: tokens)
                    if next != ":", next != "." { return index }
                }
            }
            index += 1
        }
        return nil
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// One significant token of a JS source: a name, or a punctuator.
struct JSToken: Equatable {
    /// The token's text.
    let text: String
    /// The offset of its first character, in `Character`s.
    let offset: Int
    /// Whether it is a name (an identifier or a keyword).
    let isIdentifier: Bool
}

/// A small JS scanner: the names and the punctuators of a source, with each
/// string, template text, comment, and regular expression skipped.
struct JSTokenScanner {
    private let characters: [Character]
    private var index = 0
    private var tokens: [JSToken] = []

    /// The names after which a `/` starts a regular expression.
    private static let regexAfterNames: Set<String> = [
        "return", "typeof", "case", "do", "else", "in", "of", "new", "delete", "void", "throw", "yield", "await",
    ]

    /// The punctuators made of more than one character, longest first.
    private static let longPunctuators = ["?.", "...", "=>"]

    init(_ source: String) { characters = Array(source) }

    /// The tokens of the source, in order.
    mutating func scan() -> [JSToken] {
        scanCode(closingBrace: false)
        return tokens
    }

    private func peek(_ offset: Int = 0) -> Character? {
        characters.indices.contains(index + offset) ? characters[index + offset] : nil
    }

    private static func isNameStart(_ c: Character) -> Bool { c.isLetter || c == "_" || c == "$" }
    private static func isNamePart(_ c: Character) -> Bool { isNameStart(c) || c.isNumber }

    /// Scans code up to the end, or up to the `}` that closes a template's
    /// `${` when `closingBrace` is set.
    private mutating func scanCode(closingBrace: Bool) {
        var depth = 0
        while let c = peek() {
            if c.isWhitespace {
                index += 1
            } else if c == "/", peek(1) == "/" {
                while let d = peek(), d != "\n" { index += 1 }
            } else if c == "/", peek(1) == "*" {
                index += 2
                while peek() != nil, !(peek() == "*" && peek(1) == "/") { index += 1 }
                index += 2
            } else if c == "\"" || c == "'" {
                skipString(quote: c)
            } else if c == "`" {
                skipTemplate()
            } else if c == "/", regexMayStart() {
                skipRegex()
            } else if Self.isNameStart(c) {
                let start = index
                while let d = peek(), Self.isNamePart(d) { index += 1 }
                tokens.append(JSToken(text: String(characters[start..<index]), offset: start, isIdentifier: true))
            } else if c.isNumber {
                while let d = peek(), Self.isNamePart(d) || d == "." { index += 1 }
                tokens.append(JSToken(text: "0", offset: index, isIdentifier: false))
            } else {
                if closingBrace {
                    if c == "{" { depth += 1 }
                    if c == "}" {
                        if depth == 0 {
                            index += 1
                            return
                        }
                        depth -= 1
                    }
                }
                let long = Self.longPunctuators.first { p in
                    p.enumerated().allSatisfy { peek($0.offset) == $0.element }
                }
                let text = long ?? String(c)
                tokens.append(JSToken(text: text, offset: index, isIdentifier: false))
                index += text.count
            }
        }
    }

    /// Whether a `/` here starts a regular expression rather than a division.
    private func regexMayStart() -> Bool {
        guard let last = tokens.last else { return true }
        if last.isIdentifier { return Self.regexAfterNames.contains(last.text) }
        return ![")", "]", "}", "0", "\"\"", "``", "/re/"].contains(last.text)
    }

    private mutating func skipString(quote: Character) {
        index += 1
        while let c = peek(), c != quote, c != "\n" { index += c == "\\" ? 2 : 1 }
        index += 1
        tokens.append(JSToken(text: "\"\"", offset: index, isIdentifier: false))
    }

    private mutating func skipTemplate() {
        index += 1
        while let c = peek(), c != "`" {
            if c == "\\" {
                index += 2
            } else if c == "$", peek(1) == "{" {
                index += 2
                scanCode(closingBrace: true)
            } else {
                index += 1
            }
        }
        index += 1
        tokens.append(JSToken(text: "``", offset: index, isIdentifier: false))
    }

    private mutating func skipRegex() {
        index += 1
        var inClass = false
        while let c = peek(), c != "\n" {
            if c == "\\" {
                index += 2
                continue
            }
            if c == "[" { inClass = true } else if c == "]" { inClass = false } else if c == "/", !inClass { break }
            index += 1
        }
        index += 1
        while let d = peek(), d.isLetter { index += 1 }
        tokens.append(JSToken(text: "/re/", offset: index, isIdentifier: false))
    }
}
