/// plan.md Component 8 (the other half of "Discovery"): forwards the agent
/// loop's `findAPIs(task)` step to a `Librarian`, formatting its decoded
/// `FoundAPIs` result into the text spliced into the next main-agent turn.
///
/// `Librarian` answers *what* is relevant; `FindAPITool` owns *how that
/// answer reaches the main agent's transcript* — splicing each selected
/// function's `signature`/`doc`/`example` through **verbatim** (never
/// re-derived or re-rendered), so the main model reads exactly what the
/// librarian selected.
struct FindAPITool: Sendable {
    /// The librarian this tool forwards every `findAPIs(task)` call to.
    private let librarian: Librarian

    /// Creates a `findAPIs` dispatcher over `librarian`.
    ///
    /// - Parameter librarian: the librarian to forward every `findAPIs(task)`
    ///   call to.
    init(librarian: Librarian) {
        self.librarian = librarian
    }

    /// Dispatches one `findAPIs(task)` step: asks `librarian`, then formats
    /// its result into the text to feed back into the main agent's
    /// transcript.
    ///
    /// - Parameter task: the plain-language goal the model passed to
    ///   `findAPIs`.
    /// - Returns: the text to splice into the next main-agent turn.
    /// - Throws: whatever `librarian.findAPIs(task:)` throws.
    func dispatch(task: String) async throws -> String {
        let found = try await librarian.findAPIs(task: task)
        return Self.format(task: task, found: found)
    }

    /// Formats a `FoundAPIs` result into the text spliced into the main
    /// agent's transcript — one block per selected function, each function's
    /// `signature`/`doc`/`example` copied through unmodified.
    ///
    /// - Parameters:
    ///   - task: the plain-language goal the model passed to `findAPIs`,
    ///     echoed in the header line so the transcript reads naturally
    ///     alongside `runCode`'s own result feedback (mirrors
    ///     `MultiToolAgent`'s existing `runCode result:` framing).
    ///   - found: the librarian's decoded result.
    /// - Returns: the formatted text.
    static func format(task: String, found: FoundAPIs) -> String {
        guard !found.functions.isEmpty else {
            return "findAPIs(\"\(task)\") found no matching functions."
        }
        let blocks = found.functions.map { api in
            "\(api.signature)\n\(api.doc)\nExample: \(api.example)"
        }
        return "findAPIs(\"\(task)\") found:\n" + blocks.joined(separator: "\n\n")
    }
}
