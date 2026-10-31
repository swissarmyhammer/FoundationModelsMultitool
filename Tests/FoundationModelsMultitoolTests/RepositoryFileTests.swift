import Foundation
import Testing

/// Makes sure `RepositoryFile` finds the repository from this source file and
/// stays inside it.
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
}
