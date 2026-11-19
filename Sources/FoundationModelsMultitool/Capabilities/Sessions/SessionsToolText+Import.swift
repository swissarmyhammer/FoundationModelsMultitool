// The text of the `list imports` and `import session` operations of the
// `sessions` tool: their answers and their correctives (D209 (l)).
//
// An earlier import of a source is only information: the answer names it,
// and an import of that source makes a new session (Q85).

import Foundation
import FoundationModelsExtras
import ULID

extension SessionsToolText {
    /// The name of the `agent` argument of the import operations.
    static let agentParameter = "agent"

    /// The name of the `source` argument of `import session`.
    static let sourceParameter = "source"

    /// The name of the UI command that imports a session and gives access to
    /// the sessions of an agent, which the correctives name.
    static let importUICommand = "Import Sessions…"

    /// The sentence of a corrective that tells that `import session` did not
    /// import.
    static let importNotRunSentence = "Nothing was imported."

    /// The sentence of a corrective that tells that `list imports` did not
    /// list.
    static let importListNotRunSentence = "Nothing was listed."

    /// The text of a source session with no title.
    private static let noTitleText = "(no title)"

    /// The text of a source session with no folder.
    private static let noFolderText = "(no folder)"

    /// The text of a source session with no date.
    private static let noDateText = "no date"

    /// The corrective of an import operation on a server whose host gives no
    /// importer.
    static let noImporter = """
        This server cannot list or import the sessions of other agents: its host gives no session importer. The \
        user can import a session with the command \(importUICommand) of the File menu.
        """

    /// The last line of each answer of `list imports`.
    static let importAdvice = """
        To import a session, use \(ImportSession.opString) with its agent and its source id. Each import makes a new \
        session, also when the session was imported before.
        """

    /// The line of `list imports` when no session matches.
    static let noImportableSession = "No session of another agent matches."

    /// The line of `list imports` when more sessions follow the page.
    static let moreImportableSessions = """
        More sessions match. Give a larger limit, an agent or a folder to see them.
        """

    /// The corrective of a source agent whose sessions the host cannot read,
    /// and the line of `list imports` for that agent.
    ///
    /// - Parameter agent: The source agent.
    /// - Returns: The text, which tells the agent to ask the user.
    static func noSourceAccess(_ agent: String) -> String {
        """
        No access to the sessions of \(agent). Ask the user to run \(importUICommand) to give access to them. An \
        agent cannot give access to a folder.
        """
    }

    /// The corrective of a folder of a new session that does not exist or
    /// that the host cannot write.
    ///
    /// - Parameter folder: The folder.
    /// - Returns: The corrective, which names the `folder` argument.
    static func importFolderUnavailable(_ folder: URL) -> String {
        """
        The folder \(folder.path) does not exist, or this app has no access to it. \(importNotRunSentence) Give the \
        absolute path of a folder that exists and that the user opened in the app in the `folder` argument, or ask \
        the user to open the folder.
        """
    }

    /// The corrective of an importer that could not list the sessions.
    ///
    /// - Parameter error: The error of the importer.
    /// - Returns: The corrective, which names the error and the UI command.
    static func importListFailed(_ error: any Error) -> String {
        """
        The list of the sessions of other agents failed: \(error). Try the call again. The user can import a \
        session with the command \(importUICommand) of the File menu.
        """
    }

    /// The corrective of an importer that could not import a session.
    ///
    /// - Parameters:
    ///   - order: The order of the import.
    ///   - error: The error of the importer.
    /// - Returns: The corrective, which names the source and the error.
    static func importFailed(_ order: SessionImportOrder, _ error: any Error) -> String {
        """
        The import of the session \(order.source) of \(order.agent) failed: \(error). Use \(ListImports.opString) to \
        find the source id, and try the call again.
        """
    }

    /// The answer of `list imports`: one line for each session, one line for
    /// each agent with no access, and ``importAdvice``.
    ///
    /// - Parameter outcome: The page, with the session of each earlier
    ///   import that the viewer can see.
    /// - Returns: The answer.
    static func importList(_ outcome: ImportableSessionsOutcome) -> String {
        let page = outcome.page
        let sessionLines =
            page.sessions.isEmpty
            ? [noImportableSession]
            : page.sessions.map { importableLine(of: $0, summaries: outcome.summaries) }
        let moreLines = page.nextCursor == nil ? [] : [moreImportableSessions]
        let accessLines = page.unreadableSources.map(noSourceAccess)
        return (sessionLines + moreLines + accessLines + [importAdvice]).joined(separator: "\n")
    }

    /// The answer of `import session`.
    ///
    /// - Parameter outcome: The new session, as the directory gives it.
    /// - Returns: The answer, with the short id, the name, the id and the
    ///   folder of the new session, and the number of records that the import
    ///   did not read.
    static func imported(_ outcome: SessionImportOutcome) -> String {
        let summary = outcome.summary
        return """
            Imported the session \(outcome.order.source) of \(outcome.order.agent) as the new session \
            @\(summary.shortID) "\(name(of: summary))" (id \(summary.id.ulidString)) in \
            \(summary.workingDirectory.path). The import did not read \(outcome.skippedRecordCount) records of the \
            source. The source did not change.
            """
    }

    /// The line of one session to import: `<agent> <source id> "<title>"
    /// (<folder>) <date> – <n> turns`, then `, imported <date> as @<short
    /// id>` for each earlier import.
    ///
    /// - Parameters:
    ///   - session: The session to import.
    ///   - summaries: The session of each earlier import that the viewer can
    ///     see. An earlier import with no session shows its full id.
    /// - Returns: The line.
    private static func importableLine(of session: ImportableSession, summaries: [ULID: SessionSummary]) -> String {
        let title = session.title.map { "\"\($0)\"" } ?? noTitleText
        let folder = session.folder.map { "(\($0.path))" } ?? noFolderText
        let date = session.lastDate.map { $0.formatted(.iso8601) } ?? noDateText
        let imports = session.previousImports.map { previous in
            ", imported \(previous.importedAt.formatted(.iso8601)) as @\(summaries[previous.session]?.shortID ?? previous.session.ulidString)"
        }
        return "\(session.agent) \(session.sourceID) \(title) \(folder) \(date) – \(session.turnCount) turns"
            + imports.joined()
    }
}
