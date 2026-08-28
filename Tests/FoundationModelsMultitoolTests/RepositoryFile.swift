import Foundation

/// Reads files that live in this repository, found relative to this source
/// file through `#filePath`.
///
/// `#filePath` resolves relative to the file that contains the literal, so
/// the navigation in `root` starts at this helper's own location:
/// `Tests/FoundationModelsMultitoolTests/RepositoryFile.swift`.
/// Three `deletingLastPathComponent()` steps go from this file to the
/// repository root. Keep this file directly inside
/// `Tests/FoundationModelsMultitoolTests/`, or adjust the step count to
/// match the new location.
enum RepositoryFile {
    /// The directory this repository stands in.
    ///
    /// A test that walks a whole tree needs the root itself, and not only a
    /// reader of one named file. The paths this type returns are absolute,
    /// thus a caller strips this prefix to report a path a reader can find.
    static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // RepositoryFile.swift → FoundationModelsMultitoolTests/
            .deletingLastPathComponent()  // → Tests/
            .deletingLastPathComponent()  // → repository root
    }

    /// Reads one repository file as UTF-8 text.
    ///
    /// - Parameter relativePath: the file's path from the repository root,
    ///   for example `".github/workflows/ci.yml"` or `"README.md"`.
    /// - Returns: the file's full text.
    /// - Throws: `RepositoryFileError.pathEscapesRepository` when the path
    ///   contains `..` or starts with `/`, or an error when the file cannot
    ///   be read.
    static func read(relativePath: String) throws -> String {
        try String(contentsOf: url(forRelativePath: relativePath), encoding: .utf8)
    }

    /// Walks one repository directory and gives every Swift file under it.
    ///
    /// The walk reaches each level of the tree, not the named directory
    /// alone, because the source of this package stands several directories
    /// deep. A hidden directory is passed over: `.build` holds the checkout
    /// of each dependency, and no file there is this repository's own.
    ///
    /// The result is sorted by path, thus a caller reports the same order on
    /// each run.
    ///
    /// - Parameter relativePath: the directory's path from the repository
    ///   root, for example `"Sources"` or `"Tests"`.
    /// - Returns: the absolute path of each `.swift` file under the directory.
    /// - Throws: `RepositoryFileError.pathEscapesRepository` when the path
    ///   contains `..` or starts with `/`, and
    ///   `RepositoryFileError.directoryCannotBeWalked` when the path names no
    ///   directory or the walk cannot start. A walk that answers nothing is
    ///   never reported as an empty tree, because a guard built on it would
    ///   then pass while it reads no file.
    static func swiftFiles(inRelativeDirectory relativePath: String) throws -> [URL] {
        let directoryURL = try url(forRelativePath: relativePath)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: directoryURL.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            throw RepositoryFileError.directoryCannotBeWalked(relativePath)
        }
        guard
            let walk = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
        else {
            throw RepositoryFileError.directoryCannotBeWalked(relativePath)
        }
        var swiftFiles: [URL] = []
        for case let fileURL as URL in walk where fileURL.pathExtension == "swift" {
            let isRegularFile = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                .isRegularFile
            if isRegularFile == true {
                swiftFiles.append(fileURL)
            }
        }
        return swiftFiles.sorted { $0.path < $1.path }
    }

    /// Names each needle that the Swift files under one directory hold.
    ///
    /// A guard that bans a name reads a tree and fails when the name comes
    /// back. Each guard of this target calls this one scan, thus one
    /// implementation decides what a sighting is, and no suite carries a
    /// near-identical copy.
    ///
    /// - Parameters:
    ///   - needles: the texts to search for, for example a banned type name.
    ///   - relativePath: the directory's path from the repository root, for
    ///     example `"Sources"`.
    ///   - excludedFiles: the files the walk passes over, for example a guard
    ///     file that must spell each needle to search for it. Each URL is
    ///     compared in its standardized form.
    /// - Returns: one `path:line: needle` entry for each sighting, with the
    ///   path read from the repository root.
    /// - Throws: an error when the directory cannot be walked, or when a file
    ///   under it cannot be read. A walk that reads nothing is a failure and
    ///   never an empty answer.
    static func sightings(
        of needles: [String],
        inRelativeDirectory relativePath: String,
        excluding excludedFiles: Set<URL> = []
    ) throws -> [String] {
        try swiftFiles(inRelativeDirectory: relativePath)
            .filter { !excludedFiles.contains($0.standardizedFileURL) }
            .flatMap { try sightings(of: needles, inRelativeFile: Self.relativePath(of: $0)) }
    }

    /// Names each needle that one file holds.
    ///
    /// - Parameters:
    ///   - needles: the texts to search for.
    ///   - filePath: the file's path from the repository root.
    ///   - skippingCommentLines: `true` to pass over each comment line of a
    ///     Swift file. A guard that reads what a manifest or a source file
    ///     DECLARES needs this, because prose that names the needle declares
    ///     nothing. The default is `false`, thus a scan reports a comment line
    ///     the same way it reports a line of code.
    /// - Returns: one `path:line: needle` entry for each sighting.
    /// - Throws: an error when the file cannot be read.
    static func sightings(
        of needles: [String],
        inRelativeFile filePath: String,
        skippingCommentLines: Bool = false
    ) throws -> [String] {
        let text = try read(relativePath: filePath)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .filter { !skippingCommentLines || !isCommentLine($0.element) }
            .flatMap { lineIndex, line in
                needles
                    .filter { line.contains($0) }
                    .map { "\(filePath):\(lineIndex + 1): \($0)" }
            }
    }

    /// The path of a file inside this repository, read from the repository
    /// root.
    ///
    /// - Parameter fileURL: the file's absolute location.
    /// - Returns: the same file, named the way a reader of the repository
    ///   names it, or the absolute path when the file stands outside `root`.
    static func relativePath(of fileURL: URL) -> String {
        let rootPrefix = root.path + "/"
        guard fileURL.path.hasPrefix(rootPrefix) else { return fileURL.path }
        return String(fileURL.path.dropFirst(rootPrefix.count))
    }

    /// The text that opens a comment line of a Swift file.
    private static let commentMarker = "//"

    /// Says whether one line of a Swift file is a comment.
    ///
    /// The rule is conservative: only a line whose first text is the marker is
    /// a comment. A needle inside a block comment, or after code on the same
    /// line, stands on a line this rule reads as code. The author who meets
    /// such a report moves the comment onto a line of its own.
    ///
    /// - Parameter line: one line of the file, with its indentation.
    /// - Returns: `true` when the first text of the line is `//`.
    private static func isCommentLine(_ line: Substring) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(commentMarker)
    }

    /// Resolves one repository-relative path against `root`.
    ///
    /// - Parameter relativePath: the path from the repository root.
    /// - Returns: the absolute location of that path.
    /// - Throws: `RepositoryFileError.pathEscapesRepository` when the path
    ///   contains `..` or starts with `/`, because such a path can point
    ///   outside the repository.
    private static func url(forRelativePath relativePath: String) throws -> URL {
        guard !relativePath.contains(".."), !relativePath.hasPrefix("/") else {
            throw RepositoryFileError.pathEscapesRepository(relativePath)
        }
        return root.appendingPathComponent(relativePath)
    }
}

/// The failure that `RepositoryFile` throws when it cannot answer for the
/// given path.
enum RepositoryFileError: Error, CustomStringConvertible {
    /// The path contains `..` or starts with `/`, so it can point to a file
    /// outside the repository.
    case pathEscapesRepository(String)

    /// The path names no directory of the repository, or the walk of it
    /// cannot start.
    case directoryCannotBeWalked(String)

    var description: String {
        switch self {
        case .pathEscapesRepository(let relativePath):
            return "relativePath \"\(relativePath)\" must stay inside the repository: "
                + "it must not contain \"..\" and must not start with \"/\"."
        case .directoryCannotBeWalked(let relativePath):
            return "relativePath \"\(relativePath)\" names no directory of the repository, "
                + "thus there is nothing to walk."
        }
    }
}
