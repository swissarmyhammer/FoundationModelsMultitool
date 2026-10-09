// `FilesMakeDirectoryTests` — the behavioral suite of the
// `tools.files.makeDirectory` verb.
//
// The suite uses the same setup as `FilesWriteTests`: each test makes a
// temporary root, constructs `MakeDirectoryArguments` with the memberwise
// initializer, and calls the `MakeDirectory` verb directly. There is one test
// for each acceptance criterion of the card ^es7p0fd.

import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the `tools.files.makeDirectory` verb.
///
/// The cases are: a nested path makes each absent folder; `parents: false`
/// with an absent parent gives a correction and makes nothing; a second call
/// on the same path gives `created: false` and no correction; and a path
/// where a file is, a path outside the root, and a read-only session each
/// give a correction, change nothing on the disk, and do not throw.
@Suite struct FilesMakeDirectoryTests {
    // MARK: Test scaffolding

    /// The name of the temporary directory of one test, thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryName = "FilesMakeDirectoryTests"

    /// The nested relative path the tests make: three folders deep.
    private static let nestedPath = "a/b/c"

    /// The top folder of ``nestedPath``.
    private static let topFolder = "a"

    /// The name of the file that stands where a directory is requested.
    private static let fileName = "occupied.txt"

    /// The content of the file that stands where a directory is requested.
    private static let fileContent = "keep\n"

    /// Call the `tools.files.makeDirectory` verb over a session context.
    ///
    /// - Parameters:
    ///   - path: the directory path to make.
    ///   - parents: whether to make each absent parent folder; `nil` uses the verb's default.
    ///   - context: the session context the verb works against.
    /// - Returns: the verb's flat result.
    private static func makeDirectory(
        path: String,
        parents: Bool? = nil,
        in context: FileContext
    ) async throws -> MakeDirectoryResult {
        try await MakeDirectory(context: context)
            .call(arguments: MakeDirectoryArguments(path: path, parents: parents))
    }

    // MARK: Create

    /// A nested path makes each of its three folders under the root, and the
    /// result has `created: true` and no correction.
    @Test func nestedPathMakesEachFolder() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let context = FileContext(root: root)

        let result = try await Self.makeDirectory(path: Self.nestedPath, in: context)

        #expect(result.correction == nil)
        #expect(result.created)
        #expect(FileWalker.isDirectory(TestSupport.path(Self.nestedPath, in: root)))
        #expect(result.path.hasSuffix(Self.nestedPath))
    }

    /// With `parents: false` and the top folder absent, the result has a
    /// correction and no folder is made.
    @Test func absentParentWithoutParentsIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let context = FileContext(root: root)

        let result = try await Self.makeDirectory(path: Self.nestedPath, parents: false, in: context)

        #expect(result.correction != nil)
        #expect(!result.created)
        #expect(result.path.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: TestSupport.path(Self.topFolder, in: root)))
    }

    /// A second call on the same path gives `created: false` and no
    /// correction.
    @Test func existingDirectoryIsNotCreatedAgain() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let context = FileContext(root: root)
        _ = try await Self.makeDirectory(path: Self.nestedPath, in: context)

        let result = try await Self.makeDirectory(path: Self.nestedPath, in: context)

        #expect(result.correction == nil)
        #expect(!result.created)
        #expect(FileWalker.isDirectory(TestSupport.path(Self.nestedPath, in: root)))
    }

    // MARK: Corrections

    /// A path where a file is gives a correction and leaves the file as it
    /// was.
    @Test func pathOfAFileIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let filePath = TestSupport.path(Self.fileName, in: root)
        try Data(Self.fileContent.utf8).write(to: URL(fileURLWithPath: filePath))
        let context = FileContext(root: root)

        let result = try await Self.makeDirectory(path: filePath, in: context)

        #expect(result.correction != nil)
        #expect(!result.created)
        #expect(TestSupport.text(at: filePath) == Self.fileContent)
    }

    /// A path outside the root gives a correction and makes no folder.
    @Test func pathOutsideTheRootIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let outsidePath = TestSupport.path(Self.nestedPath, in: outside)
        let context = FileContext(root: root)

        let result = try await Self.makeDirectory(path: outsidePath, in: context)

        #expect(result.correction != nil)
        #expect(!result.created)
        #expect(!FileManager.default.fileExists(atPath: TestSupport.path(Self.topFolder, in: outside)))
    }

    /// A call on a read-only session gives a correction and makes no folder.
    @Test func readOnlySessionIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let context = FileContext(root: root, readOnly: true)

        let result = try await Self.makeDirectory(path: Self.nestedPath, in: context)

        #expect(result.correction != nil)
        #expect(!result.created)
        #expect(!FileManager.default.fileExists(atPath: TestSupport.path(Self.topFolder, in: root)))
    }
}
