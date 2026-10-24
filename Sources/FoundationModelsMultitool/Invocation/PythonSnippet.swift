// `PythonSnippet` — a `runCode` snippet that is plainly Python runs with
// python3 ("Postel's rule": be liberal in what you accept).
//
// SWE-bench run bench24-1023b, django__django-14382 (child session, seq
// 11129): the model sent `import os` / `for t in [...]:` / `return results`
// to `runCode`, and it failed with "Unexpected identifier 'os'. import call
// expects one or two arguments." The model meant to run Python.
//
// The rule that keeps this safe: only a snippet that does NOT parse as
// JavaScript, that has a line only Python has, and that has no JavaScript
// declaration or `tools.*` call is run this way. It runs as one
// `tools.shell.execute` call, thus with the sandbox, the timeout, and the
// permission of every other shell command of the session, and only on a
// surface that has that verb.

import Foundation

/// The run of a snippet that is Python.
enum PythonSnippet {

    /// The note a Python run closes with.
    static let note = "This snippet was Python; it ran with python3."

    /// The start of the line the Python program prints its value on.
    private static let valueMark = "__MULTITOOL_PYTHON_VALUE__"

    /// A line only Python has: an import, a definition, or a block header
    /// that ends with `:`.
    private static let pythonLine = try? NSRegularExpression(
        pattern: #"^(import [\w.]+( as \w+)?(\s*,\s*[\w.]+( as \w+)?)*|from [\w.]+ import .+|(async )?def \w+\(.*\)( -> .+)?:|class \w+(\(.*\))?:|(for|while|if|elif|with|except)\b.*:|(else|try|finally|except):)\s*$"#
    )

    /// A mark of JavaScript, whose presence keeps the snippet JavaScript.
    private static let javaScriptMark = try? NSRegularExpression(
        pattern: #"\b(const|let|var|await|function)\b|=>|\btools\.|[;{]\s*$"#
    )

    /// The lines of `code`, with each line that is a `//` or `#` comment
    /// left out.
    private static func codeLines(_ code: String) -> [String] {
        code.components(separatedBy: "\n").filter {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("#")
        }
    }

    /// Whether `code` is plainly Python: a line only Python has, and no mark
    /// of JavaScript. A dict literal (`results[t] = {`) ends with `{` in
    /// Python too, thus a line that opens a block with `{` is not a mark
    /// when a Python block header is there.
    ///
    /// - Parameter code: a snippet that does not parse as JavaScript.
    /// - Returns: whether to run it as Python.
    static func looksLikePython(_ code: String) -> Bool {
        guard let pythonLine, let javaScriptMark else { return false }
        let lines = codeLines(code)
        func matches(_ regex: NSRegularExpression, _ line: String) -> Bool {
            regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
        }
        let python = lines.contains { matches(pythonLine, $0.trimmingCharacters(in: .whitespaces)) }
        let javaScript = lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // `x = {` opens a dict in Python; only `;` ends a JavaScript line.
            return matches(javaScriptMark, trimmed) && !(trimmed.hasSuffix("{") && !trimmed.contains(";") && python)
        }
        return python && !javaScript
    }

    /// The Python program of `code`: its body inside a function, thus a
    /// top-level `return` works, and the returned value printed as JSON on
    /// a line of its own (its `repr` when it is not JSON).
    static func program(of code: String) -> String {
        let body = code.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let python = trimmed.hasPrefix("//") ? line.replacingOccurrences(of: "//", with: "#") : line
            return "    " + python
        }
        return """
            import json as __multitool_json
            def __multitool_snippet():
            \(body.joined(separator: "\n"))
                pass
            __multitool_value = __multitool_snippet()
            try:
                print("\(valueMark)" + __multitool_json.dumps(__multitool_value))
            except (TypeError, ValueError):
                print("\(valueMark)" + __multitool_json.dumps(repr(__multitool_value)))
            """
    }

    /// The JavaScript snippet that runs the Python `code` with
    /// `tools.shell.execute`, in the working directory of the shell (the
    /// session root), with the `.venv` of the clone when it has one.
    ///
    /// Its value is the value the Python returned; each other line the
    /// Python printed goes to the console. When the Python fails, its value
    /// is the output, traceback included.
    ///
    /// - Parameter code: the Python snippet of the model.
    /// - Returns: the JavaScript snippet.
    static func javaScript(running code: String) -> String {
        let encoded = Data(program(of: code).utf8).base64EncodedString()
        let command =
            "P=python3; if [ -x .venv/bin/python ]; then P=.venv/bin/python; fi; "
            + "printf '%s' '\(encoded)' | base64 --decode | \"$P\" - 2>&1"
        let commandLiteral = String(
            decoding: (try? JSONSerialization.data(withJSONObject: [command])) ?? Data("[\"\"]".utf8), as: UTF8.self)
        return """
            const r = await tools.shell.execute({ command: \(commandLiteral)[0] });
            if (r.pending) { return r; }
            const lines = (r.output || []).map((l) => String(l).replace(/^\\d+: /, ""));
            const at = lines.map((l) => l.startsWith("\(valueMark)")).lastIndexOf(true);
            if (r.exitCode !== 0 || at < 0) { return lines.join("\\n"); }
            lines.forEach((l, i) => { if (i !== at) { console.log(l); } });
            return JSON.parse(lines[at].slice(\(valueMark.count)));
            """
    }
}
