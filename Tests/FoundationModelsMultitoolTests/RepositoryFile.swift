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
