import Foundation
import Testing

/// Makes sure `RepositoryFile` finds the repository from this source file and
/// stays inside it.
///
/// Three properties are pinned. `read(relativePath:)` and
/// `swiftFiles(inRelativeDirectory:)` reject a path that can point outside the
/// repository; without that check, a path with `..` or a leading `/` reads
/// files that are not in the repository. And `root` and
/// `swiftFiles(inRelativeDirectory:)` really find the tree, because a guard
/// built on a walk that finds no file passes while it reads nothing. And
/// `sightings(of:inRelativeFile:skippingCommentLines:)` separates a comment
/// line from a line of code, because a guard that reads what a file DECLARES
/// fails wrongly when prose names the banned text.
///
/// The comment tests scan this file itself. The three fixture declarations
/// below give one line of each kind the comment rule separates.
@Suite("RepositoryFile")
struct RepositoryFileTests {
    /// This file, named from the repository root.
    private static let fixturePath = RepositoryFile.relativePath(
        of: URL(fileURLWithPath: #filePath))

    /// The needle of the comment-line fixture.
    ///
    /// The scan reads this file, thus this needle is built from two pieces. A
    /// needle written as one literal stands on the line of its own
    /// declaration, and that line is code. This needle must stand on a comment
    /// line and nowhere else.
    private static let needleInAComment = "fixtureIn" + "AComment"

    // fixtureInAComment — the comment-line fixture. The first text of this
    // line is the comment marker, thus a scan that skips comments passes over
    // the line.

    /// The needle of the code-line fixture.
    ///
    /// This declaration is the fixture: the needle stands on a line of code,
    /// and no comment stands on that line.
    private static let needleInCode = "fixtureInCode"

    /// The needle of the fixture that stands after code on one line.
    ///
    /// This declaration is the fixture: the needle stands in the trailing
    /// comment of a line of code. The line is code, thus each scan reports it.
    private static let needleAfterCode = "fixtureAfter" + "Code"  // fixtureAfterCode

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

    @Test("sightings reports a comment line when skippingCommentLines is false")
    func sightingsReportsACommentLine() throws {
        let sightings = try Self.fixtureSightings(skippingCommentLines: false)
        #expect(sightings.contains { $0.hasSuffix(Self.needleInAComment) })
    }

    @Test("sightings skips a comment line when skippingCommentLines is true")
    func sightingsSkipsACommentLine() throws {
        let sightings = try Self.fixtureSightings(skippingCommentLines: true)
        #expect(!sightings.contains { $0.hasSuffix(Self.needleInAComment) })
    }

    @Test("sightings keeps a line of code when skippingCommentLines is true")
    func sightingsKeepsALineOfCode() throws {
        let sightings = try Self.fixtureSightings(skippingCommentLines: true)
        #expect(sightings.contains { $0.hasSuffix(Self.needleInCode) })
    }

    @Test("sightings keeps a needle after code when skippingCommentLines is true")
    func sightingsKeepsANeedleAfterCode() throws {
        let sightings = try Self.fixtureSightings(skippingCommentLines: true)
        #expect(sightings.contains { $0.hasSuffix(Self.needleAfterCode) })
    }

    /// Scans this file for each fixture needle.
    ///
    /// - Parameter skippingCommentLines: `true` to pass over each comment
    ///   line, `false` to read every line.
    /// - Returns: one entry for each sighting of a fixture needle.
    /// - Throws: an error when this file cannot be read.
    private static func fixtureSightings(skippingCommentLines: Bool) throws -> [String] {
        try RepositoryFile.sightings(
            of: [needleInAComment, needleInCode, needleAfterCode],
            inRelativeFile: fixturePath,
            skippingCommentLines: skippingCommentLines)
    }
}
