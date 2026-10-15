// `ShellCommandGate` — a shell command that runs until the test releases it.
//
// A test that needs a child process that is still running uses this gate in
// place of `sleep N`. The command reads one line from a FIFO that the gate
// makes. The read blocks until the test writes the line. Thus the command
// ends at a point that the test chose, and no test waits on real time.

import Darwin
import Foundation
import Synchronization

@testable import FoundationModelsMultitool

/// A named pipe (FIFO) that holds a shell command until the test releases it.
///
/// ``waitCommand`` is a shell fragment that blocks on the FIFO.
/// ``release(whileAlive:)`` opens the FIFO for writing, writes one line, and
/// closes it. The open for writing blocks until the command opened the FIFO
/// for reading, thus the release reaches the command that waits, also when
/// the command starts after the call of the release. The release also ends
/// when the process of the command exits first, thus no release waits for
/// all time. ``release(commandIn:orEndOf:)`` gets that process from the
/// `ShellState` of a command that runs through the `execute` verb or the run
/// plane. It also ends when the call that must start the command ends first.
///
/// One gate releases ONE wait. A command that waits more than one time needs
/// one gate for each wait. The cause: a release closes its write end only
/// after the write. In that interval the command can read the line, go on,
/// and open the same FIFO for its next wait. An open for reading ends at once
/// while a writer holds the FIFO. The close of the write end then gives the
/// next `read` the end of the file, thus that wait ends with no line and no
/// release. Thus a second release of one gate throws ``Failure``.
final class ShellCommandGate: Sendable {
    /// What a FIFO could not do.
    struct Failure: Error, CustomStringConvertible {
        /// What went wrong.
        let description: String
    }

    /// The path of the FIFO.
    let path: String

    /// The line that ``release(whileAlive:)`` writes.
    private static let releaseLine = "go\n"

    /// The mode of the FIFO: read and write for the owner only.
    private static let fifoMode: mode_t = 0o600

    /// `true` once ``release(whileAlive:)`` started. One gate releases one
    /// wait (see the type), thus a second release throws.
    private let released = Mutex(false)

    /// Makes a FIFO in the temporary directory.
    ///
    /// - Throws: ``Failure`` when `mkfifo` fails.
    init() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("multitool-gate-\(UUID().uuidString).fifo").path
        guard mkfifo(path, Self.fifoMode) == 0 else {
            throw Failure(description: "mkfifo failed for \(path): errno \(errno)")
        }
        self.path = path
    }

    deinit {
        unlink(path)
    }

    /// A shell fragment that blocks until a release writes its line.
    var waitCommand: String {
        "read gate < '\(path)'"
    }

    /// How ``release(whileAlive:)`` ended.
    enum Release: Equatable, Sendable {
        /// The command opened the FIFO, and it got the line.
        case reached

        /// The process of the command exited before it opened the FIFO, or
        /// before it read the line. The release wrote no line.
        case commandExited
    }

    /// The queue on which the exit source of a release calls its handler.
    private static let exitQueue = DispatchQueue(label: "ShellCommandGate.exit")

    /// Lets the command that waits on the FIFO go on, or ends when the
    /// process of that command exits first.
    ///
    /// An open for writing waits until a reader opens the FIFO. When the
    /// command ended before it came to the gate, no reader comes, and that
    /// wait does not end. This release ends on the first of two events, and
    /// never on a time:
    ///
    /// 1. A reader opens the FIFO. The release writes the line and gives
    ///    ``Release/reached``.
    /// 2. The kqueue exit event (`EVFILT_PROC`, `NOTE_EXIT`) of `pid` comes.
    ///    The release then opens the FIFO for reading itself, with
    ///    `O_NONBLOCK`, thus the pending open for writing ends. It writes no
    ///    line, and it gives ``Release/commandExited``.
    ///
    /// The read end that the exit event opens stays open until the writer
    /// took it, thus an open for writing that starts after the exit event
    /// does not wait either. The write end carries `F_SETNOSIGPIPE`, thus a
    /// reader that exits between the open and the write gives `EPIPE` and
    /// ``Release/commandExited``, and no `SIGPIPE`.
    ///
    /// - Parameter pid: The pid of the process of the command: the shell
    ///   child that runs ``waitCommand``.
    /// - Returns: How the release ended.
    /// - Throws: ``Failure`` when this gate was released before (one gate
    ///   releases one wait; see the type), when the FIFO does not open, or
    ///   when the write fails for a cause other than `EPIPE`. A second
    ///   release throws before it opens the FIFO.
    func release(whileAlive pid: pid_t) async throws -> Release {
        let releasedBefore = released.withLock { current in
            defer { current = true }
            return current
        }
        guard !releasedBefore else {
            throw Failure(description: "the gate \(path) was released before; one gate releases one wait")
        }
        let path = path
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Release, any Error>) in
            let race = GateReleaseRace(path: path)
            let source = DispatchSource.makeProcessSource(
                identifier: pid, eventMask: .exit, queue: Self.exitQueue)
            source.setEventHandler { race.commandExited() }
            source.resume()
            if ProcessExitWait.hasExited(pid) {
                race.commandExited()
            }
            DispatchQueue.global().async {
                defer { source.cancel() }
                continuation.resume(with: Result { try race.writeLine(Self.releaseLine) })
            }
        }
    }

    /// How ``release(commandIn:orEndOf:)`` ended.
    enum CommandRelease: Equatable, Sendable {
        /// The command started, and the release ended as `release` tells.
        case released(Release, commandID: String)

        /// The call that must start the command ended before the command
        /// started. The release wrote no line. `returned` tells what the call
        /// returned.
        case callEndedFirst(returned: String)
    }

    /// Lets the command that waits on the FIFO go on, for a command that runs
    /// through `state`, or ends when the process of that command exits first,
    /// or when the call that must start the command ends first.
    ///
    /// The test does not have the pid of a command that runs through the
    /// `execute` verb or the run plane. Each step that gets it ends on an
    /// event:
    ///
    /// 1. The first of two events: `ShellState.waitForCommand(holding:)` ends
    ///    when a command whose command line holds the path of this FIFO
    ///    started, and gives the completion token of that command; or `call`
    ///    records its end. When the call ended first, the command never
    ///    starts, and this release gives
    ///    ``CommandRelease/callEndedFirst(returned:)``. The release then
    ///    cancels the wait for the command and waits for the end of that
    ///    wait, thus no wait stays behind.
    /// 2. `ShellState.groupToCancel(commandID:)` ends when the run registered
    ///    the process of the command. It gives `nil` when the record of the
    ///    command is final with no process, for example after a spawn that
    ///    failed. This release then gives ``Release/commandExited``.
    /// 3. ``release(whileAlive:)`` ends when the command got the line, or when
    ///    the process exited.
    ///
    /// `groupToCancel` only reads the process group. It sends no signal.
    ///
    /// - Parameters:
    ///   - state: The store of the shell commands of the test.
    ///   - call: The end of the call that must start the command.
    /// - Returns: How the release ended.
    /// - Throws: What ``release(whileAlive:)`` throws.
    func release(commandIn state: ShellState, orEndOf call: CallEnd) async throws -> CommandRelease {
        let race = CommandStartRace()
        call.observe { returned in race.finish(.callEnded(returned: returned)) }
        let path = path
        let commandWait = Task {
            if let commandID = await state.waitForCommand(holding: path) {
                race.finish(.started(commandID: commandID))
            }
        }
        let first = await race.first()
        commandWait.cancel()
        await commandWait.value
        switch first {
        case .callEnded(let returned):
            return .callEndedFirst(returned: returned)
        case .started(let commandID):
            guard let group = await state.groupToCancel(commandID: commandID) else {
                return .released(.commandExited, commandID: commandID)
            }
            return .released(try await release(whileAlive: group.pid), commandID: commandID)
        }
    }
}

/// The race of one ``ShellCommandGate/release(commandIn:orEndOf:)``: the start
/// of the command against the end of the call that must start it. The first
/// event wins.
private final class CommandStartRace: Sendable {
    /// One event of the race.
    enum Event: Sendable {
        /// The command started under `commandID`.
        case started(commandID: String)

        /// The call ended, and returned `returned`.
        case callEnded(returned: String)
    }

    /// What the two events and the waiter know of the race.
    private struct State {
        /// The first event, after it came.
        var first: Event?

        /// The waiter of ``first()``, while it waits.
        var waiter: CheckedContinuation<Event, Never>?
    }

    /// The state that the events and the waiter share.
    private let state = Mutex(State())

    /// Records `event`, unless an event came before it, and ends the wait of
    /// ``first()``.
    ///
    /// - Parameter event: The event that came.
    func finish(_ event: Event) {
        let waiter = state.withLock { current -> CheckedContinuation<Event, Never>? in
            guard current.first == nil else { return nil }
            current.first = event
            defer { current.waiter = nil }
            return current.waiter
        }
        waiter?.resume(returning: event)
    }

    /// Waits for the first event. Returns at once when it already came.
    ///
    /// - Returns: The first event.
    func first() async -> Event {
        await withCheckedContinuation { (continuation: CheckedContinuation<Event, Never>) in
            let first = state.withLock { current -> Event? in
                if current.first == nil {
                    current.waiter = continuation
                }
                return current.first
            }
            if let first {
                continuation.resume(returning: first)
            }
        }
    }
}

/// The race of one ``ShellCommandGate/release(whileAlive:)``: the open for
/// writing against the exit of the command.
private final class GateReleaseRace: Sendable {
    /// What the exit handler and the writer know of the race.
    private struct State {
        /// `true` once the exit event came before the open for writing ended.
        var exited = false

        /// `true` once the open for writing ended. After that, an exit event
        /// changes nothing and opens no read end.
        var finished = false

        /// The read end that the exit event opened, until the writer closes it.
        var unblockingReader: Int32?
    }

    /// The path of the FIFO.
    private let path: String

    /// The state that the exit handler and the writer share.
    private let state = Mutex(State())

    /// Makes the race for the FIFO at `path`.
    ///
    /// - Parameter path: The path of the FIFO.
    init(path: String) {
        self.path = path
    }

    /// Records the exit of the command, and opens the FIFO for reading, thus
    /// the open for writing does not wait for a reader that never comes. A
    /// second call, or a call after the open for writing ended, does nothing.
    func commandExited() {
        state.withLock { current in
            guard !current.exited, !current.finished else { return }
            current.exited = true
            let reader = open(path, O_RDONLY | O_NONBLOCK)
            current.unblockingReader = reader >= 0 ? reader : nil
        }
    }

    /// Opens the FIFO for writing and writes `line`, unless the command
    /// exited first.
    ///
    /// - Parameter line: The line to write.
    /// - Returns: ``ShellCommandGate/Release/reached`` when the command got
    ///   the line, and ``ShellCommandGate/Release/commandExited`` otherwise.
    /// - Throws: ``ShellCommandGate/Failure`` when the open fails, or when the
    ///   write fails for a cause other than `EPIPE`.
    func writeLine(_ line: String) throws -> ShellCommandGate.Release {
        let descriptor = open(path, O_WRONLY)
        guard descriptor >= 0 else {
            throw ShellCommandGate.Failure(description: "open failed for \(path): errno \(errno)")
        }
        defer { close(descriptor) }
        let exited = state.withLock { current in
            current.finished = true
            if let reader = current.unblockingReader {
                close(reader)
                current.unblockingReader = nil
            }
            return current.exited
        }
        guard !exited else { return .commandExited }
        _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        let bytes = Array(line.utf8)
        let written = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        if written == bytes.count {
            return .reached
        }
        if written < 0, errno == EPIPE {
            return .commandExited
        }
        throw ShellCommandGate.Failure(description: "write failed for \(path): errno \(errno)")
    }
}
