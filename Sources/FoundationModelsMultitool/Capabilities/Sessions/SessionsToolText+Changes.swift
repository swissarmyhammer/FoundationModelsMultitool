// The text of the change operations of the `sessions` tool: the answers of
// `start session`, `tag session`, `untag session`, `rename session` and
// `archive session` and `unarchive session`, and their correctives
// (session.md section 8.2, D204).

import FoundationModelsExtras
import ULID

extension SessionsToolText {
    /// The name of the `message` argument of `start session`.
    static let messageParameter = "message"

    /// The name of the `title` argument of `rename session`.
    static let titleParameter = "title"

    /// The sentence of the answer of `start session`.
    static let startSentence = "The session works in the background. Its reply comes to you as a message."

    /// The sentence of the answer of `archive session` (D204).
    static let archiveSentence = """
        The session is archived. Its turn stopped, and it is hidden from the lists. A message to it waits in its \
        inbox, and `\(UnarchiveSession.opString)` brings it back.
        """

    /// The sentence of the answer of `unarchive session` (D204 (d)).
    static let unarchiveSentence = """
        The session is unarchived: it shows in the lists again. It is a recorded session until a client opens it, \
        and its transcript and its inbox are as they were.
        """

    /// The sentence of the corrective of a session operation whose `id` names
    /// more than one session.
    static let notChangedSentence = "Nothing changed."

    /// The corrective of a `tag session` or `untag session` call with no tag.
    static let noTags = "Give at least one tag. \(tagRule)"

    /// The code-mode verb of `unarchive session`, which the corrective of a
    /// session that is archived already names (D204).
    static var unarchiveSessionVerb: String {
        OperationVerbTool.verbName(for: UnarchiveSession.opString)
    }

    /// The answer of `start session`: the new session, its agent and its
    /// folder, then ``startSentence``.
    ///
    /// - Parameter summary: The new session.
    /// - Returns: The answer.
    static func started(_ summary: SessionSummary) -> String {
        "Started session \(identity(of: summary)). \(startSentence)"
    }

    /// The answer of `tag session` and `untag session`: the tags that the
    /// session has after the call.
    ///
    /// - Parameter summary: The session after the call.
    /// - Returns: The answer.
    static func tags(of summary: SessionSummary) -> String {
        guard !summary.tags.isEmpty else {
            return "Session \(summary.id.ulidString) has no tags."
        }
        return "Session \(summary.id.ulidString) has the tags: \(tagList(of: summary))."
    }

    /// The answer of `rename session`: the new title of the session.
    ///
    /// - Parameter summary: The session after the call, which has a title.
    /// - Returns: The answer.
    static func renamed(_ summary: SessionSummary) -> String {
        "Session \(summary.id.ulidString) has the title \"\(summary.title ?? "")\"."
    }

    /// The answer of `pin session` and `unpin session`: the pin state of
    /// the session after the call.
    ///
    /// - Parameter summary: The session after the call.
    /// - Returns: The answer.
    static func pinState(of summary: SessionSummary) -> String {
        summary.isPinned
            ? "Session \(summary.id.ulidString) is pinned. It shows in the Pinned list of this server."
            : "Session \(summary.id.ulidString) is not pinned."
    }

    /// The answer of `archive session`: the session, its agent and its
    /// folder, then ``archiveSentence``.
    ///
    /// - Parameter summary: The archived session.
    /// - Returns: The answer.
    static func archived(_ summary: SessionSummary) -> String {
        "Archived session \(identity(of: summary)). \(archiveSentence)"
    }

    /// The corrective of `archive session` for a session that is archived
    /// already.
    ///
    /// - Parameter id: The archived session.
    /// - Returns: The corrective, which names `unarchiveSession`.
    static func archivedAlready(_ id: ULID) -> String {
        """
        Session \(id.ulidString) is archived already: it is hidden from the lists, and a message to it waits in its \
        inbox. To bring it back, call \(unarchiveSessionVerb).
        """
    }

    /// The answer of `unarchive session`: the session, its agent and its
    /// folder, then ``unarchiveSentence``.
    ///
    /// - Parameter summary: The unarchived session.
    /// - Returns: The answer.
    static func unarchived(_ summary: SessionSummary) -> String {
        "Unarchived session \(identity(of: summary)). \(unarchiveSentence)"
    }

    /// The corrective of `unarchive session` for a session that is not
    /// archived (D204 (c)): the call changes nothing.
    ///
    /// - Parameter id: The session.
    /// - Returns: The corrective.
    static func notArchived(_ id: ULID) -> String {
        "Session \(id.ulidString) is not archived: it shows in the lists already. \(notChangedSentence)"
    }

    /// The corrective of a text argument that holds only space.
    ///
    /// - Parameter parameter: The name of the argument.
    /// - Returns: The corrective.
    static func blankText(_ parameter: String) -> String {
        "The \(parameter) is empty. Give a \(parameter) with text."
    }

    /// The id, the agent and the folder of a session.
    ///
    /// - Parameter summary: The session.
    /// - Returns: The text.
    private static func identity(of summary: SessionSummary) -> String {
        "\(summary.id.ulidString): agent \(agent(of: summary)), folder \(summary.workingDirectory.path)"
    }
}
