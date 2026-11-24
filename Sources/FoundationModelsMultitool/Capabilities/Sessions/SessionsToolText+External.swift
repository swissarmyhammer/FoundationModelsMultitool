// The text of the `list external sessions`, `count external sessions`,
// `read external session`,
// `continue external session` and `rebuild external session index`
// operations of the `sessions` tool: their answers and their correctives
// (D212, design section 5.8).
//
// Only the user can give access to the sessions of a source, with the
// command Allow Access to <source> Sessions… of the File menu. Thus each
// corrective of a source with no access tells the agent to ask the user.

import Foundation
import FoundationModelsExtras

extension SessionsToolText {
    /// The name of the `source` argument of the external session operations.
    static let externalSourceParameter = "source"

    /// The name of the `id` argument of the external session operations.
    static let externalIDParameter = "id"

    /// The sentence of a corrective that tells that `list external sessions`
    /// did not list.
    static let externalNotListedSentence = "Nothing was listed."

    /// The sentence of a corrective that tells that
    /// `count external sessions` did not count.
    static let externalNotCountedSentence = "Nothing was counted."

    /// The sentence of a corrective that tells that
    /// `continue external session` made no session.
    static let externalNotContinuedSentence = "No session was made."

    /// The sentence of a corrective that tells that the
    /// `externalSessionChanges` subscription follows no folder.
    static let externalNotFollowedSentence = "No change is followed."

    /// The text of an external session with no title and no prompt.
    private static let noExternalTextText = "(no text)"

    /// The text of an external session with no working folder.
    private static let noExternalFolderText = "(no folder)"

    /// The text that ends a tool text that the length limit cut.
    private static let cutMark = "…"

    /// The display name of each source that the corrective of Allow Access
    /// names, by the source id.
    private static let sourceNames = ["claude-code": "Claude Code", "codex": "Codex"]

    /// The label of each kind of entry that the text of a read shows, by the
    /// kind (D209 (c)). An entry of another kind shows its kind.
    private static let entryLabels = [
        SessionsToolContext.userMessageKind: "user",
        "agent_message_chunk": "agent",
        "tool_call": "tool",
        "tool_call_update": "tool result",
        "plan": "plan",
    ]

    /// The kinds of entry whose text the read shows in full, up to the size
    /// limit of the read. The text of each other kind is cut at
    /// ``SessionsToolContext/maximumExternalToolTextLength``.
    private static let fullTextKinds: Set<String> = [SessionsToolContext.userMessageKind, "agent_message_chunk"]

    /// The corrective of an external session operation on a server whose
    /// host gives no external session host.
    static let noExternalSessionHost = """
        This server cannot read the sessions of other agents: its host gives no external session host. The user \
        can see the sessions of other agents in the sidebar of the app.
        """

    /// The last line of each answer of `list external sessions`.
    static let externalListAdvice = """
        To read a session, use \(ReadExternalSession.opString) with its source and its id. To continue it in a new \
        session of this server, use \(ContinueExternalSession.opString). Each continue makes a new session.
        """

    /// The line of `list external sessions` when no session matches.
    static let noExternalSession = "No session of another agent matches."

    /// The line of `list external sessions` when more sessions follow the
    /// page.
    static let moreExternalSessions = """
        More sessions match. Give a larger limit, a source or a folder to see them.
        """

    /// The command of the UI that gives access to the sessions of a source.
    ///
    /// - Parameter source: The source agent.
    /// - Returns: The title of the command.
    static func allowAccessCommand(_ source: String) -> String {
        "Allow Access to \(sourceNames[source] ?? source) Sessions…"
    }

    /// The corrective of a cursor that is not a cursor of a page of the
    /// list.
    ///
    /// - Parameter cursor: The cursor of the request.
    /// - Returns: The text.
    static func externalInvalidCursor(_ cursor: String) -> String {
        "The cursor \(cursor) is not a cursor of a page of this list. Use the next cursor of the last page, or no cursor."
    }

    /// The corrective of a source whose sessions the host cannot read, and
    /// the line of `list external sessions` for that source.
    ///
    /// - Parameter source: The source agent.
    /// - Returns: The text, which tells the agent to ask the user.
    static func noExternalSourceAccess(_ source: String) -> String {
        """
        No access to the sessions of \(source). Ask the user to run \(allowAccessCommand(source)) of the File menu. \
        An agent cannot give access to a folder.
        """
    }

    /// The corrective of an external session that the index does not have.
    ///
    /// - Parameter session: The external session.
    /// - Returns: The corrective.
    static func unknownExternalSession(_ session: ExternalSessionID) -> String {
        """
        The index has no session \(session.sourceID) of \(session.source). Use \(ListExternalSessions.opString) to \
        find the source and the id of a session.
        """
    }

    /// The corrective of a folder of a new session that does not exist or
    /// that the host cannot write.
    ///
    /// - Parameter folder: The folder.
    /// - Returns: The corrective, which names the `folder` argument.
    static func externalFolderUnavailable(_ folder: URL) -> String {
        """
        The folder \(folder.path) does not exist, or this app has no access to it. \(externalNotContinuedSentence) \
        Give the absolute path of a folder that exists and that the user opened in the app in the `folder` \
        argument, or ask the user to open the folder.
        """
    }

    /// The corrective of a host that could not list the external sessions.
    ///
    /// - Parameter error: The error of the host.
    /// - Returns: The corrective.
    static func externalListFailed(_ error: any Error) -> String {
        "The list of the sessions of other agents failed: \(error). Try the call again."
    }

    /// The corrective of a host that could not read an external session.
    ///
    /// - Parameters:
    ///   - session: The external session.
    ///   - error: The error of the host.
    /// - Returns: The corrective.
    static func externalReadFailed(_ session: ExternalSessionID, _ error: any Error) -> String {
        """
        The read of the session \(session.sourceID) of \(session.source) failed: \(error). Try the call again.
        """
    }

    /// The corrective of a host that could not continue an external session.
    ///
    /// - Parameters:
    ///   - request: The request of the continue.
    ///   - error: The error of the host.
    /// - Returns: The corrective.
    static func externalContinueFailed(_ request: ExternalSessionContinueRequest, _ error: any Error) -> String {
        """
        The continue of the session \(request.session.sourceID) of \(request.session.source) failed: \(error). Use \
        \(ListExternalSessions.opString) to find the source and the id, and try the call again.
        """
    }

    /// The corrective of a host that could not count the external sessions.
    ///
    /// - Parameter error: The error of the host.
    /// - Returns: The corrective.
    static func externalCountFailed(_ error: any Error) -> String {
        "The count of the sessions of other agents failed: \(error). Try the call again."
    }

    /// The answer of `count external sessions`: the line of the counts,
    /// `Sessions in the index of <source> in <folder>: <n> typed, <n>
    /// automated.`, and
    /// the line of the index state when the index is not complete for the
    /// scope of the count.
    ///
    /// - Parameter outcome: The counts of the host and their scope.
    /// - Returns: The answer.
    static func externalSessionCounts(_ outcome: ExternalSessionCountOutcome) -> String {
        let counts = outcome.counts
        let source = outcome.source.map { " of \($0)" } ?? ""
        let folder = outcome.folder.map { " in \($0.path)" } ?? ""
        let countLine =
            "Sessions in the index\(source)\(folder): \(counts.typedCount) typed, \(counts.automatedCount) automated."
        let indexLines = counts.indexState.isComplete ? [] : [incompleteIndexLine(counts.indexState)]
        return ([countLine] + indexLines).joined(separator: "\n")
    }

    /// The corrective of a host that could not rebuild the index of a
    /// source.
    ///
    /// - Parameters:
    ///   - source: The source agent.
    ///   - error: The error of the host.
    /// - Returns: The corrective.
    static func externalRebuildFailed(_ source: String, _ error: any Error) -> String {
        "The rebuild of the index of the sessions of \(source) failed: \(error). Try the call again."
    }

    /// The answer of `rebuild external session index`.
    ///
    /// - Parameter source: The source agent.
    /// - Returns: The answer, which tells that the read continues after the
    ///   call.
    static func startedExternalIndexRebuild(_ source: String) -> String {
        """
        The rebuild of the index of the sessions of \(source) started. The index removed the sessions of \(source), \
        and now finds and reads each file of \(source) again. Until the read ends, \(ListExternalSessions.opString) \
        gives fewer sessions of \(source). To see the progress, use \(CountExternalSessions.opString).
        """
    }

    /// The line of the index state when the index is not complete.
    ///
    /// - Parameter state: The index state.
    /// - Returns: The line.
    static func incompleteIndexLine(_ state: ExternalSessionIndexState) -> String {
        """
        The index is not complete: it read \(state.filesRead) of \(state.filesFound) session files. A later call \
        can give more sessions.
        """
    }

    /// The answer of `list external sessions`: one line for each session,
    /// one line for each source with no access, one line of the index state
    /// when the index is not complete, and ``externalListAdvice``.
    ///
    /// - Parameter page: The page of the host.
    /// - Returns: The answer.
    static func externalSessionList(_ page: ExternalSessionPage) -> String {
        let sessionLines = page.sessions.isEmpty ? [noExternalSession] : page.sessions.map(externalSessionLine)
        let moreLines = page.nextCursor == nil ? [] : [moreExternalSessions]
        let accessLines = page.unreadableSources.map(noExternalSourceAccess)
        // A list of one folder gives the progress of that folder, else the progress of each root.
        let state = page.folderIndexState ?? page.indexState
        let indexLines = state.isComplete ? [] : [incompleteIndexLine(state)]
        return (sessionLines + moreLines + accessLines + indexLines + [externalListAdvice]).joined(separator: "\n")
    }

    /// The line of one external session: `<source> <id> "<text>"
    /// (<folder>) <date>`, then the branch, `automated`, the state of the
    /// index when the index has not read the file, and `continued <date> as
    /// <id>` for each session that a continue made from it.
    ///
    /// - Parameter session: The external session.
    /// - Returns: The line.
    static func externalSessionLine(_ session: ExternalSessionSummary) -> String {
        let text = session.displayText.map { "\"\($0)\"" } ?? noExternalTextText
        let folder = session.cwd.map { "(\($0.path))" } ?? noExternalFolderText
        let details =
            [
                session.gitBranch.map { "branch \($0)" },
                session.isAutomated ? "automated" : nil,
                session.state == .read ? nil : "\(session.state.rawValue)",
            ]
            .compactMap { $0 }
            + session.continuedSessions.map {
                "continued \($0.createdAt.formatted(.iso8601)) as \($0.sessionID.ulidString)"
            }
        let tail = details.isEmpty ? "" : " – " + details.joined(separator: ", ")
        return "\(session.source) \(session.sourceID) \(text) \(folder) \(session.displayDate.formatted(.iso8601))"
            + tail
    }

    /// The lines of the facts of the index in the answer of
    /// `read external session`: the absolute path of the file when the index
    /// gives it, and one line for each session that a continue made from the
    /// session.
    ///
    /// - Parameter summary: The entry of the session in the index, or `nil`.
    /// - Returns: The lines, or none.
    static func externalSessionFactLines(_ summary: ExternalSessionSummary?) -> [String] {
        let fileLines = (summary?.fileURL).map { ["The file of the session is \($0.path)."] } ?? []
        return fileLines
            + (summary?.continuedSessions ?? []).map {
                "Continued \($0.createdAt.formatted(.iso8601)) as the session \($0.sessionID.ulidString)."
            }
    }

    /// The answer of `read external session`: a header line, the facts of
    /// the index, the text of each turn of the range, and the next turn to
    /// read.
    ///
    /// - Parameter reading: The turns of the range.
    /// - Returns: The answer.
    static func externalSessionText(_ reading: ExternalSessionReading) -> String {
        let name = "The session \(reading.session.sourceID) of \(reading.session.source)"
        let facts = externalSessionFactLines(reading.summary)
        let factTexts = facts.isEmpty ? [] : [facts.joined(separator: "\n")]
        guard let first = reading.turns.first, let last = reading.turns.last else {
            guard let count = reading.lastTurnOfSession, count > 0 else {
                return (["\(name) has no turns."] + factTexts).joined(separator: "\n\n")
            }
            return (["\(name) has \(count) turns. Give a fromTurn from 1 to \(count)."] + factTexts)
                .joined(separator: "\n\n")
        }
        let header = "\(name): turns \(first.number) to \(last.number)."
        let turnTexts = reading.turns.map { turn in
            (["Turn \(turn.number)"] + turn.lines).joined(separator: "\n")
        }
        let tail: [String]
        if let next = reading.nextTurn {
            let reason = reading.isCut ? "The text was cut at the size limit." : "More turns follow."
            tail = ["\(reason) To read more, use \(ReadExternalSession.opString) with fromTurn \(next)."]
        } else {
            tail = ["This is the last turn of the session."]
        }
        return ([header] + factTexts + turnTexts + tail).joined(separator: "\n\n")
    }

    /// The line of one entry of an external session in the text of a read,
    /// or `nil` for an entry that the text does not show: a thought.
    ///
    /// The line is `<label>: <text>`, or `<label> (<status>): <text>` when
    /// the entry has a status. The text is each `text` value of the payload,
    /// else its `title`.
    ///
    /// - Parameter entry: The entry.
    /// - Returns: The line, or `nil`.
    static func externalEntryLine(_ entry: SessionTranscriptEntry) -> String? {
        guard entry.kind != SessionsToolContext.thoughtKind else {
            return nil
        }
        let label = entryLabels[entry.kind] ?? entry.kind
        let status = topLevelText("status", in: entry.payload).map { " (\($0))" } ?? ""
        let title = topLevelText("title", in: entry.payload)
        let texts = textValues(in: entry.payload).joined(separator: " ")
        var body = [title, texts.isEmpty ? nil : texts].compactMap { $0 }.joined(separator: ": ")
        if !fullTextKinds.contains(entry.kind), body.count > SessionsToolContext.maximumExternalToolTextLength {
            body = String(body.prefix(SessionsToolContext.maximumExternalToolTextLength)) + cutMark
        }
        return "\(label)\(status): \(body)"
    }

    /// The text of a key at the top of a payload.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - payload: The payload of an entry.
    /// - Returns: The text, or `nil` when the payload has no text at the key.
    private static func topLevelText(_ key: String, in payload: OperationValue) -> String? {
        guard case .object(let fields) = payload, case .string(let text)? = fields[key] else {
            return nil
        }
        return text
    }

    /// Each text at a `text` key of a value, at each depth, in the order of
    /// the keys.
    ///
    /// - Parameter value: The value.
    /// - Returns: The texts.
    private static func textValues(in value: OperationValue) -> [String] {
        guard case .object(let fields) = value else {
            return []
        }
        return fields.keys.sorted().flatMap { key -> [String] in
            switch fields[key] {
            case .string(let text)? where key == "text": [text]
            case let nested?: textValues(in: nested)
            case nil: []
            }
        }
    }

    /// The answer of `continue external session`.
    ///
    /// - Parameter outcome: The new session, as the host gives it.
    /// - Returns: The answer, with the short id, the name, the id and the
    ///   folder of the new session.
    static func continuedExternalSession(_ outcome: ExternalSessionContinueOutcome) -> String {
        let summary = outcome.summary
        let session = outcome.request.session
        return """
            Continued the session \(session.sourceID) of \(session.source) as the new session @\(summary.shortID) \
            "\(name(of: summary))" (id \(summary.id.ulidString)) in \(summary.workingDirectory.path). The source did \
            not change.
            """
    }
}
