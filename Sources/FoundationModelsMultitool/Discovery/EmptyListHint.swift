/// The hint for a field read on the first item of a list that is empty.
///
/// SWE-bench run noqueue24, django__django-13710 seq 1351: the model wrote
/// `const m = grep.matches[0];` and then `m.startLine`, and the `grepCode`
/// call matched nothing. JavaScriptCore said only `undefined is not an object
/// (evaluating 'm.startLine')`, which names neither the list nor why `m` has
/// no value. This hint names both: `[0]` of a list gives `undefined` only when
/// the list has no item, so the search found nothing.
///
/// The hint reads the error message and the model's own snippet, and nothing
/// else. It answers two shapes:
///
/// - `x[0].field`, where the message itself ends in `[0]`.
/// - `name.field`, where the snippet assigns `name` from an expression that
///   ends in `[0]` (`const`, `let` or `var`).
///
/// Any other `undefined` gets no hint, because its cause is not known.
enum EmptyListHint {
    /// How the hint says that the list has no item.
    ///
    /// The only place the phrase is written, so a test reads it from here and
    /// a reword moves the test with it.
    static let emptyPhrase = "that list is empty"

    /// What the hint tells the model to do next.
    private static let advice =
        "Check the length of the list before you read an item, or search again more widely."

    /// The hint for a field read on `[0]` of an empty list, or nil.
    ///
    /// - Parameters:
    ///   - message: the message of the failed snippet.
    ///   - snippet: the code of the snippet, as the model wrote it.
    /// - Returns: the hint text, or nil when the undefined value did not come
    ///   from `[0]` of a list.
    static func hint(message: String, snippet: String) -> String? {
        let pattern = /undefined is not an object \(evaluating '(.+)\.[A-Za-z_$][A-Za-z0-9_$]*'\)/
        guard let base = message.firstMatch(of: pattern).map({ String($0.1) }) else { return nil }
        if base.hasSuffix("[0]") {
            return "`\(base)` is undefined: \(emptyPhrase), so nothing matched and `[0]` has no item. \(advice)"
        }
        guard base.wholeMatch(of: /[A-Za-z_$][A-Za-z0-9_$]*/) != nil,
            let source = firstItemSource(of: base, in: snippet)
        else { return nil }
        return "`\(base)` is undefined: it holds `\(source)`, and \(emptyPhrase), so nothing matched "
            + "and `[0]` has no item. \(advice)"
    }

    /// The expression that ends in `[0]` and that `snippet` assigns to `name`
    /// when it declares it, or nil.
    ///
    /// - Parameters:
    ///   - name: the variable name, a plain JavaScript identifier.
    ///   - snippet: the code of the snippet.
    /// - Returns: the expression, without the `;` that ends it.
    private static func firstItemSource(of name: String, in snippet: String) -> String? {
        let escaped = name.replacingOccurrences(of: "$", with: "\\$")
        guard let declaration = try? Regex<(Substring, Substring)>(
            #"(?:const|let|var)\s+"# + escaped + #"\s*=\s*([^;\n]*\[0\])\s*(?:;|\n|$)"#)
        else { return nil }
        return snippet.firstMatch(of: declaration).map { String($0.1).trimmingCharacters(in: .whitespaces) }
    }
}
