import Testing

/// Makes sure `RepositoryFile.read(relativePath:)` rejects a path that can
/// point to a file outside the repository. Without this check, a path with
/// `..` or a leading `/` can read files that are not in the repository.
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
}
