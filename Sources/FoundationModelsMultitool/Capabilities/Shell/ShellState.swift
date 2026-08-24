// `ShellState` — the history actor of one process, and its `.shell/log` store.
//
// The state is small and the execution is long. A caller touches `ShellState`
// only to record bookkeeping (start a command, register its process group,
// append the lines it captured, mark it done) and to answer history questions
// (`getLines`, `grep`). It never runs a child process and never waits for one.
// Thus a command that runs for a long time can never hold the actor. Each
// method is O(small), except the append to the log and the line-by-line scans
// of `getLines` and `grep`.
//
// eventplan.md § "Consolidation of the siblings" states the identity rule of a
// run: the `commandID` of a shell run is its `correlationID` is its
// `completionToken` — one string on two planes. Thus a command id here is the
// ULID string that `SessionMailbox.makeCompletionToken()` mints, and the
// caller gives it. This store mints no identifier of its own, and it holds no
// identifier of a kind of its own: the one string joins the run plane, which
// the Router mailbox owns, to the content plane, which this store owns.
//
// The history belongs to one session, thus to one process. Each stored log
// line opens with the `sessionID` of this process, and each reader keeps the
// lines with the prefix `{sessionID}:{commandID}:` only. Thus a question sees
// the lines of this session, also when several sessions share one `.shell`
// folder.

import Foundation

/// The execution status of a command the store tracks.
///
/// The raw values are the strings the response of a history operation carries,
/// thus a consumer of the wire format reads the same words as before.
enum CommandStatus: String, Sendable {
    /// The command runs now.
    case running
    /// The command ended by itself.
    case completed
    /// A cancel stopped the command. `cancel(completionToken)` is the one path
    /// that reaches this status, and for a shell run it sends `SIGKILL` to the
    /// process group.
    case killed
    /// The command went past its time limit (on the wire: "timed_out").
    case timedOut = "timed_out"
}

/// The record of one command execution.
struct CommandRecord: Sendable {
    /// The completion token this command runs under.
    ///
    /// It is the `correlationID` of each event the run posts, and it is the
    /// token that `cancel` and `status` take. The caller mints it with
    /// `SessionMailbox.makeCompletionToken()` and gives it to `startCommand`.
    let id: String
    /// The command line as the caller gave it.
    let command: String
    /// The status now.
    var status: CommandStatus
    /// The exit code, when it is known (`nil` while the command runs, `-1`
    /// after a time limit).
    var exitCode: Int?
    /// The number of log lines this command holds (stdout, then stderr).
    var lineCount: Int
    /// The start instant on the monotonic clock, thus a duration pays no
    /// attention to a change of the wall clock.
    let startedAt: ContinuousClock.Instant
    /// The start time on the wall clock, for display.
    let startedAtWall: Date
    /// The end instant on the monotonic clock, set when the command ends.
    var completedAt: ContinuousClock.Instant?
    /// The end time on the wall clock, set when the command ends.
    var completedAtWall: Date?

    /// Milliseconds in one second — the multiplier `durationMs` puts on the
    /// seconds component of `duration`.
    private static let millisecondsPerSecond = 1000

    /// Attoseconds in one millisecond (`1e15`) — the divisor `durationMs` puts
    /// on the attoseconds component of `duration`. `Duration.components` gives
    /// seconds plus attoseconds.
    private static let attosecondsPerMillisecond = 1_000_000_000_000_000

    /// The time from the start to the end, or from the start to now while the
    /// command still runs.
    var duration: Duration {
        startedAt.duration(to: completedAt ?? ContinuousClock().now)
    }

    /// `duration`, cut to whole milliseconds.
    ///
    /// This is the one source of truth for the elapsed time of a run: the
    /// response of the execute operation and the `.completed` event of the
    /// runner each read it, thus the two never disagree about a rounding.
    var durationMs: Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * Self.millisecondsPerSecond
            + Int(attoseconds / Int64(Self.attosecondsPerMillisecond))
    }
}

/// One line that `getLines` takes from the log.
struct LogLine: Equatable, Sendable {
    /// The line number inside the command, counted from 1.
    let lineNumber: Int
    /// The text of the line, with no storage prefix and no line separator.
    let text: String
}

/// One matching line that `grep` gives back.
struct GrepResult: Equatable, Sendable {
    /// The completion token of the command the line belongs to.
    let commandID: String
    /// The line number inside the command, counted from 1.
    let lineNumber: Int
    /// The text of the matching line.
    let text: String
}

/// The result of a `grep`: the matches, which the limit caps, plus the full
/// count of the matches.
struct GrepResults: Sendable {
    /// The matches, capped at the limit the caller gave.
    let results: [GrepResult]
    /// The number of matches the scan found, which the limit does not change.
    let total: Int
}

/// The errors `ShellState` gives back, each one recoverable.
///
/// `Sendable`, because `ShellState` is an actor: an error it throws crosses
/// the actor boundary. Each associated value is a value type, thus the
/// `invalidRegex` case holds the failure as a message `String` that it takes at
/// the moment of the throw, and it holds no non-`Sendable` `any Error`.
enum ShellStateError: Error, CustomStringConvertible, Sendable {
    /// `appendLines` or `getLines` named a completion token that no command
    /// ever started under.
    case unknownCommand(String)
    /// `grep` took a pattern that does not compile as a regular expression. It
    /// carries the message of the failure, taken at the moment of the throw.
    case invalidRegex(pattern: String, underlyingMessage: String)
    /// The log file did not create inside the store directory.
    case logCreationFailed(URL)

    var description: String {
        switch self {
        case .unknownCommand(let id):
            return "Unknown command ID \(id)"
        case .invalidRegex(let pattern, let underlyingMessage):
            return "Invalid regex pattern \"\(pattern)\": \(underlyingMessage)"
        case .logCreationFailed(let url):
            return "Failed to create log file at \(url.path)"
        }
    }
}

/// The history and output store of the virtual shell — one instance for each
/// process.
actor ShellState {
    /// The session identifier of this process, which no other process shares.
    nonisolated let sessionID: String
    /// The append-only `.shell/log` file this session reads and writes.
    nonisolated let logURL: URL

    private var commands: [CommandRecord] = []
    /// The commands that run now: the completion token of each one, and the
    /// pid of the leader of its process group.
    private var processes: [String: pid_t] = [:]

    /// Continuations of a `pidToCancel(commandID:)` call that arrived before
    /// this store had a pid to give it, keyed by completion token.
    ///
    /// A `wait: false` call can detach before its child is even spawned —
    /// the block window can be zero, see `Execute.detachmentClocks(from:)` —
    /// so a cancel can reach `pidToCancel` before `registerProcess` ever
    /// runs. Rather than answer `nil` and leave the process to run
    /// unwatched, `pidToCancel` SUSPENDS, and this dictionary is where it
    /// parks the continuation that resumes it. `registerProcess(commandID:pid:)`
    /// resumes it with the pid the moment the child registers, and
    /// `completeCommand(commandID:status:exitCode:)` resumes it with `nil`
    /// on every exit path that ends the command without ever registering
    /// one — a spawn that throws before it, above all — so a cancel this
    /// store can never satisfy is never left waiting forever. Both
    /// resumptions are one hop of this actor, with no `await` between the
    /// check that finds no pid and the continuation that waits for one, so
    /// no third call can land in the gap and leave a continuation orphaned.
    ///
    /// A list, not a single continuation, because more than one caller can
    /// cancel the same token before it resolves; each one gets the same
    /// answer.
    private var pidWaiters: [String: [CheckedContinuation<pid_t?, Never>]] = [:]

    /// Resumes every continuation `pidWaiters` holds for `commandID` with
    /// `result`, and forgets them.
    ///
    /// The one place either resumption path — `registerProcess` with a pid,
    /// `completeCommand` with `nil` — actually settles a waiter, so the two
    /// callers cannot drift into resuming a continuation twice or leaving one
    /// unresumed.
    ///
    /// - Parameters:
    ///   - commandID: The completion token whose waiters to resume.
    ///   - result: The pid to resume them with, or `nil` when none will ever
    ///     come.
    private func resolvePidWaiters(commandID: String, with result: pid_t?) {
        guard let waiters = pidWaiters.removeValue(forKey: commandID) else { return }
        for continuation in waiters {
            continuation.resume(returning: result)
        }
    }

    /// The one field separator of a stored log line, whose framing is
    /// `{sessionID}:{commandID}:{lineNumber}:{text}`.
    ///
    /// One source of truth for the join on the write and for the split on the
    /// read, thus the wire format cannot drift between the two. A `Character`,
    /// because that is the type the scan sites (`firstIndex(of:)`,
    /// `split(separator:)`) take, and it also joins cleanly into the strings
    /// the writer builds.
    ///
    /// A ULID holds no separator character, thus a completion token in field 2
    /// keeps the format readable field by field.
    private static let fieldSeparator: Character = ":"

    /// The number of fields a stored log line holds after the session id: the
    /// command id, the line number, and the text.
    private static let fieldsAfterSessionID = 3

    /// The `\n` byte the stored log splits on.
    ///
    /// `OutputBuffer` reads the same byte: it cuts an over-cap chunk at a line
    /// boundary, and it finds the lines of a chunk that are complete. Thus the
    /// byte that ends a line is stated one time, as `splitLogLines` is written
    /// one time.
    static let newlineByte = UInt8(ascii: "\n")

    // MARK: - Initialization

    /// Makes a `ShellState` that prefers `preferredDirectory` for its `.shell`
    /// store, and that falls back to a unique temporary directory when that
    /// value is `nil` or does not prepare (absent, read-only, or otherwise not
    /// writable).
    ///
    /// The read-only fallback is what a launch from the graphical shell needs:
    /// an application that a user opens from the Finder runs with `/` as its
    /// working directory, which is a read-only system volume, thus `<cwd>/.shell`
    /// does not create there. The fallback keeps the construction from failing.
    ///
    /// - Parameter preferredDirectory: The store directory to try first, or
    ///   `nil` to go directly to the temporary fallback.
    /// - Throws: When neither the preferred directory nor the fallback prepares.
    init(preferredDirectory: URL?) throws {
        let session = UUID().uuidString
        let directory = try Self.resolveDirectory(preferred: preferredDirectory, sessionID: session)
        self.sessionID = session
        self.logURL = directory.appendingPathComponent(Self.logFilename)
    }

    /// Makes a `ShellState` rooted at `<cwd>/.shell`, with the temporary
    /// fallback.
    ///
    /// - Throws: When neither `<cwd>/.shell` nor the fallback prepares.
    init() throws {
        let workingDirectory = ShellDotfolder.currentDirectory()
        try self.init(preferredDirectory: workingDirectory.appendingPathComponent(".shell"))
    }

    // MARK: - The life of a command

    /// Starts to track a command under the completion token of its run.
    ///
    /// The caller mints the token with `SessionMailbox.makeCompletionToken()`,
    /// and that same token is the `correlationID` of each event the run posts.
    /// Thus the model reads one identifier and reaches both planes with it: the
    /// run plane through `status`, `wait` and `cancel`, and the content plane
    /// through `getLines` and `grepHistory`.
    ///
    /// - Parameters:
    ///   - command: The command line, as the caller gave it.
    ///   - commandID: The completion token of the run.
    func startCommand(_ command: String, commandID: String) {
        commands.append(
            CommandRecord(
                id: commandID,
                command: command,
                status: .running,
                exitCode: nil,
                lineCount: 0,
                startedAt: ContinuousClock().now,
                startedAtWall: Date(),
                completedAt: nil,
                completedAtWall: nil
            ))
    }

    /// Registers the pid of the process-group leader of a command that runs,
    /// and resumes any `pidToCancel(commandID:)` call already waiting on it.
    ///
    /// - Parameters:
    ///   - commandID: The completion token of the run.
    ///   - pid: The pid of the leader of the process group of the child.
    func registerProcess(commandID: String, pid: pid_t) {
        processes[commandID] = pid
        resolvePidWaiters(commandID: commandID, with: pid)
    }

    /// The pid of the process-group leader of a command that runs, or `nil`
    /// when the store holds no process for that token.
    ///
    /// A plain, non-suspending read: it never waits, thus it is safe for a
    /// caller that only wants to observe now. The canceler of a run takes
    /// `pidToCancel(commandID:)` instead, because a cancel must also close
    /// the race against a spawn that has not registered a pid yet — see the
    /// doc comment of `pidWaiters`. A command that ended holds no entry, thus
    /// a read here after that never reports a pid the store no longer owns.
    ///
    /// - Parameter commandID: The completion token of the run.
    /// - Returns: The pid of the leader of the process group, or `nil`.
    func runningProcess(commandID: String) -> pid_t? {
        processes[commandID]
    }

    /// The pid to send a cancel's `killpg` to, waiting for it when no process
    /// has registered yet.
    ///
    /// This SUSPENDS rather than answering `nil` on a miss, because a `nil`
    /// here would leave the caller — the canceler — with nothing to kill, and
    /// the process group would run unwatched once it did spawn. The wait
    /// always ends: `registerProcess(commandID:pid:)` resumes it with the pid
    /// the moment the child registers, and `completeCommand(commandID:status:exitCode:)`
    /// resumes it with `nil` on every exit path that ends the command with no
    /// pid ever registered — a spawn that throws, above all. See the doc
    /// comment of `pidWaiters` for why the check and the wait are one
    /// uninterrupted hop of this actor.
    ///
    /// - Parameter commandID: The completion token of the run to cancel.
    /// - Returns: The pid to kill, or `nil` when the command ended (or never
    ///   started) with no process to kill.
    func pidToCancel(commandID: String) async -> pid_t? {
        if let pid = processes[commandID] { return pid }
        return await withCheckedContinuation { continuation in
            pidWaiters[commandID, default: []].append(continuation)
        }
    }

    /// The index of the command with `commandID`, or `nil` when no command
    /// started under that token.
    ///
    /// This is the one home of the match of a token against a record. Each
    /// other method reaches a record through it: `commandIndex` throws on the
    /// `nil`, the two methods that finalize a command read the `nil` as a
    /// no-operation, and `record` maps the index to the record. Thus one
    /// predicate answers each lookup, and the four sites cannot drift apart.
    ///
    /// - Parameter commandID: The completion token of the run.
    /// - Returns: The index of the record inside `commands`, or `nil`.
    private func indexOfCommand(commandID: String) -> Int? {
        commands.firstIndex { $0.id == commandID }
    }

    /// The index of the command with `commandID`, which throws
    /// `unknownCommand` when no command started under that token.
    ///
    /// The one lookup of each method that must refuse an unknown token —
    /// `appendLines` and `getLines`.
    ///
    /// - Parameter commandID: The completion token of the run.
    /// - Returns: The index of the record inside `commands`.
    /// - Throws: `ShellStateError.unknownCommand` for a token no command
    ///   started under.
    private func commandIndex(commandID: String) throws -> Int {
        guard let index = indexOfCommand(commandID: commandID) else {
            throw ShellStateError.unknownCommand(commandID)
        }
        return index
    }

    /// Appends the output a command gave to the log. Inside one call, each
    /// `stdout` line is written before the `stderr` lines of that same call.
    ///
    /// The runner calls this as the chunks arrive, usually with one stream
    /// filled. Thus the output of a command that still runs becomes visible to
    /// `getLines` and `grep` before that command ends, and the order across
    /// calls is the order of arrival — not "each stdout line, then each stderr
    /// line" for the command as a whole.
    ///
    /// Each call shares one line counter that continues across the calls and
    /// counts from 1 inside the command. Each line is stored as
    /// `{sessionID}:{commandID}:{lineNumber}:{text}\n`.
    ///
    /// - Parameters:
    ///   - commandID: The completion token of the run.
    ///   - stdout: The standard-output lines of this chunk.
    ///   - stderr: The standard-error lines of this chunk.
    /// - Throws: `ShellStateError.unknownCommand` for a token no command
    ///   started under, or a file error when the append does not write.
    func appendLines(commandID: String, stdout: [String] = [], stderr: [String] = []) throws {
        let index = try commandIndex(commandID: commandID)

        var buffer = Data()
        let separator = String(Self.fieldSeparator)
        for line in stdout + stderr {
            commands[index].lineCount += 1
            let fields = [sessionID, commandID, String(commands[index].lineCount), line]
            buffer.append(Data("\(fields.joined(separator: separator))\n".utf8))
        }
        guard !buffer.isEmpty else { return }

        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: buffer)
    }

    /// Marks a command finished with the status and the exit code it gives, and
    /// drops the entry of its process group.
    ///
    /// A no-operation for a token no command started under.
    ///
    /// - Parameters:
    ///   - commandID: The completion token of the run.
    ///   - status: The status the command ends in.
    ///   - exitCode: The exit code, or `nil` when the command has none.
    func completeCommand(
        commandID: String, status: CommandStatus = .completed, exitCode: Int? = nil
    ) {
        processes[commandID] = nil
        // A `pidToCancel(commandID:)` call already suspended for this token —
        // a cancel that outraced this same spawn, most often — has nobody
        // left to answer it once this command ends, on this or any other
        // exit path, without ever registering a pid. Resume it with `nil`
        // here, on the same exit path that already drops the pid, so that
        // waiter is never left suspended forever.
        resolvePidWaiters(commandID: commandID, with: nil)
        guard let index = indexOfCommand(commandID: commandID) else { return }
        commands[index].status = status
        commands[index].exitCode = exitCode
        commands[index].completedAt = ContinuousClock().now
        commands[index].completedAtWall = Date()
    }

    /// Finalizes a command **only while it still runs**, in one hop of the
    /// actor.
    ///
    /// This is the atomic transition the runner uses to record a normal end or
    /// an end at the time limit. The check and the write happen with no
    /// suspension between them, thus a cancel that runs at the same time and
    /// already made the record `.killed` is never written over. A no-operation
    /// for an unknown token and for a command that already ended.
    ///
    /// - Parameters:
    ///   - commandID: The completion token of the run.
    ///   - status: The status the command ends in.
    ///   - exitCode: The exit code, or `nil` when the command has none.
    func completeIfRunning(commandID: String, status: CommandStatus, exitCode: Int?) {
        guard let index = indexOfCommand(commandID: commandID),
            commands[index].status == .running
        else { return }
        completeCommand(commandID: commandID, status: status, exitCode: exitCode)
    }

    /// Each command record, in the order the commands started.
    func listCommands() -> [CommandRecord] {
        commands
    }

    /// The record of one command, or `nil` when no command started under
    /// `commandID`.
    ///
    /// The one lookup by token that each caller with a need for one
    /// authoritative record shares — the response of the execute operation, and
    /// the detached events the runner posts — instead of each one scanning
    /// `listCommands()` with a search of its own.
    ///
    /// - Parameter commandID: The completion token of the run.
    /// - Returns: The record, or `nil`.
    func record(commandID: String) -> CommandRecord? {
        indexOfCommand(commandID: commandID).map { commands[$0] }
    }

    // MARK: - History questions

    /// Reads the lines of a command from the log, inside `start...end` when the
    /// caller bounds it (the defaults are `1` and no upper bound).
    ///
    /// The scan reads the lines of this session for `commandID` only.
    ///
    /// - Parameters:
    ///   - commandID: The completion token of the run.
    ///   - start: The first line number to give back, or `nil` for 1.
    ///   - end: The last line number to give back, or `nil` for no bound.
    /// - Returns: The lines inside the range, in order.
    /// - Throws: `ShellStateError.unknownCommand` for a token no command
    ///   started under, or a file error when the log does not read.
    func getLines(commandID: String, start: Int? = nil, end: Int? = nil) throws -> [LogLine] {
        _ = try commandIndex(commandID: commandID)

        let lower = start ?? 1
        let upper = end ?? Int.max
        let prefix = "\(sessionID)\(Self.fieldSeparator)\(commandID)\(Self.fieldSeparator)"

        var results: [LogLine] = []
        for line in try readLogLines() {
            guard line.hasPrefix(prefix) else { continue }
            let rest = line.dropFirst(prefix.count)
            guard let separator = rest.firstIndex(of: Self.fieldSeparator),
                let number = Int(rest[..<separator]),
                number >= lower, number <= upper
            else { continue }
            let text = String(rest[rest.index(after: separator)...])
            results.append(LogLine(lineNumber: number, text: text))
        }
        return results
    }

    /// The cap on the results of `grep` when the caller states no limit.
    private static let defaultGrepResultLimit = 10

    /// Searches the log lines of this session with a regular expression, inside
    /// one command when the caller names it.
    ///
    /// `literal: true` escapes the pattern first, thus the pattern matches word
    /// for word. The match is line by line, thus the binary output of one
    /// command cannot break the search of another. The results stop at `limit`
    /// (the default is `defaultGrepResultLimit`), and `total` counts each match
    /// the scan found.
    ///
    /// - Parameters:
    ///   - pattern: The regular expression, or the literal text.
    ///   - literal: `true` to escape the pattern first.
    ///   - commandID: The completion token to search inside, or `nil` for each
    ///     command of this session.
    ///   - limit: The cap on the results, or `nil` for the default.
    /// - Returns: The capped matches, plus the full count.
    /// - Throws: `ShellStateError.invalidRegex` for a pattern that does not
    ///   compile, or a file error when the log does not read.
    func grep(
        pattern: String, literal: Bool = false, commandID: String? = nil, limit: Int? = nil
    ) throws -> GrepResults {
        let resultLimit = limit ?? Self.defaultGrepResultLimit
        let source = literal ? NSRegularExpression.escapedPattern(for: pattern) : pattern
        let regex: Regex<AnyRegexOutput>
        do {
            regex = try Regex(source)
        } catch {
            // Take the message of the failure now, thus the error stays
            // `Sendable` and holds no `any Error` across the actor boundary.
            // `String(describing:)` gives the same text the description made
            // before.
            throw ShellStateError.invalidRegex(
                pattern: pattern, underlyingMessage: String(describing: error))
        }

        let sessionPrefix = "\(sessionID)\(Self.fieldSeparator)"
        var results: [GrepResult] = []
        var total = 0
        for line in try readLogLines() {
            guard
                let entry = Self.parseLogLine(
                    line, sessionPrefix: sessionPrefix, commandIDFilter: commandID)
            else { continue }
            guard ((try? regex.firstMatch(in: entry.text)) ?? nil) != nil else { continue }
            total += 1
            if results.count < resultLimit {
                results.append(entry)
            }
        }
        return GrepResults(results: results, total: total)
    }

    // MARK: - Scanning the log

    /// Reads the log file and splits it into lines.
    ///
    /// The split and the decode of the bytes are `splitLogLines`, thus this
    /// method holds the file reading only. `Data` goes through with no copy of
    /// the whole buffer, because `splitLogLines` takes any collection of bytes.
    ///
    /// - Returns: One string for each stored line.
    /// - Throws: When the log file does not read.
    private func readLogLines() throws -> [String] {
        let data = try Data(contentsOf: logURL)
        return Self.splitLogLines(data)
    }

    /// Splits stored bytes into log lines, the way each reader of the log needs
    /// them.
    ///
    /// The split is on the `\n` BYTE and not on a grapheme, thus a `\r\n` pair
    /// also splits. Each line decodes as UTF-8 with replacement, thus output
    /// that does not decode cannot stop the scan. A trailing `\r` goes away,
    /// which is the CRLF behavior of Rust `BufRead::lines()`.
    ///
    /// This is the one home of the split and the decode of a log line. Each
    /// other reader or writer of the log calls it, thus a change to the split,
    /// to the encoding, or to the CRLF behavior is made one time.
    ///
    /// - Parameter data: The stored bytes to split.
    /// - Returns: One string for each line, with no separator and no trailing
    ///   `\r`.
    static func splitLogLines<Bytes: Collection>(_ data: Bytes) -> [String]
    where Bytes.Element == UInt8 {
        data
            .split(separator: newlineByte, omittingEmptySubsequences: true)
            .map { lineBytes in
                let line = String(decoding: lineBytes, as: UTF8.self)
                return line.hasSuffix("\r") ? String(line.dropLast()) : line
            }
    }

    /// Parses one `{sessionID}:{commandID}:{lineNumber}:{text}` log line into a
    /// `GrepResult`.
    ///
    /// It refuses a line of another session, a line that the optional
    /// command-id filter excludes, and a line whose fields do not parse.
    ///
    /// - Parameters:
    ///   - line: The stored line.
    ///   - sessionPrefix: The session id of this store, plus the separator.
    ///   - commandIDFilter: The completion token to keep, or `nil` for each
    ///     command.
    /// - Returns: The parsed result, or `nil` when the line does not belong to
    ///   the answer.
    private static func parseLogLine(
        _ line: String, sessionPrefix: String, commandIDFilter: String?
    ) -> GrepResult? {
        guard line.hasPrefix(sessionPrefix) else { return nil }
        let rest = line.dropFirst(sessionPrefix.count)
        let parts = rest.split(
            separator: fieldSeparator,
            maxSplits: fieldsAfterSessionID - 1,
            omittingEmptySubsequences: false)
        guard parts.count == fieldsAfterSessionID else { return nil }

        let commandID = String(parts[0])
        if let filter = commandIDFilter, filter != commandID { return nil }
        guard let lineNumber = Int(parts[1]), var text = parts.last else { return nil }

        // The same as Rust `grep`'s `str::trim_end()`: drop the trailing
        // whitespace of the matched line. (`getLines` keeps it, on purpose.)
        while let last = text.last, last.isWhitespace { text = text.dropLast() }
        return GrepResult(commandID: commandID, lineNumber: lineNumber, text: String(text))
    }

    // MARK: - The store directory

    /// The name of the append-only log file inside the `.shell` directory.
    private static let logFilename = "log"

    /// The name of the self-ignoring file the store seeds beside the log.
    private static let gitignoreFilename = ".gitignore"

    /// The body of `.shell/.gitignore`: ignore each file of the directory
    /// except the `.gitignore` itself, thus the `.shell` store of a project
    /// stays out of the repository.
    private static let gitignoreContent = """
        # Shell runtime data
        # This file is automatically created by FoundationModelsMultitool

        # Ignore everything except this gitignore
        *
        !.gitignore

        """

    /// Resolves and prepares the store directory: try `preferred`, and after
    /// any failure fall back to `<tmp>/.shell-{sessionID}`.
    ///
    /// - Parameters:
    ///   - preferred: The directory to try first, or `nil` to go directly to
    ///     the fallback.
    ///   - sessionID: The session id, which names the fallback directory.
    /// - Returns: The prepared store directory.
    /// - Throws: When the fallback does not prepare either.
    private static func resolveDirectory(preferred: URL?, sessionID: String) throws -> URL {
        if let preferred {
            do {
                try prepareDirectory(preferred)
                return preferred
            } catch {
                // The preferred location is not usable — a read-only working
                // directory, for example. Fall back.
            }
        }
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent(".shell-\(sessionID)", isDirectory: true)
        try prepareDirectory(fallback)
        return fallback
    }

    /// Makes `directory`, seeds its `.gitignore` when that file is absent, and
    /// touches the `log` file.
    ///
    /// The preparation continues past `createDirectory` — the seed of
    /// `.gitignore` and the touch of the log can each throw — thus a directory
    /// that this function made is removed again before the failure goes up.
    /// Without that unwind the half-prepared directory leaks, and on the
    /// `preferred` branch it leaks *silently*: `resolveDirectory` takes the
    /// error and falls back, thus the caller succeeds and never learns the path.
    ///
    /// It removes a directory that this call made, and no other.
    /// `createDirectory(at:withIntermediateDirectories: true)` succeeds quietly
    /// on a directory that is already there, thus an unwind that always removes
    /// would delete a store of the caller — and each log already in it — after
    /// one write failure that does not last.
    ///
    /// - Parameter directory: The store directory to prepare.
    /// - Throws: When the directory or the log does not create, which is what
    ///   makes `resolveDirectory` fall back.
    private static func prepareDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        let existedBeforehand = fileManager.fileExists(atPath: directory.path)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            let gitignore = directory.appendingPathComponent(Self.gitignoreFilename)
            if !fileManager.fileExists(atPath: gitignore.path) {
                try gitignoreContent.write(to: gitignore, atomically: true, encoding: .utf8)
            }

            let log = directory.appendingPathComponent(Self.logFilename)
            if !fileManager.fileExists(atPath: log.path) {
                guard fileManager.createFile(atPath: log.path, contents: nil) else {
                    throw ShellStateError.logCreationFailed(log)
                }
            }
        } catch {
            if !existedBeforehand {
                try? fileManager.removeItem(at: directory)
            }
            throw error
        }
    }
}
