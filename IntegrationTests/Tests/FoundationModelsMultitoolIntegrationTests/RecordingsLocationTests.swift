import Foundation
import Testing

/// Ungated coverage for where `LiveRouterFixture` puts the Router recordings
/// it makes.
///
/// CI run `32294279325` hung for 30 minutes with zero tool calls and an empty
/// reply, and left no forensic record: the recordings root was a fresh
/// directory under `FileManager.default.temporaryDirectory`, which no CI step
/// uploads and which does not survive the runner. The one artifact that shows
/// the literal dispatched prompt and the generation activity of a hung turn
/// was gone before anyone could read it (card `^hht0009`).
///
/// The structural fix is a recordings root INSIDE the workspace —
/// `IntegrationTests/.build/recordings` — so a CI artifact-upload step can
/// keep it, and a local investigator can find it without racing the
/// platform's temporary-directory sweep. These tests hold that location.
///
/// They carry no gate on purpose. They need no model, no download and no
/// GPU: the root is a pure path computation off this package's own layout,
/// and the directory creation touches only the local `.build` tree.
@Suite("Recordings location")
struct RecordingsLocationTests {
    @Test("the recordings root stands under the package's own .build directory")
    func recordingsRootStandsUnderThePackageBuildDirectory() {
        let root = LiveRouterFixture.recordingsRoot

        // `<package>/.build/recordings` — the two trailing components carry
        // the whole contract: `.build` keeps the tree out of git (the root
        // `.gitignore` ignores `.build/`), and `recordings` is the one name a
        // CI upload glob has to know.
        #expect(Array(root.pathComponents.suffix(2)) == [".build", "recordings"])

        // Two levels above the root is the IntegrationTests package itself —
        // proven by its manifest, so a rearrangement of the test tree that
        // silently derived some other directory fails here.
        let manifest = root
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Package.swift")
        #expect(FileManager.default.fileExists(atPath: manifest.path))
    }

    @Test("the recordings root does not stand under the ephemeral temporary directory")
    func recordingsRootIsNotTemporary() {
        let temporary = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath().path
        let root = LiveRouterFixture.recordingsRoot
            .resolvingSymlinksInPath().path

        // The temporary directory is exactly the location the fix moves away
        // from: nothing there survives for a CI upload step to find.
        #expect(!root.hasPrefix(temporary))
    }

    @Test("a fixture recordings directory is created directly under the recordings root")
    func recordingsDirectoryIsCreatedUnderTheRoot() throws {
        let dir = LiveRouterFixture.makeRecordingsDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(
            dir.deletingLastPathComponent().resolvingSymlinksInPath()
                == LiveRouterFixture.recordingsRoot.resolvingSymlinksInPath()
        )
    }
}
