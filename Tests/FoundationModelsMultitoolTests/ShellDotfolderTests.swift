import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for `ShellDotfolder`, which resolves the file of each layer of the
/// `shell` dotfolder.
///
/// The user layer takes an injected environment, thus each test states the
/// value of `XDG_CONFIG_HOME` it examines and depends on no real state of the
/// process. The project layer walks up from the working directory to the
/// nearest git root, which under `swift test` is the root of this package.
@Suite("ShellDotfolderTests")
struct ShellDotfolderTests {

    /// The name of the environment variable the XDG specification states for
    /// the user configuration root.
    private static let configHomeVariable = "XDG_CONFIG_HOME"

    /// An absolute `XDG_CONFIG_HOME` value, which the specification accepts.
    ///
    /// No test writes to this path. Each test compares the resolved URL only.
    private static let absoluteConfigHome = "/tmp/shell-dotfolder-tests"

    /// A relative `XDG_CONFIG_HOME` value, which the specification refuses.
    private static let relativeConfigHome = "relative/config"

    /// The folder of the user layer inside the home directory, which is the
    /// fallback root of the XDG specification.
    private static let homeConfigFolder = ".config"

    /// The permissions a lock sidecar takes when it is not already there.
    private static let expectedLockFileMode: mode_t = 0o644

    /// The user-layer URL of `fileName` when no valid `XDG_CONFIG_HOME` stands
    /// in the environment.
    ///
    /// - Parameter fileName: The file to locate inside the user layer root.
    /// - Returns: `~/.config/shell/<fileName>`.
    private func homeFallbackURL(fileName: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(Self.homeConfigFolder, isDirectory: true)
            .appendingPathComponent(ShellDotfolder.name, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    @Test("An absolute XDG_CONFIG_HOME gives the root of the user layer")
    func absoluteConfigHomeGivesTheUserLayerRoot() throws {
        let url = try #require(
            ShellDotfolder.userURL(
                fileName: ShellDotfolder.configFileName,
                environment: [Self.configHomeVariable: Self.absoluteConfigHome]))

        let expected = URL(fileURLWithPath: Self.absoluteConfigHome, isDirectory: true)
            .appendingPathComponent(ShellDotfolder.name, isDirectory: true)
            .appendingPathComponent(ShellDotfolder.configFileName)
        #expect(url.path == expected.path)
    }

    @Test("A relative XDG_CONFIG_HOME falls back to the home directory")
    func relativeConfigHomeFallsBackToTheHomeDirectory() throws {
        // The XDG specification states an absolute path. A relative value is
        // thus invalid, and the default takes its place.
        let url = try #require(
            ShellDotfolder.userURL(
                fileName: ShellDotfolder.decisionsFileName,
                environment: [Self.configHomeVariable: Self.relativeConfigHome]))

        #expect(url.path == homeFallbackURL(fileName: ShellDotfolder.decisionsFileName).path)
    }

    @Test("An environment with no XDG_CONFIG_HOME falls back to the home directory")
    func absentConfigHomeFallsBackToTheHomeDirectory() throws {
        let url = try #require(
            ShellDotfolder.userURL(fileName: ShellDotfolder.configFileName, environment: [:]))

        #expect(url.path == homeFallbackURL(fileName: ShellDotfolder.configFileName).path)
    }

    @Test("The project layer stands in the .shell folder of the git root")
    func projectLayerStandsInTheGitRootDotfolder() throws {
        // `swift test` runs with the package root as the working directory, and
        // that root is inside a git working tree. Thus the walk finds a root.
        let url = try #require(ShellDotfolder.projectURL(fileName: ShellDotfolder.decisionsFileName))

        #expect(url.lastPathComponent == ShellDotfolder.decisionsFileName)

        let layerRoot = url.deletingLastPathComponent()
        #expect(layerRoot.lastPathComponent == ".\(ShellDotfolder.name)")

        let gitRoot = layerRoot.deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: gitRoot.appendingPathComponent(".git").path))
    }

    @Test("Each layer file has its lock sidecar beside it")
    func lockSidecarStandsBesideTheFileItGuards() {
        // The two files of a layer travel together, and each one has a sidecar
        // that a writer locks while it rewrites the file.
        #expect(ShellDotfolder.configFileName + ShellDotfolder.lockFileSuffix == "config.yaml.lock")
        #expect(
            ShellDotfolder.decisionsFileName + ShellDotfolder.lockFileSuffix
                == "decisions.yaml.lock")
        #expect(ShellDotfolder.lockFileMode == Self.expectedLockFileMode)
    }
}
