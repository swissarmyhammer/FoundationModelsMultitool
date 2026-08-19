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
    /// - Throws: an error when the file cannot be read.
    static func read(relativePath: String) throws -> String {
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RepositoryFile.swift → FoundationModelsMultitoolTests/
            .deletingLastPathComponent() // → Tests/
            .deletingLastPathComponent() // → repository root
            .appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
