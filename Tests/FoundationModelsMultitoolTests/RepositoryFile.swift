import Foundation

/// Reads files that live in this repository, found relative to this source
/// file through `#filePath`.
///
/// `#filePath` resolves relative to the file that contains the literal, so
/// the navigation in `read(relativePath:)` starts at this helper's own
/// location: `Tests/FoundationModelsMultitoolTests/RepositoryFile.swift`.
/// Three `deletingLastPathComponent()` steps go from this file to the
/// repository root. Keep this file directly inside
/// `Tests/FoundationModelsMultitoolTests/`, or adjust the step count to
/// match the new location.
enum RepositoryFile {
    /// Reads one repository file as UTF-8 text.
    ///
    /// - Parameter relativePath: the file's path from the repository root,
    ///   for example `".github/workflows/ci.yml"` or `"README.md"`.
    /// - Returns: the file's full text.
    /// - Throws: `RepositoryFileError.pathEscapesRepository` when the path
    ///   contains `..` or starts with `/`, or an error when the file cannot
    ///   be read.
    static func read(relativePath: String) throws -> String {
        // Reject a path with ".." or a leading "/", because such a path can
        // point to a file outside the repository.
        guard !relativePath.contains(".."), !relativePath.hasPrefix("/") else {
            throw RepositoryFileError.pathEscapesRepository(relativePath)
        }
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RepositoryFile.swift → FoundationModelsMultitoolTests/
            .deletingLastPathComponent() // → Tests/
            .deletingLastPathComponent() // → repository root
            .appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}

/// The failure that `RepositoryFile.read(relativePath:)` throws when the
/// given path is not safe.
enum RepositoryFileError: Error, CustomStringConvertible {
    /// The path contains `..` or starts with `/`, so it can point to a file
    /// outside the repository.
    case pathEscapesRepository(String)

    var description: String {
        switch self {
        case .pathEscapesRepository(let relativePath):
            return "relativePath \"\(relativePath)\" must stay inside the repository: "
                + "it must not contain \"..\" and must not start with \"/\"."
        }
    }
}
