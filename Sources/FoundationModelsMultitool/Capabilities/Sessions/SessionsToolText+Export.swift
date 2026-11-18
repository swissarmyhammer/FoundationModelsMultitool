// The text of the `export session` operation of the `sessions` tool: its
// answer and its correctives (D202 (g)).
//
// The answer gives the path of the file, the number of lines and the title of
// the session, never the text: a transcript can be much larger than the
// context window of the model.

import Foundation
import FoundationModelsExtras
import ULID

extension SessionsToolText {
    /// The name of the `format` argument of `export session`.
    static let formatParameter = "format"

    /// The name of the `replace` argument of `export session`.
    static let replaceParameter = "replace"

    /// The name of the UI command that exports a session, which each
    /// corrective of a server that cannot export names.
    static let exportUICommand = "Export as Markdown…"

    /// The extension of the default file of an export.
    static let markdownExtension = "md"

    /// The sentence that tells the user how to export a session in the UI.
    private static let exportInUISentence =
        "The user can export a session with the command \(exportUICommand) of the Session menu."

    /// The corrective of `export session` on a server whose host gives no
    /// exporter.
    static let noExporter = """
        This server cannot export a session: its host gives no transcript exporter. Nothing was written. \
        \(exportInUISentence)
        """

    /// The file name of an export with no `path`: the slug of the session
    /// and `.md`.
    ///
    /// - Parameter summary: The session.
    /// - Returns: The file name.
    static func defaultExportName(of summary: SessionSummary) -> String {
        "\(summary.slug).\(markdownExtension)"
    }

    /// The answer of `export session`: the file, its number of lines, and
    /// the title of the session.
    ///
    /// - Parameters:
    ///   - summary: The exported session.
    ///   - file: The file that the export wrote.
    ///   - text: The text that the export wrote.
    /// - Returns: The answer, which does not hold `text`.
    static func exported(_ summary: SessionSummary, to file: URL, text: String) -> String {
        let title = summary.title.map { "Title: \"\($0)\"." } ?? "The session has no title."
        return """
            Exported session \(summary.id.ulidString) to \(file.path): \(lineCount(of: text)) lines. \(title) \
            To see the text, read the file.
            """
    }

    /// The corrective of a `path` that is absolute or goes out of the
    /// session folder.
    ///
    /// - Parameters:
    ///   - path: The path, as written.
    ///   - folder: The session folder.
    /// - Returns: The corrective.
    static func pathOutOfFolder(_ path: String, folder: URL) -> String {
        """
        The path "\(path)" is not in the session folder \(folder.path). Nothing was written. Give a file name or a \
        relative path in the session folder.
        """
    }

    /// The corrective of an export to a file that exists, with no
    /// `replace`.
    ///
    /// - Parameter file: The file.
    /// - Returns: The corrective, which names the path and `replace`.
    static func exportFileExists(_ file: URL) -> String {
        """
        The file \(file.path) exists already. Nothing was written. Give \(replaceParameter): true to replace it, \
        or give a different path.
        """
    }

    /// The corrective of an exporter that could not give the transcript.
    ///
    /// - Parameters:
    ///   - id: The session.
    ///   - error: The error of the exporter.
    /// - Returns: The corrective, which names the UI command.
    static func exportFailed(_ id: ULID, error: any Error) -> String {
        """
        The transcript of session \(id.ulidString) could not be exported: \(error). Nothing was written. \
        \(exportInUISentence)
        """
    }

    /// The corrective of an export whose file could not be written.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - error: The error of the write.
    /// - Returns: The corrective.
    static func exportWriteFailed(_ file: URL, error: any Error) -> String {
        "The export could not write the file \(file.path): \(error). Give a different path."
    }

    /// The number of lines of `text`. A line feed at the end of the text
    /// does not start a new line, and an empty text has no lines.
    ///
    /// - Parameter text: The text.
    /// - Returns: The number of lines.
    private static func lineCount(of text: String) -> Int {
        guard !text.isEmpty else {
            return 0
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return text.hasSuffix("\n") ? lines.count - 1 : lines.count
    }
}
