import Foundation
import Testing

import FoundationModelsMultitool

/// Pins the file-change record as a host sees it.
///
/// This file imports `FoundationModelsMultitool` PLAINLY — it carries no
/// `@testable` — thus each name it uses must be genuinely public. A type, an
/// initializer, a property, or a method that goes back to `internal` stops this
/// file from building, and that is the point of the plain import.
///
/// Nothing here touches the disk. What is under test is the shape of the
/// exchange: a host builds a ``FileChange`` and a ``FileChangeSet`` from
/// values, reads their fields back, and decodes the envelope an
/// `OperationEvent.detail` carries.
@Suite("File change set public surface")
struct FileChangeSetPublicSurfaceTests {

    /// The session root each test roots its set at. It is already
    /// symlink-resolved, the way `FileChangeJournal` roots a drained set.
    private static let root = URL(fileURLWithPath: "/private/tmp/session", isDirectory: true)

    /// The absolute path of the file each test's rename starts from.
    private static let sourcePath = "/private/tmp/session/source.txt"

    /// The absolute path of the file each test's rename ends at.
    private static let destinationPath = "/private/tmp/session/dest.txt"

    /// The rename each test builds, from outside the module.
    private static let rename = FileChange(
        kind: .move,
        path: sourcePath,
        destinationPath: destinationPath,
        oldContent: "keep me\n",
        newContent: "keep me\n"
    )

    /// The set each test builds, from outside the module.
    private static let changeSet = FileChangeSet(root: root, changes: [rename])

    @Test("a host outside the module builds a change and reads its fields back")
    func hostBuildsAChange() {
        let change = Self.rename

        #expect(change.kind == FileChangeKind.move)
        #expect(change.kind.rawValue == "move")
        #expect(change.path == Self.sourcePath)
        #expect(change.destinationPath == Self.destinationPath)
        #expect(change.oldContent == "keep me\n")
        #expect(change.newContent == "keep me\n")
    }

    @Test("a host outside the module builds a change set and reads its fields back")
    func hostBuildsAChangeSet() {
        let set = Self.changeSet

        #expect(set.root == Self.root)
        #expect(set.changes == [Self.rename])
        #expect(set.patch.contains("rename from source.txt"))
    }

    @Test("a host reads the envelope off an OperationEvent detail")
    func hostReadsTheEnvelope() throws {
        let text = Self.changeSet.encodedOperationEventDetail()

        #expect(FileChangeSet.operationEventDetailKey == "fileChanges")
        #expect(text.hasPrefix("{\"\(FileChangeSet.operationEventDetailKey)\":"))
        let decoded = try #require(FileChangeSet(operationEventDetail: text))
        #expect(decoded == Self.changeSet)
    }

    @Test("a host tells a plain notify detail from the envelope")
    func hostRejectsAPlainDetail() {
        #expect(FileChangeSet(operationEventDetail: "starting the sweep") == nil)
    }
}
