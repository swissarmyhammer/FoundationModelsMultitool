// `OwnedChild` — a child process that a test spawns itself, for a test that
// checks who a kill reached.
//
// The child is `/bin/cat` on a pipe. It leads its own process group, and it
// lives until its standard input closes or a kill ends it. A test closes the
// pipe at the end and reads HOW the child ended: a signal means that a kill
// reached it, and an exit with code 0 means that no kill did. The test needs
// no timer for this, because `waitpid` returns on the end of the child.
//
// A test only signals a child that it spawned itself. This type has no way to
// signal any other pid.
//
// A test of a kill that reaches a process without a group of its own asks for
// a child that stays in the group of the test process. That child is not a
// target for a group kill: the test process would be in the group.

import Darwin

/// One `/bin/cat` child of a test, in its own process group by default.
final class OwnedChild {
    /// How the child ended.
    enum Ending: Equatable {
        /// A signal ended the child.
        case signaled(Int32)
        /// The child exited by itself, with this code.
        case exited(Int32)
    }

    /// The path of the child program. It exits when its standard input ends.
    private static let program = "/bin/cat"

    /// The number of descriptors that `pipe` fills.
    private static let pipeEndCount = 2

    /// The process-group id that makes `posix_spawn` put the child in a new
    /// group with the pid of the child as the id.
    private static let newGroupOfOwnPid: pid_t = 0

    /// The bits of a wait status that hold the signal that ended the child.
    private static let signalMask: Int32 = 0x7f

    /// The number of bits that the exit code is above in a wait status.
    private static let exitCodeShift: Int32 = 8

    /// The bits of the shifted wait status that hold the exit code.
    private static let exitCodeMask: Int32 = 0xff

    /// The signal bits of a wait status of a child that exited by itself.
    private static let noSignal: Int32 = 0

    /// The pid of the child. It is also the id of its process group when the
    /// child leads its group.
    let pid: pid_t

    /// The write end of the standard input of the child, or `nil` after
    /// ``finish()`` closed it.
    private var stdinWriteDescriptor: Int32?

    /// The ending of the child, once ``finish()`` read it.
    private var ending: Ending?

    /// Spawns the child.
    ///
    /// - Parameter leadsGroup: `true`, the default, puts the child in its own
    ///   process group. `false` leaves it in the group of the test process.
    /// - Throws: ``SpawnError`` when the pipe or the spawn fails.
    init(leadsGroup: Bool = true) throws {
        var descriptors = [Int32](repeating: 0, count: Self.pipeEndCount)
        guard pipe(&descriptors) == 0 else { throw SpawnError.pipe(errno) }
        let (readEnd, writeEnd) = (descriptors[0], descriptors[1])
        defer { close(readEnd) }
        // The child must not hold the write end, or it never sees the end of
        // its input.
        _ = fcntl(writeEnd, F_SETFD, FD_CLOEXEC)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, readEnd, STDIN_FILENO)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        if leadsGroup {
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
            posix_spawnattr_setpgroup(&attributes, Self.newGroupOfOwnPid)
        }

        var childPid: pid_t = 0
        let arguments = [strdup(Self.program), nil]
        defer {
            for argument in arguments {
                free(argument)
            }
        }
        let result = posix_spawn(&childPid, Self.program, &actions, &attributes, arguments, environ)
        guard result == 0 else {
            close(writeEnd)
            throw SpawnError.spawn(result)
        }
        pid = childPid
        stdinWriteDescriptor = writeEnd
    }

    /// Why the spawn of the child failed.
    enum SpawnError: Error {
        /// `pipe` failed with this errno.
        case pipe(Int32)
        /// `posix_spawn` failed with this error number.
        case spawn(Int32)
    }

    /// Closes the standard input of the child and waits for its end.
    ///
    /// The wait returns when the child ended, by a kill that came before, or
    /// by the end of its input. A second call returns the same ending.
    ///
    /// - Returns: How the child ended.
    func finish() -> Ending {
        if let ending { return ending }
        if let stdinWriteDescriptor {
            close(stdinWriteDescriptor)
            self.stdinWriteDescriptor = nil
        }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        let read = Self.read(status: status)
        ending = read
        return read
    }

    /// Translates a wait status into an ``Ending``.
    ///
    /// - Parameter status: The status `waitpid` gave.
    /// - Returns: The signal that ended the child, or its exit code.
    private static func read(status: Int32) -> Ending {
        let signal = status & signalMask
        if signal == noSignal { return .exited((status >> exitCodeShift) & exitCodeMask) }
        return .signaled(signal)
    }

    deinit {
        // This process spawned the child, thus the pid is not reused before
        // the wait below. The kill reaches our own child only.
        guard ending == nil else { return }
        kill(pid, SIGKILL)
        _ = finish()
    }
}
