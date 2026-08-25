import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the ``PathCorrective`` shared vocabulary.
///
/// The read and edit verbs of the files capability compose
/// ``PathCorrective/unreadableDescription`` and
/// ``PathCorrective/pathErrorMessage(description:path:)`` behind `private`
/// members. Thus these tests pin the shared vocabulary itself directly. They
/// guard the exact wording and the `<description>: <path>` shape, which both
/// operations depend on staying byte identical.
@Suite struct PathCorrectiveTests {
    @Test func unreadableDescriptionIsPinned() {
        #expect(PathCorrective.unreadableDescription == "The file could not be read")
    }

    @Test func pathErrorMessageFormatsDescriptionAndPath() {
        #expect(
            PathCorrective.pathErrorMessage(description: "The file could not be read", path: "/tmp/example.txt")
                == "The file could not be read: /tmp/example.txt")
    }

    @Test func pathErrorMessageComposesTheUnreadableDescription() {
        #expect(
            PathCorrective.pathErrorMessage(description: PathCorrective.unreadableDescription, path: "/tmp/blocked.txt")
                == "The file could not be read: /tmp/blocked.txt")
    }

    @Test func readDataReturnsTheOnDiskBytesOnSuccess() throws {
        let directory = TestSupport.makeTemporaryDirectory(named: "PathCorrectiveTests")
        let url = directory.appendingPathComponent("example.txt", isDirectory: false)
        try Data("hello".utf8).write(to: url)

        switch PathCorrective.readData(at: url, path: url.path) {
        case .success(let data):
            #expect(data == Data("hello".utf8))
        case .failure(let failure):
            Issue.record("expected success, got failure: \(failure.correctiveMessage)")
        }
    }

    @Test func readDataReturnsTheUnreadableCorrectiveOnFailure() {
        let missing = URL(fileURLWithPath: "/tmp/PathCorrectiveTests-does-not-exist.txt")

        switch PathCorrective.readData(at: missing, path: "/tmp/reported-path.txt") {
        case .success:
            Issue.record("expected failure reading a nonexistent file")
        case .failure(let failure):
            #expect(failure.correctiveMessage == "The file could not be read: /tmp/reported-path.txt")
        }
    }
}
