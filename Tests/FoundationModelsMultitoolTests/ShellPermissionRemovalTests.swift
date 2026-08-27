import Foundation
import Testing

/// Guards the decision of 2026-08-24: the shell capability has no permission
/// question and no store of remembered answers, and the seatbelt sandbox is
/// the only gate on a command.
///
/// The design that this decision replaced was deleted from the source, from
/// the tests and from `eventplan.md`. A deletion alone does not hold: a later
/// planning pass reads a name that stayed behind and writes the cards again.
/// So each case here reads a tree, or one file, and fails when a banned name
/// comes back. Each failure names the file and the line, thus the reader goes
/// straight to it.
///
/// `config.yaml` is not banned. `ShellDotfolder.configFileName` was kept on
/// purpose, with the reason written in its doc comment: the write confinement
/// of the sandbox is configuration the host supplies, and that file is where
/// it is meant to come from.
@Suite("ShellPermissionRemoval")
struct ShellPermissionRemovalTests {
    /// The names of the deleted permission design.
    ///
    /// `ShellPolicy` and `ShellPolicyError` were the policy, `decisions.yaml`
    /// held the remembered "always" answers, and `ShellDecisionStore` read and
    /// wrote that file.
    static let bannedNames = [
        "ShellPolicy",
        "ShellDecisionStore",
        "ShellPolicyError",
        "decisions.yaml",
    ]

    /// This guard file itself.
    ///
    /// The walk of `Tests/` passes over it, because the file must spell each
    /// banned name to search for it.
    static let guardFileURL = URL(fileURLWithPath: #filePath).standardizedFileURL

    @Test("no source file names the deleted permission design")
    func sourcesNameNoBannedName() throws {
        let sightings = try Self.sightings(inRelativeDirectory: "Sources")
        #expect(sightings.isEmpty, "\(Self.report(sightings))")
    }

    @Test("no test file names the deleted permission design")
    func testsNameNoBannedName() throws {
        let sightings = try Self.sightings(inRelativeDirectory: "Tests")
        #expect(sightings.isEmpty, "\(Self.report(sightings))")
    }

    @Test("eventplan.md names no part of the deleted permission design")
    func eventplanNamesNoBannedName() throws {
        let sightings = try Self.sightings(inRelativeFile: "eventplan.md")
        #expect(sightings.isEmpty, "\(Self.report(sightings))")
    }

    @Test("Package.swift names no part of the deleted permission design")
    func packageManifestNamesNoBannedName() throws {
        let sightings = try Self.sightings(inRelativeFile: "Package.swift")
        #expect(sightings.isEmpty, "\(Self.report(sightings))")
    }

    /// Names each banned name that the Swift files under one directory hold.
    ///
    /// The scan is `RepositoryFile.sightings(of:inRelativeDirectory:excluding:)`,
    /// with this guard file passed over.
    ///
    /// - Parameter directoryPath: the directory's path from the repository
    ///   root, for example `"Sources"`.
    /// - Returns: one `path:line: name` entry for each sighting.
    /// - Throws: an error when the directory cannot be walked, or when a file
    ///   under it cannot be read.
    private static func sightings(inRelativeDirectory directoryPath: String) throws -> [String] {
        try RepositoryFile.sightings(
            of: bannedNames, inRelativeDirectory: directoryPath, excluding: [guardFileURL])
    }

    /// Names each banned name that one file holds.
    ///
    /// - Parameter filePath: the file's path from the repository root.
    /// - Returns: one `path:line: name` entry for each sighting.
    /// - Throws: an error when the file cannot be read.
    private static func sightings(inRelativeFile filePath: String) throws -> [String] {
        try RepositoryFile.sightings(of: bannedNames, inRelativeFile: filePath)
    }

    /// The failure message that names each sighting.
    ///
    /// - Parameter sightings: the `path:line: name` entries a case collected.
    /// - Returns: the text a failing case shows.
    private static func report(_ sightings: [String]) -> String {
        """
        The deleted shell permission design is named again. The seatbelt \
        sandbox is the only gate on a command (decision of 2026-08-24), thus \
        each name below must go:
        \(sightings.joined(separator: "\n"))
        """
    }
}
