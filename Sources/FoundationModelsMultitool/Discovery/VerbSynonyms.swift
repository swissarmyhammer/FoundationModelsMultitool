// `VerbSynonyms` — the other names a model uses for a verb of a
// package-owned capability, in one table that two readers share.
//
// The `tools.*` preamble binds a synonym as a hidden alias of its verb, thus
// `tools.files.search(...)` runs `tools.files.grep(...)` ("Postel's rule": be
// liberal in what you accept — SWE-bench run bench24-1023b). The
// unknown-tool hint reads the same table, by meaning, before it compares
// names, thus a synonym that is not bound still names the right verb.

/// One row: a real path, and the verb names a model uses for it.
struct VerbSynonym: Sendable {

    /// The catalog path that does the work, without its `tools.` prefix.
    let path: String

    /// The verb names a model calls for that work, in lowercase with no `_`
    /// or `-` (see ``VerbSynonyms/normalized(_:)``).
    let verbs: Set<String>

    /// Whether the preamble binds the names as callable aliases.
    ///
    /// `false` for a verb whose guess must never run the work unasked: a
    /// rollback, which undoes other work of the session. A delete binds since
    /// SWE-bench run bench24-1023b (django__django-13933): it is bounded to
    /// one file, or to an empty directory, inside the root.
    let binds: Bool
}

/// The table of ``VerbSynonym`` rows.
///
/// Each row is one path of a capability this package owns, so the path and
/// the work it does are known here. A row answers only when its path is in
/// the surface.
///
/// The evidence: the SWE-bench run of 2026-10-05 called `listFiles` and `find`
/// for `files.glob`, and `run` for `shell.execute`. Run bench24-1023b called
/// `files.search` for `files.grep` and a bare `ls` for `files.list`. The
/// other names of each row are the same intent in the words of a shell. The
/// user named `reset` and `rewind` as the other names of a rollback (task
/// `^f4d43vr`).
enum VerbSynonyms {

    /// The rows, one for each path.
    static let rows: [VerbSynonym] = [
        VerbSynonym(path: "files.read", verbs: ["cat", "view", "show", "open", "readfile", "getfile", "readtext", "get"], binds: true),
        VerbSynonym(path: "files.write", verbs: ["writefile", "save", "savefile", "createfile"], binds: true),
        VerbSynonym(path: "files.list", verbs: ["ls", "dir", "listdir", "listdirectory", "readdir", "lsdir", "listfolder"], binds: true),
        VerbSynonym(path: "files.glob", verbs: ["find", "findfiles", "listfiles"], binds: true),
        VerbSynonym(path: "files.grep", verbs: ["search", "searchfiles", "rg", "findtext", "searchtext"], binds: true),
        VerbSynonym(path: "shell.execute", verbs: ["run", "exec", "runcommand", "command", "sh", "bash"], binds: true),
        VerbSynonym(
            path: "files.makeDirectory",
            verbs: ["mkdir", "makedir", "createdirectory", "createdir", "newdirectory"], binds: true),
        VerbSynonym(
            path: "files.delete",
            verbs: ["remove", "rm", "unlink", "del", "deletefile", "removefile", "erase", "trash"], binds: true),
        VerbSynonym(
            path: "files.removeDirectory", verbs: ["rmdir", "removedir", "deletedirectory", "deletedir"], binds: true),
        VerbSynonym(path: "snapshots.rollback", verbs: ["reset", "rewind"], binds: false),
        // The read verbs of the `code_context` group of
        // FoundationModelsCodeContext. bench24-1023b, django__django-14411:
        // `tools.code_context.search({ query })` for `searchSymbol`. A name
        // that a files row holds too (`search`, `find`, `grep`) answers in
        // the group it is called in.
        VerbSynonym(
            path: "code_context.searchSymbol",
            verbs: ["search", "find", "lookup", "symbol", "findsymbol", "searchsymbols"], binds: true),
        VerbSynonym(
            path: "code_context.getDefinition",
            verbs: ["definition", "goto", "gotodefinition", "finddefinition", "def"], binds: true),
        VerbSynonym(
            path: "code_context.getReferences",
            verbs: ["references", "refs", "usages", "findreferences", "findusages"], binds: true),
        VerbSynonym(
            path: "code_context.getInboundCalls",
            verbs: ["callers", "whocalls", "incomingcalls", "inboundcalls"], binds: true),
        VerbSynonym(
            path: "code_context.listSymbol", verbs: ["symbols", "outline", "listsymbols", "filesymbols"], binds: true),
        VerbSynonym(path: "code_context.grepCode", verbs: ["grep"], binds: true),
        VerbSynonym(path: "code_context.getCallgraph", verbs: ["callgraph"], binds: true),
        VerbSynonym(path: "code_context.getBlastradius", verbs: ["blastradius", "impact"], binds: true),
    ]

    /// `name` in the form the table holds: lowercase, with no `_` or `-`.
    ///
    /// Thus `listFiles`, `list_files` and `ListFiles` read as one name.
    ///
    /// - Parameter name: a verb name as a model wrote it.
    /// - Returns: the normalized name.
    static func normalized(_ name: String) -> String {
        String(name.lowercased().filter { $0 != "_" && $0 != "-" })
    }

    /// The row whose verbs hold `verb`, or `nil`.
    ///
    /// - Parameter verb: a verb name as a model wrote it.
    /// - Returns: the row, or `nil` when no row names the verb.
    static func row(for verb: String) -> VerbSynonym? {
        rows(for: verb).first
    }

    /// Each row whose verbs hold `verb`, in table order: one name can mean a
    /// verb in each of two groups (`search` is `files.grep` and
    /// `code_context.searchSymbol`).
    ///
    /// - Parameter verb: a verb name as a model wrote it.
    /// - Returns: the rows.
    static func rows(for verb: String) -> [VerbSynonym] {
        let name = normalized(verb)
        return rows.filter { $0.verbs.contains(name) }
    }
}
