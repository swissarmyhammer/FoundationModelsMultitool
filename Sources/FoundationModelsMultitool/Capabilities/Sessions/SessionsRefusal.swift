// `SessionsRefusal` — a call that the shared rules of the `sessions` tool and
// of the `sessions` GraphQL endpoint refuse (MT-2, MT-10).
//
// The tool answers the corrective text of a refusal. The endpoint gives the
// same text as the message of a coded error, with the code of the refusal in
// `extensions.code`. Thus the tool op and its mutation refuse a call with one
// text (session.md section 11.4).

import FoundationModelsExtras

/// A call that the shared rules of the `sessions` tool and endpoint refuse,
/// with the corrective text that tells how to correct the call.
///
/// The tool catches it and answers ``message``; the endpoint gives it as a
/// coded error.
struct SessionsRefusal: CodedError {
    /// What the call does wrong. The raw value is the code of the endpoint.
    enum Kind: String, CaseIterable, Sendable {
        /// An id argument is not a session id.
        case invalidSessionID = "INVALID_SESSION_ID"

        /// An id argument is not a message id.
        case invalidMessageID = "INVALID_MESSAGE_ID"

        /// A page cursor is not a cursor that the endpoint gave.
        case invalidCursor = "INVALID_CURSOR"

        /// A message address is in no form, or in a form that the client
        /// cannot use.
        case invalidAddress = "INVALID_ADDRESS"

        /// A reference names more than one session (D199 (d)).
        case ambiguousReference = "AMBIGUOUS_REFERENCE"

        /// A working folder is not an absolute path of a folder.
        case invalidFolder = "INVALID_FOLDER"

        /// A text names no allowed value.
        case invalidValue = "INVALID_VALUE"

        /// A tag breaks the tag rule.
        case invalidTag = "INVALID_TAG"

        /// A tag call names no tag.
        case missingTags = "MISSING_TAGS"

        /// A text argument holds only space.
        case blankText = "BLANK_TEXT"

        /// The launcher knows no agent with the id.
        case unknownAgent = "UNKNOWN_AGENT"

        /// The server has no launcher, so it starts no session.
        case missingLauncher = "MISSING_LAUNCHER"

        /// A message is too deep in its chain of messages.
        case deepChain = "DEEP_CHAIN"

        /// A message is longer than the limit.
        case longMessage = "LONG_MESSAGE"

        /// The session is archived already.
        case archivedSession = "ARCHIVED_SESSION"

        /// The session of an unarchive is not archived (D204 (c)).
        case notArchived = "NOT_ARCHIVED"

        /// A reply answers a message from the user, not from a session.
        case userMessage = "USER_MESSAGE"

        /// A call of the agent that acts for its own session runs in no
        /// session.
        case missingCaller = "MISSING_CALLER"

        /// A client that is not a device of the user asks for a change that
        /// only a device of the user can make.
        case untrustedClient = "UNTRUSTED_CLIENT"

        /// A call of the agent names, as the source session of a message, a
        /// session that is not its caller session (D199 (f)).
        case sourceNotCaller = "SOURCE_NOT_CALLER"

        /// The server has no exporter, so it cannot export a session
        /// (D202 (g)).
        case missingExporter = "MISSING_EXPORTER"

        /// The exporter could not give the transcript of the session.
        case exportFailed = "EXPORT_FAILED"

        /// A file path is absolute, or goes out of the session folder.
        case invalidPath = "INVALID_PATH"

        /// The file of an export exists, and the call does not replace it.
        case fileExists = "FILE_EXISTS"

        /// The file of an export could not be written.
        case writeFailed = "WRITE_FAILED"

        /// The cut of a fork is not in the history of the source.
        case forkCutOutOfRange = "FORK_CUT_OUT_OF_RANGE"

        /// The server cannot fork a session.
        case forkUnsupported = "FORK_UNSUPPORTED"

        /// The server cannot import a session.
        case importUnsupported = "IMPORT_UNSUPPORTED"

        /// A token of a session search query has a wrong value (D207 (e)).
        case invalidQuery = "INVALID_QUERY"

        /// The server has no searcher, so it cannot search the transcripts
        /// of the sessions (D207 (g)).
        case missingSearcher = "MISSING_SEARCHER"

        /// The searcher could not search the transcripts of the sessions.
        case searchFailed = "SEARCH_FAILED"

        /// The server has no sharer, so it cannot share a session
        /// (D208 (k)).
        case sharingUnavailable = "SHARING_UNAVAILABLE"

        /// The session of an update or a stop of a share has no share.
        case notShared = "NOT_SHARED"

        /// The sharer could not read, make, update or stop a share.
        case shareFailed = "SHARE_FAILED"
    }

    /// The code of each kind, for the conformance check of EXTRAS-9 rule 8.
    static let codes = Kind.allCases.map(\.rawValue)

    /// What the call does wrong.
    let kind: Kind

    /// The corrective text: what is wrong, and how to correct the call.
    let message: String

    /// The code of the refusal, as `extensions.code` gives it.
    var code: String {
        kind.rawValue
    }

    /// Makes a refusal.
    ///
    /// - Parameters:
    ///   - kind: What the call does wrong.
    ///   - message: The corrective text.
    init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }
}

/// A reply to a message that the session did not get. The tool answers its
/// corrective; the endpoint gives the `NOT_FOUND` of the toolkit, so the
/// response does not tell that the message exists.
struct SessionsUnknownMessage: Error {
    /// The id of the message that the reply names.
    let id: MailID
}
