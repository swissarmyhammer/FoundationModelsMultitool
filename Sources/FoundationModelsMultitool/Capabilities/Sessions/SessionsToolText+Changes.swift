// The text of the change operations of the `sessions` tool: the answers of
// `start session`, `tag session`, `untag session`, `rename session` and
// `archive session`, and their correctives (session.md section 8.2).

import FoundationModelsExtras
import ULID

extension SessionsToolText {
    /// The name of the `message` argument of `start session`.
    static let messageParameter = "message"

    /// The name of the `title` argument of `rename session`.
    static let titleParameter = "title"

    /// The sentence of the answer of `start session`.
    static let startSentence = "The session works in the background. Its reply comes to you as a message."

    /// The sentence of the answer of `archive session`.
    static let archiveSentence = "The session is archived. Its work stopped, and it takes no more messages."

    /// The corrective of a `tag session` or `untag session` call with no tag.
    static let noTags = "Give at least one tag. \(tagRule)"

    /// The code-mode verb of `start session`, which the corrective of an
    /// archived session names.
    static var startSessionVerb: String {
        OperationVerbTool.verbName(for: StartSession.opString)
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
    /// - Parameters:
    ///   - id: The session.
    ///   - title: The new title.
    /// - Returns: The answer.
    static func renamed(_ id: ULID, to title: String) -> String {
        "Session \(id.ulidString) has the title \"\(title)\"."
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
    /// - Returns: The corrective, which names `startSession`.
    static func archivedAlready(_ id: ULID) -> String {
        """
        Session \(id.ulidString) is archived already: it does no work and takes no messages. \
        To go on with its work, call \(startSessionVerb) to start a new session.
        """
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
