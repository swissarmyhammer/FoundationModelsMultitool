// MARK: - The runCode description, in each mode
//
// The description of `runCode` is the behavioral contract of a session that
// has no instructions. A registry in direct mode mounts no `searchTools`, so
// the text that tells the model to call the paths `searchTools` returned
// sends the model to a tool that does not exist. CI run 36951032341 recorded
// the result: the model guessed a call, the snippet failed, and the run lost
// one full model turn to learn the signature from the correction (task
// `^bwa2p6c`). Thus the text changes with the mode of the current registry.

extension MultiTool {
    /// This tool's `Tool`-protocol description, presented to the model as
    /// usage instructions for `runCode`.
    ///
    /// Together with `SearchToolsTool.description` this carries the **whole**
    /// behavioral contract a session needs. Mounting the two tools is the
    /// entire integration: a `Tool` conformance's description goes into the
    /// prompt on every turn, but a session instruction is optional and a host
    /// can supply none. So nothing load-bearing can live outside these two
    /// strings. `searchTools` owns the discovery mandate; this side owns the
    /// snippet, the provenance rule, and the error-recovery contract.
    ///
    /// The provenance rule — answer only from what the snippet returns — is
    /// in this text because runs reported a booking as confirmed with nothing
    /// invoked.
    ///
    /// The ambient globals' *contract* is the one part deliberately not
    /// carried here. This text is read on every turn, alongside every tool
    /// schema, so everything in it competes with the discovery mandate for
    /// the model's attention — and the globals are the part a snippet needs
    /// only once it is already writing a snippet. So this names them, closes
    /// the global world around them, and points at `docs("globals")`, which
    /// hands back the contract on demand (see
    /// `MultiTool+SandboxGlobals.swift`, "MARK: - The docs() page").
    ///
    /// **The text follows the mode of the current registry.** A registry in
    /// discovery mode gives ``discoveryDescription``, which sends the snippet
    /// to the paths `searchTools` returned. A registry in direct mode
    /// (`Registry.directMode()`) mounts no `searchTools`, so it gives
    /// ``directDescription(declaring:)``, which names no `searchTools` and
    /// declares the signature of each catalog entry. The model then reads
    /// each signature before its first snippet. The text is computed from
    /// the holder at each read, so a registry swapped in at a submission
    /// boundary changes the text too.
    public var description: String {
        let registry = holder.current.registry
        guard registry.isDirectMode else { return Self.discoveryDescription }
        return Self.directDescription(declaring: registry.surface)
    }

    /// The description of a `runCode` that a `searchTools` is mounted beside:
    /// the snippet calls the exact paths `searchTools` returned.
    static let discoveryDescription = contractText(
        pathSource: "searchTools returned",
        globalsNote: "Ambient globals never appear in searchTools — \(globalsPointer)")

    /// The description of a `runCode` in direct mode: the contract, with no
    /// `searchTools` in it, and then the signature of each entry of
    /// `surface`, under its full `tools.<path>`.
    ///
    /// The list holds each ``APISurface/Entry/declarationBlock``, and not
    /// the full block with its doc comment and its example, because this
    /// text goes into the prompt on every turn. A snippet reads the full
    /// block of one entry with `docs("<path>")`.
    ///
    /// - Parameter surface: The catalog whose entries the text declares.
    /// - Returns: The direct-mode description.
    static func directDescription(declaring surface: APISurface) -> String {
        let contract = contractText(
            pathSource: "declared below",
            globalsNote: "Ambient globals are not declared below — \(globalsPointer) "
                + "Run `docs(\"<path>\")` in a snippet to read the doc comment and an example of one function.")
        return "\(contract)\n\nThe functions under `tools.*`:\n\n\(surface.declarations)"
    }

    /// The clause that tells the model how to read the ambient globals.
    private static let globalsPointer = "run `docs(\"\(sandboxGlobalsDocsTopic)\")` in a snippet to read them."

    /// The contract text the two modes share, with the two clauses that
    /// change with the mode put in.
    ///
    /// - Parameters:
    ///   - pathSource: Where the exact `tools.*` paths come from, as the end
    ///     of the phrase "the exact `tools.*` paths …".
    ///   - globalsNote: The last sentence: where the ambient globals are not
    ///     listed, and how to read them.
    /// - Returns: The contract text.
    private static func contractText(pathSource: String, globalsNote: String) -> String {
        """
        runCode is an isolated JavaScript runtime that runs one snippet and returns what
        that snippet returns — use it for any computation (arithmetic, string work,
        dates, sorting, reshaping JSON) and for this session's functions, which it
        exposes under `tools.*`. The runtime is JavaScriptCore, core JavaScript only:
        `import` and `require` do not exist, there are no modules and no node, deno or
        bun APIs, and every function you can call is under `tools.*`. Write one snippet
        calling the exact `tools.*` paths \(pathSource), await every call, and
        `return` the final value; only that value comes back. Awaiting a call is the
        whole of how a snippet coordinates its work: do not wait() inside a snippet, and
        never time a call or poll for one. When runCode answers with `pending` false, the
        snippet is done and its result is the detail field: answer from that result. When
        runCode answers with `pending` true, the snippet is still going and you do not have
        its result: end your answer now, and the result comes back to you as a new message
        when the snippet finishes. Answer only from what the snippet returns: never
        state a fact about the user's data that did not come from a `tools.*` return
        value, and never claim success for a call the snippet did not actually return.
        When a snippet fails, fix it and call runCode again immediately. \(globalsNote)
        """
    }
}
