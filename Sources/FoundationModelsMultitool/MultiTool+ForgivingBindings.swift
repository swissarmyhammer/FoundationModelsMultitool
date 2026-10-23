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
//    both work, and it still serializes as the plain string.
// 2. **A name that is not there finds the verb it means.** `tools` and each
//    group are `Proxy` objects: a missing name is read in any letter case
//    with `_` and `-` ignored, then through ``VerbSynonyms`` (`files.search`
//    → `files.grep`), and at the top a bare verb that one group holds
//    (`tools.grep`), or a synonym (`tools.ls` → `files.list`), resolves to
//    that verb. A name that nothing answers is still `undefined`, thus the
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
        "code_context.listSymbol": "symbols",
        "code_context.getSymbol": "symbols",
    ]

    /// The JS object, as source, that maps each bound synonym to its path.
    private static var synonymTableSource: String {
        var table: [String: String] = [:]
        for row in VerbSynonyms.rows where row.binds {
            for verb in row.verbs { table[verb] = row.path }
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
            const synonyms = \(synonymTableSource); const shapes = \(shapes); \
            const norm = (k) => String(k).toLowerCase().replace(/[_-]/g, ""); \
            const tag = /^\\d+:[0-9a-f]{2}\\|/; \
            const textOf = (v) => { if (!v || typeof v !== "object") { return String(v); } \
            if (Array.isArray(v.lines) && (v.lines.length > 0 || !v.correction)) { return v.lines.map((l) => String(l).replace(tag, "")).join("\\n"); } \
            return v.correction ? String(v.correction) : ""; }; \
            const isIndex = (k) => typeof k === "string" && /^\\d+$/.test(k); \
            const asText = (v) => { if (!v || typeof v !== "object") { return v; } let text; const t = () => (text === undefined ? (text = textOf(v)) : text); \
            return new Proxy(v, { get(target, k) { \
            if (k === Symbol.toPrimitive) { return () => t(); } \
            if (k === "toString" || k === "valueOf") { return () => t(); } \
            if (Reflect.has(target, k)) { return Reflect.get(target, k); } \
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
            const asArray = (v, field) => { if (!v || typeof v !== "object") { return v; } \
            if (field === "entries" && Array.isArray(v.entries)) { v.entries = named(v.entries); } \
            const list = () => { const a = v[field]; if (Array.isArray(a)) { return a; } return Array.isArray(v.files) ? v.files : []; }; \
            return new Proxy(v, { get(target, k) { \
            if (Reflect.has(target, k)) { return Reflect.get(target, k); } \
            const a = list(); \
            if (k === "length") { return a.length; } \
            if (k === Symbol.iterator) { return a[Symbol.iterator].bind(a); } \
            if (isIndex(k)) { return a[k]; } \
            const m = a[k]; if (typeof m === "function") { return m.bind(a); } \
            return undefined; } }); }; \
            const shaped = (fn, shape) => function (...args) { const pending = fn(...args); \
            return new Proxy(Object.create(Object.getPrototypeOf(pending)), { get(_, k) { \
            if (k === "then") { return (onFulfilled, onRejected) => pending.then((v) => { const s = shape(v); return typeof onFulfilled === "function" ? onFulfilled(s) : s; }, onRejected); } \
            return Reflect.get(pending, k); } }); }; \
            for (const path of Object.keys(shapes)) { const [g, verb] = path.split("."); \
            if (tools[g] && typeof tools[g][verb] === "function") { const kind = shapes[path]; \
            tools[g][verb] = shaped(tools[g][verb], kind === "text" ? asText : (v) => asArray(v, kind)); } } \
            const isGroup = (v) => v !== null && typeof v === "object"; \
            const groups = Object.keys(tools).filter((g) => isGroup(tools[g])); \
            for (const g of groups) { tools[g] = new Proxy(tools[g], { get(target, k) { \
            if (typeof k !== "string" || Reflect.has(target, k)) { return Reflect.get(target, k); } \
            const n = norm(k); const same = Object.keys(target).find((verb) => norm(verb) === n); if (same) { return target[same]; } \
            const path = synonyms[n]; if (path && path.startsWith(g + ".")) { return target[path.slice(g.length + 1)]; } \
            return undefined; } }); } \
            globalThis.tools = new Proxy(tools, { get(target, k) { \
            if (typeof k !== "string" || Reflect.has(target, k)) { return Reflect.get(target, k); } \
            const n = norm(k); \
            const top = Object.keys(target).find((name) => !isGroup(target[name]) && norm(name) === n); if (top) { return target[top]; } \
            const owners = groups.filter((g) => Object.keys(target[g]).some((verb) => norm(verb) === n)); \
            if (owners.length === 1) { return target[owners[0]][k]; } \
            const path = synonyms[n]; if (path) { const [g, verb] = path.split("."); if (isGroup(target[g])) { return target[g][verb]; } } \
            return undefined; } }); \
            })();
            """
    }
}
