// The `export session` operation of the `sessions` tool (D202 (g), D100: the
// agent can do what the UI can do).
//
// The operation writes the Markdown of the transcript of a session to a file
// in the session folder, and answers the path, the number of lines and the
// title, never the text. The host gives the Markdown through a
// ``SessionTranscriptExporter``. With no exporter, the operation gives a
// corrective that names the UI command Export as Markdown….
//
// The operation acts for the caller session, as the change operations do: a
// call with no caller gives a corrective. Each error is a corrective text,
// never a thrown model error.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Operations
import ULID

/// The format of an export. Markdown is the only format now (D202 (g)).
enum SessionExportFormat: String, CaseIterable, Sendable {
    /// A Markdown document.
    case markdown
}

/// What one export asks for, after the tool read its arguments.
struct SessionExportOptions: Sendable {
    /// The format of the file.
    let format: SessionExportFormat

    /// True to include the thoughts of the agent.
    let includeThoughts: Bool

    /// The `path` as written, or `nil` for the default file.
    let path: String?

    /// True to replace a file that exists.
    let replace: Bool
}

/// Writes the transcript of a session to a Markdown file in the session
/// folder (`export session`).
@Generable
@Operation(
    verb: "export", noun: "session",
    description: """
        Export the transcript of a session as a Markdown file in the session folder. Gives the path of the file, \
        the number of lines and the title, not the text: to see the text, read the file.
        """)
struct ExportSession {
    /// The session to export: its id, its short id or its slug.
    @Guide(description: SessionsToolText.optionalSessionReference)
    @OperationParam(aliases: ["sessionId", "session"])
    var id: String?

    /// The format of the file.
    @Guide(description: "Optional. The format of the file: markdown, the default and the only format.")
    var format: String?

    /// True to include the thoughts of the agent.
    @Guide(description: "Optional. True to include the thoughts of the agent. The default is false.")
    @OperationParam(aliases: ["includeThoughts"])
    var thoughts: Bool?

    /// The file, relative to the session folder.
    @Guide(
        description: """
            Optional. A file name or a relative path in the session folder. The default is the slug of the \
            session and .md.
            """)
    @OperationParam(aliases: ["file", "fileName"])
    var path: String?

    /// True to replace a file that exists.
    @Guide(description: "Optional. True to replace a file that exists. The default is false.")
    @OperationParam(aliases: ["overwrite"])
    var replace: Bool?
}

extension ExportSession {
    /// Exports the session `id`, or the caller session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The path of the file, the number of lines and the title. A
    ///   corrective for a call with no caller, a format that is not
    ///   markdown, a server with no exporter, an id that names no session
    ///   that the caller can see, a path out of the session folder, a file
    ///   that exists with no `replace`, and an export or a write that fails.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answer(asCallerOf: Self.opString) { callerID in
            let options = SessionExportOptions(
                format: try SessionsToolInput.exportFormat(format), includeThoughts: thoughts ?? false, path: path,
                replace: replace ?? false)
            let target = try await context.sessionID(referencedBy: id, defaultingTo: callerID)
            return try await context.export(session: target, with: options)
        }
    }
}

extension SessionsToolContext {
    /// Writes the transcript of a session to its file in the session folder,
    /// for `export session`.
    ///
    /// The export asks the exporter for the text only after it checks the
    /// file, so a call that writes nothing does no export.
    ///
    /// - Parameters:
    ///   - target: The session.
    ///   - options: What the export asks for.
    /// - Returns: The answer: the path of the file, the number of lines and
    ///   the title.
    /// - Throws: ``SessionsRefusal`` for a server with no exporter, a path
    ///   out of the session folder, a file that exists with no `replace`,
    ///   and an export or a write that fails;
    ///   `SessionDirectoryError.unknownSession` when the caller cannot see
    ///   the session.
    func export(session target: ULID, with options: SessionExportOptions) async throws -> String {
        let exporter = try Self.requiredExporter(self.exporter)
        let summary = try await existingSummary(of: target)
        let file = try SessionsToolInput.exportFile(
            options.path, in: summary.workingDirectory, defaultName: SessionsToolText.defaultExportName(of: summary))
        guard options.replace || !FileManager.default.fileExists(atPath: file.path) else {
            throw SessionsRefusal(.fileExists, SessionsToolText.exportFileExists(file))
        }
        let text = try await Self.transcript(
            of: target, from: exporter, format: options.format, includeThoughts: options.includeThoughts)
        do {
            try AtomicWriter.write(Data(text.utf8), to: file)
        } catch {
            throw SessionsRefusal(.writeFailed, SessionsToolText.exportWriteFailed(file, error: error))
        }
        return SessionsToolText.exported(summary, to: file, text: text)
    }

    /// The exporter of the host, for an export.
    ///
    /// The `export session` operation and the `export` field of the
    /// `sessions` endpoint refuse an export with no exporter with this one
    /// refusal.
    ///
    /// - Parameter exporter: The exporter of the host, or `nil`.
    /// - Returns: The exporter.
    /// - Throws: ``SessionsRefusal`` with the code `MISSING_EXPORTER` when
    ///   `exporter` is `nil`.
    static func requiredExporter(
        _ exporter: (any SessionTranscriptExporter)?
    ) throws(SessionsRefusal) -> any SessionTranscriptExporter {
        guard let exporter else {
            throw SessionsRefusal(.missingExporter, SessionsToolText.noExporter)
        }
        return exporter
    }

    /// The text of the transcript of a session in a format.
    ///
    /// The `export session` operation and the `export` field of the
    /// `sessions` endpoint read the text with this one call.
    ///
    /// - Parameters:
    ///   - target: The session.
    ///   - exporter: The exporter of the host.
    ///   - format: The format of the text.
    ///   - includeThoughts: True to include the thoughts of the agent.
    /// - Returns: The text.
    /// - Throws: ``SessionsRefusal`` with the code `EXPORT_FAILED` when the
    ///   exporter fails.
    static func transcript(
        of target: ULID, from exporter: any SessionTranscriptExporter, format: SessionExportFormat,
        includeThoughts: Bool
    ) async throws(SessionsRefusal) -> String {
        do {
            switch format {
            case .markdown:
                return try await exporter.markdown(of: target, includeThoughts: includeThoughts)
            }
        } catch {
            throw SessionsRefusal(.exportFailed, SessionsToolText.exportFailed(target, error: error))
        }
    }
}
