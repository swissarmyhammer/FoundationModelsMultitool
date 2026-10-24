// `MultiTool+ForgivingBindings` — the preamble line that makes the `tools.*`
// object forgive the plain mistakes of a model ("Postel's rule": be liberal
// in what you accept). SWE-bench runs bench24-1023 and bench24-1023b are the
// evidence; each mistake below cost the model a failed snippet.
//
// Two things happen on that one line, after every real binding is in place:
//
// 1. **The result of a files verb also acts as its main value.** A model
//    wrote `(await tools.files.read({ path })).slice(0, 2000)`, treating the
//    result as the text, and `(await tools.files.glob({ pattern })).slice(0,
//    40)`, treating it as the list. The result keeps its fields, and a name
//    it does not have reads from the text (`files.read`) or from the list
//    (`files.glob`, `files.grep`, `files.list`). Each entry of a list result
//    is a `String` object with a `name`, thus `e.name` and `e.endsWith("/")`
//    both work, and it still serializes as the plain string. A field name the
//    model guessed for that value answers it too, unless the result has a
//    real field of that name: `content`, `text`, `body`, `data` give the text
//    (`tox.content.slice(0, 1500)`, bench24-1023b django__django-14238), and
//    `items`, `results`, `entries`, `files`, `matches` give the list. A
//    `shell.execute` result answers `stdout`, `out`, `text` (its output as
//    one string, without the `N: ` of each line), `stderr` (`""`: the shell
//    merges the two streams), `code`, `returncode`, `exit` (its `exitCode`),
//    and `ok`, `success` (django__django-14534: `r.stdout.slice(-3000)`).
//    A list field that is `null` (`files.grep` on no match, or on a path that
//    is not there, beside its `correction`) reads as `[]`
//    (django__django-14608: `r2.matches.map(...)`), and each item of a list
//    result answers the names the other verbs use: `file`, `filePath`,
//    `path`; `line`, `startLine`, `lineNumber`; and `source`, `code`,
//    `body`, `snippet` for its `text`. A list result read as one item
//    answers from its first item (noqueue24 django__django-13447:
//    `s.text.slice(...)` on a `getSymbol` result), and an empty list answers
//    `undefined` there, as before. An item with only an LSP
//    `range` answers `line`, `startLine` from `range.start.line` and
//    `endLine` from `range.end.line`, as they are: every line and column of
//    `code_context` is 1-based since FoundationModelsCodeContext 223732b,
//    the same as the `line` of `files.grep` and the lines of `files.read`,
//    thus one convention holds across all groups and nothing adds or
//    subtracts 1. The list-shaped
//    `code_context` verbs act as their list too (django__django-14752:
//    `refs.map(...)` on a `grepCode` result).
// 2. **A name that is not there finds the verb it means.** `tools` and each
//    group are `Proxy` objects: a missing name is read in any letter case
//    with `_` and `-` ignored, then through ``VerbSynonyms`` (`files.search`
//    → `files.grep`), and at the top a bare verb that one group holds
//    (`tools.grep`), or a synonym (`tools.ls` → `files.list`), resolves to
//    that verb. In a group, a made-up name that holds the name of one verb
//    that reads (`listEntries` ⊃ `list`) calls it (see `containedVerbPaths`).
//    A name that nothing answers is still `undefined`, thus the
//    snippet fails the way it did before and `UnknownToolHint` answers it.
//
// The line is one line on purpose: each preamble line moves the line numbers
// of the snippet that the model reads (see `makePreamble`).

import Foundation

extension MultiTool {

    /// How a result of one verb also acts as its main value.
    ///
    /// The `code_context` symbol verbs answer `{ file, symbols: [...] }`
    /// since FoundationModelsCodeContext 502d26d, and `listSymbol` answered a
    /// bare array before; the model writes both `syms.symbols.filter(...)`
    /// and `syms.filter(...)` (SWE-bench run bench24-1023b). A path that a
    /// surface does not hold is skipped.
    private static let resultShapes: [String: String] = [
        "files.read": "text",
        "files.glob": "files",
        "files.grep": "matches",
        "files.list": "entries",
        // django__django-14608: `r1.matches.map(m => m.file)`, see `aliased`;
        // django__django-14752: `refs.map(...)`. The field names are those of
        // the FoundationModelsCodeContext results; `searchSymbol` answers a
        // bare list.
        "code_context.grepCode": "matches",
        "code_context.searchCode": "hits",
        "code_context.searchSymbol": "symbols",
        "code_context.getReferences": "references",
        "code_context.getImplementations": "implementations",
        "code_context.getInboundCalls": "calls",
        "code_context.getDefinition": "locations",
        "code_context.getTypeDefinition": "locations",
        "code_context.listSymbol": "symbols",
        "code_context.getSymbol": "symbols",
        // django__django-14534: `r.stdout.slice(-3000)`, see `asShell`.
        "shell.execute": "shell",
    ]

    /// The JS object, as source, that maps each bound synonym to its paths,
    /// in table order: one name can mean a verb of each group.
    private static var synonymTableSource: String {
        var table: [String: [String]] = [:]
        for row in VerbSynonyms.rows where row.binds {
            for verb in row.verbs { table[verb, default: []].append(row.path) }
        }
        let data = (try? JSONSerialization.data(withJSONObject: table, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The verbs a made-up name that holds their name, or a synonym of it,
    /// calls: `files.listEntries` → `files.list` (bench24-1023b,
    /// django__django-14382). Only verbs that read are here, thus a name such
    /// as `files.deleteAllFiles` never runs anything. The read verbs of
    /// `code_context` are here too (django__django-14411:
    /// `searchSymbolByName` → `searchSymbol`); `rebuildIndex` and the LSP
    /// start and stop verbs are not.
    private static let containedVerbPaths: [String] = [
        "files.read", "files.list", "files.glob", "files.grep",
        "code_context.searchSymbol", "code_context.getSymbol", "code_context.listSymbol",
        "code_context.grepCode", "code_context.searchCode", "code_context.getDefinition",
        "code_context.getTypeDefinition", "code_context.getReferences", "code_context.getImplementations",
        "code_context.getInboundCalls", "code_context.getHover", "code_context.getCallgraph",
        "code_context.getBlastradius",
    ]

    /// The JS object, as source, that maps each name of 4 or more letters of a
    /// ``containedVerbPaths`` verb (the verb and its synonyms) to its paths.
    private static var containedTableSource: String {
        var table: [String: [String]] = [:]
        for path in containedVerbPaths {
            let verb = String(path.split(separator: ".").last ?? "")
            let names = [VerbSynonyms.normalized(verb)] + (VerbSynonyms.rows.first { $0.path == path }?.verbs.sorted() ?? [])
            for name in names where name.count >= 4 { table[name, default: []].append(path) }
        }
        let data = (try? JSONSerialization.data(withJSONObject: table, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The preamble line of the forgiving bindings — see the file comment.
    ///
    /// It must run after every `tools.*` assignment, because it wraps the
    /// verbs that are there and puts a `Proxy` in front of each group.
    static var forgivingBindingsLine: String {
        let shapes = (try? JSONSerialization.data(withJSONObject: resultShapes, options: [.sortedKeys]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return """
            (function () { \
            const synonyms = \(synonymTableSource); const shapes = \(shapes); const contained = \(containedTableSource); \
            const norm = (k) => String(k).toLowerCase().replace(/[_-]/g, ""); \
            const tag = /^\\d+:[0-9a-f]{2}\\|/; \
            const textNames = ["content", "text", "body", "data"]; \
            const listNames = ["items", "results", "entries", "files", "matches", "hits", "symbols", "references", "locations"]; \
            const textOf = (v) => { if (!v || typeof v !== "object") { return String(v); } \
            if (Array.isArray(v.lines) && (v.lines.length > 0 || !v.correction)) { return v.lines.map((l) => String(l).replace(tag, "")).join("\\n"); } \
            return v.correction ? String(v.correction) : ""; }; \
            const isIndex = (k) => typeof k === "string" && /^\\d+$/.test(k); \
            const asText = (v) => { if (!v || typeof v !== "object") { return v; } let text; const t = () => (text === undefined ? (text = textOf(v)) : text); \
            return new Proxy(v, { get(target, k) { \
            if (k === Symbol.toPrimitive) { return () => t(); } \
            if (k === "toString" || k === "valueOf") { return () => t(); } \
            if (Reflect.has(target, k)) { return Reflect.get(target, k); } \
            if (textNames.includes(k)) { return t(); } \
            if (k === "length") { return t().length; } \
            if (isIndex(k)) { return t()[k]; } \
            const m = String.prototype[k]; if (typeof m === "function") { return m.bind(t()); } \
            return undefined; } }); }; \
            const sameString = (a, b) => a !== null && a !== undefined && b !== null && b !== undefined && String(a) === String(b); \
            const named = (list) => { const out = list.map((e) => { if (typeof e !== "string") { return e; } const s = new String(e); \
            Object.defineProperty(s, "name", { value: e.endsWith("/") ? e.slice(0, -1) : e }); \
            Object.defineProperty(s, "isDirectory", { value: e.endsWith("/") }); return s; }); \
            Object.defineProperty(out, "includes", { value: (x) => out.some((e) => sameString(e, x)) }); \
            Object.defineProperty(out, "indexOf", { value: (x) => out.findIndex((e) => sameString(e, x)) }); return out; }; \
            const matchNames = { file: "file", filepath: "file", path: "file", filename: "file", line: "line", startline: "line", lineno: "line", linenumber: "line", endline: "end", text: "text", content: "text", linetext: "text", source: "text", code: "text", body: "text", snippet: "text" }; \
            const matchFields = { file: ["file", "filePath", "path"], line: ["line", "startLine", "lineNumber"], end: ["endLine"], text: ["text", "content"] }; \
            const rangeLine = (target, kind) => { const r = target.range; const p = r && typeof r === "object" ? (kind === "line" ? r.start : kind === "end" ? r.end : undefined) : undefined; \
            return p && typeof p.line === "number" ? p.line : undefined; }; \
            const aliased = (m) => (!m || typeof m !== "object" ? m : new Proxy(m, { get(target, k) { \
            if (typeof k !== "string" || Reflect.has(target, k)) { return Reflect.get(target, k); } \
            const kind = matchNames[norm(k)]; const real = kind && matchFields[kind].find((n) => Reflect.has(target, n)); \
            return real ? target[real] : rangeLine(target, kind); } })); \
            const asArray = (v, field) => { if (!v || typeof v !== "object") { return v; } \
            if (field === "entries" && Array.isArray(v.entries)) { v.entries = named(v.entries); } \
            if (field !== "entries" && Array.isArray(v[field])) { v[field] = v[field].map(aliased); } \
            const list = () => { const a = v[field]; if (Array.isArray(a)) { return a; } \
            const other = listNames.find((n) => Array.isArray(v[n])); return other ? v[other] : []; }; \
            return new Proxy(v, { get(target, k) { \
            if (Reflect.has(target, k)) { const real = Reflect.get(target, k); \
            return (real === null || real === undefined) && (k === field || listNames.includes(k)) ? list() : real; } \
            const a = list(); \
            if (listNames.includes(k)) { return a; } \
            if (k === "length") { return a.length; } \
            if (k === Symbol.iterator) { return a[Symbol.iterator].bind(a); } \
            if (isIndex(k)) { return a[k]; } \
            const m = a[k]; if (typeof m === "function") { return m.bind(a); } \
            if (typeof k === "string" && field !== "entries" && a[0] && typeof a[0] === "object") { return a[0][k]; } \
            return undefined; } }); }; \
            const shellNames = { stdout: "text", out: "text", text: "text", stderr: "stderr", code: "code", returncode: "code", exit: "code", exitstatus: "code", ok: "ok", success: "ok" }; \
            const asShell = (v) => { if (!v || typeof v !== "object") { return v; } \
            const text = () => (Array.isArray(v.output) ? v.output : []).map((l) => String(l).replace(/^\\d+: /, "")).join("\\n"); \
            return new Proxy(v, { get(target, k) { \
            if (typeof k !== "string" || Reflect.has(target, k)) { return Reflect.get(target, k); } \
            const kind = shellNames[norm(k)]; \
            if (kind === "text") { return text(); } \
            if (kind === "stderr") { return ""; } \
            if (kind === "code") { return target.exitCode; } \
            if (kind === "ok") { return target.exitCode === undefined ? undefined : target.exitCode === 0; } \
            return undefined; } }); }; \
            const shaped = (fn, shape) => function (...args) { const pending = fn(...args); \
            return new Proxy(Object.create(Object.getPrototypeOf(pending)), { get(_, k) { \
            if (k === "then") { return (onFulfilled, onRejected) => pending.then((v) => { const s = shape(v); return typeof onFulfilled === "function" ? onFulfilled(s) : s; }, onRejected); } \
            return Reflect.get(pending, k); } }); }; \
            for (const path of Object.keys(shapes)) { const [g, verb] = path.split("."); \
            if (tools[g] && typeof tools[g][verb] === "function") { const kind = shapes[path]; \
            tools[g][verb] = shaped(tools[g][verb], kind === "text" ? asText : kind === "shell" ? asShell : (v) => asArray(v, kind)); } } \
            const isGroup = (v) => v !== null && typeof v === "object"; \
            const groups = Object.keys(tools).filter((g) => isGroup(tools[g])); \
            for (const g of groups) { tools[g] = new Proxy(tools[g], { get(target, k) { \
            if (typeof k !== "string" || Reflect.has(target, k)) { return Reflect.get(target, k); } \
            const n = norm(k); const same = Object.keys(target).find((verb) => norm(verb) === n); if (same) { return target[same]; } \
            const inGroup = (paths) => (paths || []).filter((p) => p.startsWith(g + ".") && typeof target[p.slice(g.length + 1)] === "function"); \
            const path = inGroup(synonyms[n])[0]; if (path) { return target[path.slice(g.length + 1)]; } \
            const held = Object.keys(contained).filter((c) => n.includes(c) && inGroup(contained[c]).length > 0); \
            const longest = Math.max(0, ...held.map((c) => c.length)); \
            const meant = [...new Set(held.filter((c) => c.length === longest).flatMap((c) => inGroup(contained[c])))]; \
            if (meant.length === 1) { return target[meant[0].slice(g.length + 1)]; } \
            return undefined; } }); } \
            globalThis.tools = new Proxy(tools, { get(target, k) { \
            if (typeof k !== "string" || Reflect.has(target, k)) { return Reflect.get(target, k); } \
            const n = norm(k); \
            const top = Object.keys(target).find((name) => !isGroup(target[name]) && norm(name) === n); if (top) { return target[top]; } \
            const owners = groups.filter((g) => Object.keys(target[g]).some((verb) => norm(verb) === n)); \
            if (owners.length === 1) { return target[owners[0]][k]; } \
            const path = (synonyms[n] || []).find((p) => { const [g, verb] = p.split("."); return isGroup(target[g]) && typeof target[g][verb] === "function"; }); \
            if (path) { const [g, verb] = path.split("."); return target[g][verb]; } \
            return undefined; } }); \
            })();
            """
    }
}
