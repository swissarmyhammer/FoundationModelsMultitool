import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the ``PathGuard`` validation stack.
///
/// This suite is a port of the sibling FileTool suite, which itself mirrors
/// the Rust `swissarmyhammer-tools` `shared_utils` path-validation stack
/// (`FilePathValidator::validate_path`, `validate_file_path`,
/// `reject_filesystem_root`, `check_file_permissions`,
/// `ensure_workspace_boundary`). The tables below keep the Rust
/// `DANGEROUS_PATHS` traversal exemplars, the symlink and workspace-boundary
/// security tests, and the `check_file_permissions` expectations. Thus the
/// port rejects and accepts the same inputs the sibling does — this is
/// security-sensitive code, and the parity is the point.
@Suite struct PathGuardTests {
    // MARK: Temp-directory helpers

    /// The unique final directory-name component of a temporary directory.
    ///
    /// macOS routes the temporary directory through the `/var` ->
    /// `/private/var` symlink, thus a prefix comparison of a resolved
    /// absolute path against a raw temporary URL does not hold. The unique
    /// UUID-bearing directory name appears in the resolved path only when
    /// resolution went through that session root. Thus an assertion that the
    /// resolved path contains this name proves resolution used the session
    /// root and not the process current directory.
    private static func uniqueName(_ url: URL) -> String {
        url.lastPathComponent
    }

    // MARK: Traversal exemplars

    /// Each `../`-style traversal exemplar from the Rust `DANGEROUS_PATHS`
    /// table. The guard rejects each one as a blocked pattern, on each
    /// operation.
    private static let traversalExemplars: [String] = [
        "/tmp/../../../etc/passwd",
        "/tmp/../../etc/passwd",
        "/home/user/../../../etc/passwd",
        "../../../etc/passwd",
        "..\\..\\..\\windows\\system32\\config\\sam",
        "/var/tmp/../../../../etc/shadow",
        "~/../../etc/hosts",
        "/usr/local/../../../root/.ssh/id_rsa",
        "/tmp/../../../../../proc/version",
    ]

    @Test(arguments: traversalExemplars, [FileOperation.read, .write, .edit, .directory])
    func rejectsTraversalExemplarOnEveryOperation(path: String, operation: FileOperation) {
        let guardUnderTest = PathGuard(root: URL(fileURLWithPath: "/tmp"))
        let result = guardUnderTest.validate(path, for: operation)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(
                violation.message.contains("blocked pattern"),
                "the guard must reject the traversal exemplar \(path) as a blocked pattern, got: \(violation.message)"
            )
        }
    }

    // MARK: Length / null / control rejects

    @Test func rejectsPathLongerThanMaximum() {
        let guardUnderTest = PathGuard(root: URL(fileURLWithPath: "/tmp"))
        let overlyLong = String(repeating: "a", count: 5000)
        let result = guardUnderTest.validatePath(overlyLong)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("too long"))
        }
    }

    @Test func rejectsEmptyAndWhitespacePath() {
        let guardUnderTest = PathGuard(root: URL(fileURLWithPath: "/tmp"))
        #expect(throws: PathViolation.self) { try guardUnderTest.validatePath("").get() }
        #expect(throws: PathViolation.self) { try guardUnderTest.validatePath("   ").get() }
        // Rust's `str::trim` covers the full Unicode whitespace set, and that
        // set includes newlines. Thus a newline-only path is empty, and the
        // guard must reject it too.
        #expect(throws: PathViolation.self) { try guardUnderTest.validatePath("\n").get() }
    }

    @Test func rejectsResolvedPathExceedingMaximumLength() {
        // A short relative input that resolves under a very long session
        // root can exceed the maximum length although the raw input does
        // not. The guard re-checks the resolved path, which matches the
        // nested length check of the Rust source.
        let longRoot = "/" + String(repeating: "a", count: 5000)
        let guardUnderTest = PathGuard(root: URL(fileURLWithPath: longRoot))
        let result = guardUnderTest.validatePath("file.txt")
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("too long"))
        }
    }

    @Test func rejectsNullByte() {
        let guardUnderTest = PathGuard(root: URL(fileURLWithPath: "/tmp"))
        let result = guardUnderTest.validatePath("/tmp/foo\u{0}bar")
        #expect(throws: PathViolation.self) { try result.get() }
    }

    @Test func rejectsControlCharacter() {
        // The guard rejects a control character other than tab, newline, and
        // carriage return. The parent (the temporary directory) exists, thus
        // validation reaches the control-character gate and does not fail on
        // a missing parent first.
        let directory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let guardUnderTest = PathGuard(root: directory)
        let result = guardUnderTest.validatePath(directory.path + "/foo\u{07}bar")
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("control"))
        }
    }

    // MARK: Session-root (never CWD) relative resolution

    @Test func resolvesRelativePathAgainstSessionRootNotProcessDirectory() throws {
        let sessionRoot = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let file = sessionRoot.appendingPathComponent("relative.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)

        let guardUnderTest = PathGuard(root: sessionRoot)
        let resolved = try guardUnderTest.validatePath("relative.txt").get()

        // The relative path must resolve under the session root, never
        // under the process current directory (which does not contain
        // relative.txt).
        #expect(resolved.path.contains(Self.uniqueName(sessionRoot)))
        #expect(resolved.lastPathComponent == "relative.txt")
    }

    @Test func resolvesNestedRelativePathAgainstSessionRoot() throws {
        let sessionRoot = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let nested = sessionRoot.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "content".write(to: nested.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let guardUnderTest = PathGuard(root: sessionRoot)
        let resolved = try guardUnderTest.validatePath("nested/file.txt").get()
        #expect(resolved.path.contains(Self.uniqueName(sessionRoot)))
        #expect(resolved.path.hasSuffix("/nested/file.txt"))
    }

    // MARK: Symlink handling

    @Test func rejectsSymlinkBeforeCanonicalizationByDefault() throws {
        // The symlink target does NOT exist, thus canonicalization would
        // fail. A rejection here proves the guard refuses the symlink
        // BEFORE canonicalization.
        let directory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let link = directory.appendingPathComponent("dangling.txt")
        let target = directory.appendingPathComponent("does-not-exist.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let guardUnderTest = PathGuard(root: directory)
        let result = guardUnderTest.validatePath(link.path)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("symlink"))
        }
    }

    @Test func acceptsSymlinkWhenOptedIn() throws {
        let directory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let target = directory.appendingPathComponent("target.txt")
        try "content".write(to: target, atomically: true, encoding: .utf8)
        let link = directory.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let guardUnderTest = PathGuard(root: directory, allowSymlinks: true)
        let resolved = try guardUnderTest.validatePath(link.path).get()
        // The opt-in path resolves the symlink to its real target.
        #expect(resolved.lastPathComponent == "target.txt")
    }

    @Test func rejectsDanglingSymlinkEvenWhenSymlinksAllowed() throws {
        // Even with symlinks opted in, the guard must reject a symlink whose
        // target does not exist. Such a link cannot resolve, thus the guard
        // cannot confine it to the workspace, and a later write would follow
        // it and create a file at its (out-of-workspace) target. This
        // mirrors the Rust `resolve_symlink_securely`, which
        // re-canonicalizes and fails on a dangling link. The symlink lives
        // inside the workspace, thus only this re-resolution step — not the
        // boundary check — can catch it.
        let workspace = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let link = workspace.appendingPathComponent("dangling.txt")
        let target = workspace.appendingPathComponent("nowhere/evil.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let guardUnderTest = PathGuard(root: workspace, workspaceRoot: workspace, allowSymlinks: true)
        let result = guardUnderTest.validatePath(link.path)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("symlink"))
        }
    }

    // MARK: Workspace-boundary enforcement

    @Test func acceptsNonexistentTargetInsideWorkspace() throws {
        let workspace = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let guardUnderTest = PathGuard(root: workspace, workspaceRoot: workspace)
        // A not-yet-created write target directly under the workspace passes.
        let target = workspace.appendingPathComponent("new-file.txt")
        let resolved = try guardUnderTest.validatePath(target.path).get()
        #expect(resolved.lastPathComponent == "new-file.txt")
    }

    @Test func acceptsNonexistentTargetViaDeepestExistingParentInsideWorkspace() throws {
        let workspace = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        // The subdirectory exists but the target file does not. Thus the
        // boundary check reconstructs the target from its deepest existing
        // parent (the subdirectory) and confirms the reconstructed path is
        // inside.
        let subdirectory = workspace.appendingPathComponent("subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)

        let guardUnderTest = PathGuard(root: workspace, workspaceRoot: workspace)
        let target = subdirectory.appendingPathComponent("new-file.txt")
        let resolved = try guardUnderTest.validatePath(target.path).get()
        #expect(resolved.path.hasSuffix("/subdir/new-file.txt"))
    }

    @Test func rejectsExistingTargetOutsideWorkspace() throws {
        let workspace = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let outside = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let outsideFile = outside.appendingPathComponent("secret.txt")
        try "secret".write(to: outsideFile, atomically: true, encoding: .utf8)

        let guardUnderTest = PathGuard(root: workspace, workspaceRoot: workspace)
        let result = guardUnderTest.validatePath(outsideFile.path)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("outside workspace"))
        }
    }

    @Test func rejectsNonexistentTargetOutsideWorkspaceViaDeepestExistingParent() throws {
        let workspace = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let outside = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        // The subdirectory exists but the target file does not. Thus the
        // boundary check reconstructs the target from its deepest existing
        // parent (the outside subdirectory) and rejects it because it is
        // outside the workspace.
        let subdirectory = outside.appendingPathComponent("subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)

        let guardUnderTest = PathGuard(root: workspace, workspaceRoot: workspace)
        let target = subdirectory.appendingPathComponent("new-file.txt")
        let result = guardUnderTest.validatePath(target.path)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("outside workspace"))
        }
    }

    // MARK: Multi-root confinement

    /// A path inside a secondary root validates. A sibling path outside each
    /// configured root is rejected, and the rejection names each in-scope
    /// root.
    @Test func validatesPathInSecondaryRootAndRejectsSiblingOutsideAllRoots() throws {
        let primary = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let secondary = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let sibling = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")

        let vendoredFile = secondary.appendingPathComponent("vendored.txt")
        try "content".write(to: vendoredFile, atomically: true, encoding: .utf8)
        let siblingFile = sibling.appendingPathComponent("outside.txt")
        try "content".write(to: siblingFile, atomically: true, encoding: .utf8)

        let guardUnderTest = PathGuard(
            root: primary, workspaceRoot: primary, additionalWorkspaceRoots: [secondary]
        )

        // The secondary root validates the same way the primary root does.
        let resolved = try guardUnderTest.validatePath(vendoredFile.path).get()
        #expect(resolved.lastPathComponent == "vendored.txt")

        // A sibling directory that is not a configured root is rejected,
        // and the message names both roots that were in scope.
        let result = guardUnderTest.validatePath(siblingFile.path)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("outside workspace"))
            #expect(violation.message.contains(Self.uniqueName(primary)))
            #expect(violation.message.contains(Self.uniqueName(secondary)))
        }
    }

    /// A relative path resolves against the primary root only, even when the
    /// same filename also exists (and would match) inside a secondary root.
    @Test func relativePathResolvesAgainstPrimaryRootOnlyEvenWhenSecondaryRootMatches() throws {
        let primary = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let secondary = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        try "primary".write(to: primary.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
        try "secondary".write(to: secondary.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)

        let guardUnderTest = PathGuard(
            root: primary, workspaceRoot: primary, additionalWorkspaceRoots: [secondary]
        )
        let resolved = try guardUnderTest.validatePath("shared.txt").get()
        #expect(resolved.path.contains(Self.uniqueName(primary)))
        #expect(!resolved.path.contains(Self.uniqueName(secondary)))
    }

    /// With symlinks disallowed, the guard still rejects a symlink whose
    /// target lands in a *different* (also valid) root. A target that is
    /// technically in bounds must not quietly permit the symlink.
    @Test func rejectsSymlinkFromPrimaryRootIntoSecondaryRootWhenSymlinksDisallowed() throws {
        let primary = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let secondary = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let target = secondary.appendingPathComponent("target.txt")
        try "content".write(to: target, atomically: true, encoding: .utf8)
        let link = primary.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let guardUnderTest = PathGuard(
            root: primary, workspaceRoot: primary, additionalWorkspaceRoots: [secondary]
        )
        let result = guardUnderTest.validatePath(link.path)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("symlink"))
        }
    }

    /// Overlapping and nested roots configured fully within
    /// `additionalWorkspaceRoots` (disjoint from the primary
    /// `workspaceRoot`) do not produce double-validation or inconsistent
    /// results: a path inside the nested root still validates exactly once.
    /// The primary root is deliberately unrelated to `outer` and `inner`,
    /// thus a passing result here proves `additionalWorkspaceRoots` is
    /// load-bearing — this would fail if the additional-roots set were
    /// silently ignored, and it would be merely redundant with a
    /// fully-nested primary configuration.
    @Test func overlappingAndNestedRootsProduceConsistentResults() throws {
        let primary = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let outer = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let inner = outer.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let file = inner.appendingPathComponent("file.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)

        let guardUnderTest = PathGuard(
            root: primary, workspaceRoot: primary, additionalWorkspaceRoots: [outer, inner]
        )
        // `outer` and `inner` both contain `file.txt`. Validation still
        // succeeds exactly once regardless of the overlap.
        let resolved = try guardUnderTest.validatePath(file.path).get()
        #expect(resolved.lastPathComponent == "file.txt")

        // A path outside each configured root — the primary included — is
        // still rejected.
        let outsideDirectory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let outsideFile = outsideDirectory.appendingPathComponent("outside.txt")
        try "content".write(to: outsideFile, atomically: true, encoding: .utf8)
        let outsideResult = guardUnderTest.validatePath(outsideFile.path)
        #expect(throws: PathViolation.self) { try outsideResult.get() }
    }

    /// An additional root that fails to canonicalize (for example, one that
    /// was deleted or never existed) does not poison the whole boundary
    /// check. The guard skips it, thus a path within the still-valid
    /// primary root continues to validate.
    @Test func toleratesANonexistentAdditionalRootAndStillValidatesThePrimaryRoot() throws {
        let primary = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let file = primary.appendingPathComponent("ok.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)
        let missingRoot = primary.appendingPathComponent("does-not-exist-root", isDirectory: true)

        let guardUnderTest = PathGuard(
            root: primary, workspaceRoot: primary, additionalWorkspaceRoots: [missingRoot]
        )
        let resolved = try guardUnderTest.validatePath(file.path).get()
        #expect(resolved.lastPathComponent == "ok.txt")
    }

    /// When *every* configured root fails to canonicalize, validation still
    /// fails outright — there is nothing valid to fall back on. This keeps
    /// the pre-existing single-root behavior for an invalid `workspaceRoot`.
    @Test func rejectsEverythingWhenEveryConfiguredRootFailsToCanonicalize() throws {
        let primary = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let file = primary.appendingPathComponent("file.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)
        let missingWorkspace = primary.appendingPathComponent("does-not-exist", isDirectory: true)

        let guardUnderTest = PathGuard(root: primary, workspaceRoot: missingWorkspace)
        let result = guardUnderTest.validatePath(file.path)
        #expect(throws: PathViolation.self) { try result.get() }
    }

    /// Single-root construction (the pre-existing initializer shape, with no
    /// `additionalWorkspaceRoots` argument) stays source-compatible.
    @Test func existingSingleRootConstructionRemainsSourceCompatible() {
        let workspace = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let guardUnderTest = PathGuard(root: workspace, workspaceRoot: workspace, allowSymlinks: true)
        #expect(guardUnderTest.workspaceRoot == workspace)
        #expect(guardUnderTest.additionalWorkspaceRoots.isEmpty)
    }

    // MARK: Filesystem-root walk refusal

    @Test(arguments: ["/", ".", ""])
    func refusesFilesystemRootAndUnresolvedSearchDirectory(searchDirectory: String) {
        let guardUnderTest = PathGuard(root: URL(fileURLWithPath: "/tmp"))
        let result = guardUnderTest.rejectFilesystemRoot(searchDirectory)
        #expect(throws: PathViolation.self) { try result.get() }
    }

    @Test func acceptsNormalDirectoryAsSearchRoot() {
        let directory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let guardUnderTest = PathGuard(root: directory)
        let result = guardUnderTest.rejectFilesystemRoot(directory.path)
        #expect((try? result.get()) != nil)
    }

    // MARK: Per-operation permission checks

    @Test func rejectsReadOfDirectoryAsNonRegularFile() {
        let directory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let guardUnderTest = PathGuard(root: directory)
        let result = guardUnderTest.checkPermission(directory, for: .read)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("regular file"))
        }
    }

    @Test func rejectsReadOfUnreadableFile() throws {
        let directory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let file = directory.appendingPathComponent("noread.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }

        let guardUnderTest = PathGuard(root: directory)
        let result = guardUnderTest.checkPermission(file, for: .read)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("readable"))
        }
    }

    @Test func rejectsWriteOfReadonlyFile() throws {
        let directory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let file = directory.appendingPathComponent("readonly.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }

        let guardUnderTest = PathGuard(root: directory)
        let result = guardUnderTest.checkPermission(file, for: .write)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("read-only"))
        }
    }

    @Test func rejectsWriteWithMissingParentDirectory() {
        let directory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let guardUnderTest = PathGuard(root: directory)
        let target = directory.appendingPathComponent("missing-parent/file.txt")
        let result = guardUnderTest.checkPermission(target, for: .write)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("parent directory does not exist"))
        }
    }

    @Test func rejectsEditOfNonexistentFile() {
        let directory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let guardUnderTest = PathGuard(root: directory)
        let target = directory.appendingPathComponent("nope.txt")
        let result = guardUnderTest.checkPermission(target, for: .edit)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("non-existent"))
        }
    }

    @Test func rejectsEditOfReadonlyFile() throws {
        let directory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let file = directory.appendingPathComponent("readonly.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }

        let guardUnderTest = PathGuard(root: directory)
        let result = guardUnderTest.checkPermission(file, for: .edit)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("read-only"))
        }
    }

    // MARK: Delete permission checks

    @Test func acceptsDeleteOfExistingRegularFileInWritableDirectory() throws {
        let directory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let file = directory.appendingPathComponent("victim.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)

        let guardUnderTest = PathGuard(root: directory)
        let resolved = try guardUnderTest.validate(file.path, for: .delete).get()
        #expect(resolved.lastPathComponent == "victim.txt")
    }

    @Test func rejectsDeleteOfNonexistentFile() {
        let directory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let guardUnderTest = PathGuard(root: directory)
        let target = directory.appendingPathComponent("nope.txt")
        let result = guardUnderTest.checkPermission(target, for: .delete)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("non-existent"))
        }
    }

    @Test func rejectsDeleteOfDirectory() {
        let directory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let guardUnderTest = PathGuard(root: directory)
        let result = guardUnderTest.checkPermission(directory, for: .delete)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("regular file"))
        }
    }

    @Test func rejectsDeleteWhenParentDirectoryIsNotWritable() throws {
        let directory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let file = directory.appendingPathComponent("locked.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)
        // POSIX deletion permission lives on the parent directory. Thus the
        // removal of its write bits must reject the delete although the
        // file itself is writable. The teardown restores the write bits,
        // thus the operating system can reclaim the directory.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

        let guardUnderTest = PathGuard(root: directory)
        let result = guardUnderTest.checkPermission(file, for: .delete)
        #expect(throws: PathViolation.self) { try result.get() }
        if case .failure(let violation) = result {
            #expect(violation.message.lowercased().contains("parent directory is not writable"))
        }
    }

    @Test(arguments: [FileOperation.read, .write, .edit])
    func acceptsWritableRegularFileForEveryOperation(operation: FileOperation) throws {
        let directory = TestSupport.makeTemporaryDirectory(named: "PathGuardTests")
        let file = directory.appendingPathComponent("ok.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)

        let guardUnderTest = PathGuard(root: directory)
        let resolved = try guardUnderTest.validate(file.path, for: operation).get()
        #expect(resolved.lastPathComponent == "ok.txt")
    }
}
