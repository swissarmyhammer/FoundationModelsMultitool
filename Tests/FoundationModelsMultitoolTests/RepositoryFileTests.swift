import Foundation
import Testing

/// Makes sure `RepositoryFile` finds the repository from this source file and
/// stays inside it.
///
/// Two properties are pinned. `read(relativePath:)` and
/// `swiftFiles(inRelativeDirectory:)` reject a path that can point outside the
/// repository; without that check, a path with `..` or a leading `/` reads
/// files that are not in the repository. And `root` and
/// `swiftFiles(inRelativeDirectory:)` really find the tree, because a guard
/// built on a walk that finds no file passes while it reads nothing.
@Suite("RepositoryFile")
struct RepositoryFileTests {
    @Test("read(relativePath:) rejects a path that contains \"..\"")
    func readRejectsParentDirectoryPath() {
        #expect(throws: RepositoryFileError.self) {
            _ = try RepositoryFile.read(relativePath: "../outside")
        }
    }

    @Test("read(relativePath:) rejects an absolute path")
    func readRejectsAbsolutePath() {
        #expect(throws: RepositoryFileError.self) {
            _ = try RepositoryFile.read(relativePath: "/etc/hosts")
        }
    }

    @Test("root names the directory that holds the package manifest")
    func rootHoldsThePackageManifest() {
        let manifestURL = RepositoryFile.root.appendingPathComponent("Package.swift")
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))
    }

    @Test("swiftFiles(inRelativeDirectory:) finds a file nested under the directory")
    func swiftFilesFindsANestedFile() throws {
        let files = try RepositoryFile.swiftFiles(inRelativeDirectory: "Tests")
        let thisHelper = RepositoryFile.root
            .appendingPathComponent("Tests/FoundationModelsMultitoolTests/RepositoryFile.swift")
        #expect(files.contains { $0.path == thisHelper.path })
    }

    @Test("swiftFiles(inRelativeDirectory:) returns Swift files only")
    func swiftFilesReturnsSwiftFilesOnly() throws {
        let files = try RepositoryFile.swiftFiles(inRelativeDirectory: "Sources")
        #expect(files.allSatisfy { $0.pathExtension == "swift" })
    }

    @Test("swiftFiles(inRelativeDirectory:) rejects a path that contains \"..\"")
    func swiftFilesRejectsParentDirectoryPath() {
        #expect(throws: RepositoryFileError.self) {
            _ = try RepositoryFile.swiftFiles(inRelativeDirectory: "../outside")
        }
    }

    @Test("swiftFiles(inRelativeDirectory:) rejects a directory that is not there")
    func swiftFilesRejectsAMissingDirectory() {
        #expect(throws: RepositoryFileError.self) {
            _ = try RepositoryFile.swiftFiles(inRelativeDirectory: "NoSuchDirectory")
        }
    }
}
