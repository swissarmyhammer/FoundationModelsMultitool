// `GitNoProgramProbe` — runs each git verb, the files glob and grep, and a
// snapshot list, and writes one line for each check (task `^b7jrvhc`).
//
// Test support — see `gitNoProgramProbeExecutableName` in `Package.swift`.
// `GitNoProgramTests` starts this binary with an empty `PATH` and a bad
// `DEVELOPER_DIR`, thus no `git` program can run. Each check calls the library
// directly, with no model. The exit status is 0 only when each check passes,
// else 1.

import Foundation
import FoundationModelsHooks

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The result of one check: its name, and why it failed.
struct ProbeCheck {

    /// The name of the check, for its output line.
    let name: String

    /// Why the check failed, or `nil` when it passed.
    let failure: String?

    /// The output line of the check.
    var line: String {
        guard let failure else { return "PASS \(name)" }
        return "FAIL \(name): \(failure)"
    }
}

/// The repository that the checks read, and the files it holds.
///
/// The history has two commits and a branch. After the commits, the work
/// folder holds a staged change, an untracked file, and an ignored file in an
/// ignored folder.
enum ProbeRepository {

    /// The Swift file that each commit changes, and that the staged change
    /// changes.
    static let swiftFile = "a.swift"

    /// The tracked text file that the second commit adds. It holds
    /// ``needle``.
    static let trackedTextFile = "b.txt"

    /// The untracked text file. It holds ``needle``.
    static let untrackedTextFile = "untracked.txt"

    /// The ignored text file in the ignored folder. It holds ``needle``.
    static let ignoredTextFile = "build/ignored.txt"

    /// The branch that the history makes at the second commit.
    static let featureBranch = "feature"

    /// The text that the grep check finds.
    static let needle = "needle"

    /// The ignore rules of the repository: the `build` folder.
    private static let ignoreRules = "build/\n"

    /// Makes the repository.
    ///
    /// - Returns: The repository. Its folder is removed when it is released.
    /// - Throws: What a write, a commit, a branch, or a stage throws.
    static func make() throws -> TemporaryGitRepository {
        let repository = try TemporaryGitRepository()
        try repository.write(ignoreRules, to: ".gitignore")
        try repository.write("struct A {}\n", to: swiftFile)
        try repository.commit(message: "first")
        try repository.write("struct A {\n    let value = 1\n}\n", to: swiftFile)
        try repository.write("\(needle)\n", to: trackedTextFile)
        try repository.commit(message: "second")
        try repository.createBranch(named: featureBranch)
        try repository.write("struct A {\n    let value = 2\n}\n", to: swiftFile)
        try repository.stage(swiftFile)
        try repository.write("\(needle)\n", to: untrackedTextFile)
        try repository.write("\(needle)\n", to: ignoredTextFile)
        return repository
    }
}

/// The checks of the probe, and the run that writes their lines.
enum NoProgramProbe {

    /// The exit status when each check passes.
    static let passStatus: Int32 = 0

    /// The exit status when a check fails, or when the setup fails.
    static let failStatus: Int32 = 1

    /// The text files that a git-aware walk gives: the tracked file and the
    /// untracked file, and not the ignored file.
    private static let visibleTextFiles: Set = [
        ProbeRepository.trackedTextFile, ProbeRepository.untrackedTextFile,
    ]

    /// The glob pattern that matches each text file at each depth.
    private static let textFilePattern = "**/*.txt"

    /// The grep output mode that gives the matching files only.
    private static let filesWithMatchesMode = "filesWithMatches"

    /// The session key of the snapshot check.
    private static let snapshotSessionKey = "git-no-program-probe"

    /// The session ID of the snapshot check, which the store reads as the
    /// owner.
    private static let snapshotOwner = "session-git-no-program-probe"

    /// The label of the one checkpoint of the snapshot check.
    private static let snapshotLabel = "probe"

    /// The file that the snapshot check writes after the open, thus the
    /// snapshot records a change. The checks of the files capability run
    /// before it, thus they do not see it.
    private static let snapshotFile = "snapshot.txt"

    /// The prefix of the name of the temporary folder of the snapshot check.
    /// Thus a leaked folder is traceable to this probe.
    private static let temporaryFolderPrefix = "GitNoProgramProbe"

    /// Runs each check, writes one line for each, and gives the exit status.
    ///
    /// - Returns: ``passStatus`` when each check passes, else ``failStatus``.
    static func run() async -> Int32 {
        let repository: TemporaryGitRepository
        do {
            repository = try ProbeRepository.make()
        } catch {
            write("FAIL setup: \(error)")
            return failStatus
        }
        let gitResults = await gitChecks(in: repository)
        let fileResults = await fileChecks(in: repository)
        let results = gitResults + fileResults + [await snapshotCheck(in: repository)]
        for result in results {
            write(result.line)
        }
        return results.allSatisfy { $0.failure == nil } ? passStatus : failStatus
    }

    /// Runs one check, and gives a failure when the body throws.
    ///
    /// - Parameters:
    ///   - name: The name of the check.
    ///   - body: The check. It gives why the check failed, or `nil` when it
    ///     passed.
    /// - Returns: The result of the check.
    private static func check(_ name: String, _ body: () async throws -> String?) async -> ProbeCheck {
        do {
            return ProbeCheck(name: name, failure: try await body())
        } catch {
            return ProbeCheck(name: name, failure: "threw \(error)")
        }
    }

    /// Gives the failure text of a correction.
    ///
    /// - Parameter correction: The correction of a result, or `nil`.
    /// - Returns: The failure text, or `nil` when there is no correction.
    private static func failure(ofCorrection correction: String?) -> String? {
        correction.map { "correction: \($0)" }
    }

    /// Runs each verb of `GitCapability(root:)` over the work folder of
    /// `repository`.
    ///
    /// - Parameter repository: The repository.
    /// - Returns: One result for each verb, in render order.
    private static func gitChecks(in repository: TemporaryGitRepository) async -> [ProbeCheck] {
        let context = GitCapability(root: repository.workDirectory).context
        let swiftFile = ProbeRepository.swiftFile
        return [
            await check("git.blame") {
                failure(
                    ofCorrection: try await Blame(context: context).call(
                        arguments: BlameArguments(path: swiftFile)
                    ).correction)
            },
            await check("git.show") {
                let arguments = ShowArguments(path: swiftFile, ref: ProbeRepository.featureBranch)
                return failure(
                    ofCorrection: try await Show(context: context).call(arguments: arguments).correction)
            },
            await check("git.log") {
                failure(
                    ofCorrection: try await Log(context: context).call(arguments: LogArguments()).correction)
            },
            await check("git.commit") {
                failure(
                    ofCorrection: try await Commit(context: context).call(arguments: CommitArguments())
                        .correction)
            },
            await check("git.status") {
                failure(
                    ofCorrection: try await Status(context: context).call(arguments: StatusArguments())
                        .correction)
            },
            await check("git.branches") {
                failure(
                    ofCorrection: try await Branches(context: context).call(arguments: BranchesArguments())
                        .correction)
            },
            await check("git.changes") {
                failure(
                    ofCorrection: try await Changes(context: context).call(arguments: ChangesArguments())
                        .correction)
            },
            await check("git.diff") {
                failure(
                    ofCorrection: try await Diff(context: context).call(arguments: DiffArguments()).correction
                )
            },
        ]
    }

    /// Runs the files glob and grep over the work folder of `repository`.
    ///
    /// Each one must give the tracked and the untracked text file, and not
    /// the ignored file: that shows the git-aware listing ran, and not the
    /// plain walk that is the fallback when the listing fails.
    ///
    /// - Parameter repository: The repository.
    /// - Returns: The result of the glob, then of the grep.
    private static func fileChecks(in repository: TemporaryGitRepository) async -> [ProbeCheck] {
        let context = FileContext(root: repository.workDirectory)
        let root = repository.workDirectory.path
        return [
            await check("files.glob") {
                let arguments = GlobArguments(pattern: textFilePattern, path: root)
                let result = try await Glob(context: context).call(arguments: arguments)
                return failure(ofCorrection: result.correction) ?? failure(ofListing: result.files)
            },
            await check("files.grep") {
                let arguments = GrepArguments(
                    pattern: ProbeRepository.needle, outputMode: filesWithMatchesMode)
                let result = try await Grep(context: context).call(arguments: arguments)
                return failure(ofCorrection: result.correction) ?? failure(ofListing: result.files ?? [])
            },
        ]
    }

    /// Gives the failure text of a file listing that is not the git-aware
    /// listing of the text files.
    ///
    /// - Parameter files: The listed paths, relative to the root.
    /// - Returns: The failure text, or `nil` when the listing holds exactly
    ///   ``visibleTextFiles``.
    private static func failure(ofListing files: [String]) -> String? {
        guard Set(files) != visibleTextFiles else { return nil }
        return "expected \(visibleTextFiles.sorted()), got \(files.sorted())"
    }

    /// Takes one snapshot of the work folder of `repository`, and runs the
    /// snapshot list.
    ///
    /// - Parameter repository: The repository whose work folder the store
    ///   records.
    /// - Returns: The result of the list. It fails unless the list gives the
    ///   one checkpoint.
    private static func snapshotCheck(in repository: TemporaryGitRepository) async -> ProbeCheck {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(temporaryFolderPrefix)-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        return await check("snapshots.list") {
            let dataFolder = folder.appendingPathComponent("data", isDirectory: true)
            try FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
            let store = try await openStore(in: folder, over: repository)
            let session = HookSession(
                sessionID: snapshotOwner, sessionKey: snapshotSessionKey, parentSessionID: nil,
                workingDirectory: repository.workDirectory, dataDirectory: dataFolder)
            let result = try await HookSession.$current.withValue(session) {
                try await ListSnapshots(context: SnapshotsContext(store: store)).call(
                    arguments: ListSnapshotsArguments())
            }
            guard result.correction == nil else { return failure(ofCorrection: result.correction) }
            return result.checkpoints.count == 1
                ? nil : "expected 1 checkpoint, got \(result.checkpoints.count)"
        }
    }

    /// Makes a store in `folder`, opens the session key of the probe on it
    /// over the work folder of `repository`, writes ``snapshotFile``, and
    /// takes one snapshot. A snapshot of no change gives no checkpoint, thus
    /// the write comes first.
    ///
    /// - Parameters:
    ///   - folder: The temporary folder of the snapshot check.
    ///   - repository: The repository whose work folder the store records.
    /// - Returns: The store.
    /// - Throws: What the store throws.
    private static func openStore(in folder: URL, over repository: TemporaryGitRepository)
        async throws
        -> SnapshotStore
    {
        let store = SnapshotStore(directory: folder.appendingPathComponent("store", isDirectory: true))
        try await store.open(
            sessionKey: snapshotSessionKey, owner: snapshotOwner,
            workingDirectory: repository.workDirectory)
        try repository.write("\(snapshotLabel)\n", to: snapshotFile)
        _ = try await store.take(
            sessionKey: snapshotSessionKey, owner: snapshotOwner, trigger: .manual(label: snapshotLabel))
        return store
    }

    /// Writes `line` and a line end to the standard output.
    ///
    /// - Parameter line: The line.
    private static func write(_ line: String) {
        FileHandle.standardOutput.write(Data("\(line)\n".utf8))
    }
}

/// The entry point of the probe: runs each check, and exits with the status
/// of ``NoProgramProbe/run()``.
///
/// The entry is a `@main` type and not top-level code in `main.swift`, thus
/// a dead-code check sees the start of each call chain of the probe.
@main
enum GitNoProgramProbeMain {
    /// Runs the probe, and exits with its status.
    static func main() async {
        exit(await NoProgramProbe.run())
    }
}
