import Foundation
import Testing

/// Behavioral tests for `TestSupport.path(candidate:isContainedBy:)` — the one
/// guard a suite routes its root check through when a path must stay in a root
/// directory.
///
/// The sibling case is the defensive point of the helper. A bare
/// `hasPrefix(root)` accepts a sibling directory that only shares the string
/// prefix of the root. That is the path-traversal weakness this guard closes.
@Suite("PathContainment")
struct PathContainmentTests {
    /// The root directory each case measures containment against.
    private let root = URL(fileURLWithPath: "/tmp/test", isDirectory: true)

    @Test("the root itself is contained")
    func rootItselfIsContained() {
        #expect(TestSupport.path(candidate: root, isContainedBy: root))
    }

    @Test("a descendant of the root is contained")
    func descendantIsContained() {
        let descendant = root.appendingPathComponent("Sources/FoundationModelsMultitool/File.swift")
        #expect(TestSupport.path(candidate: descendant, isContainedBy: root))
    }

    @Test("a sibling directory that shares the root's string prefix is not contained")
    func siblingSharingPrefixIsNotContained() {
        let sibling = URL(fileURLWithPath: "/tmp/test-evil/file.swift")
        #expect(!TestSupport.path(candidate: sibling, isContainedBy: root))
    }

    @Test("a path that escapes the root through `..` is not contained")
    func parentEscapeIsNotContained() {
        let escape = root.appendingPathComponent("../etc/passwd")
        #expect(!TestSupport.path(candidate: escape, isContainedBy: root))
    }
}
