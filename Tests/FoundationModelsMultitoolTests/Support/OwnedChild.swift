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

import Darwin

/// One `/bin/cat` child of a test, in its own process group.
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

    /// The pid of the child. It is also the id of its process group.
    let pid: pid_t

    /// The write end of the standard input of the child, or `nil` after
    /// ``finish()`` closed it.
    private var stdinWriteDescriptor: Int32?

    /// The ending of the child, once ``finish()`` read it.
    private var ending: Ending?

    /// Spawns the child in its own process group.
    ///
    /// - Throws: ``SpawnError`` when the pipe or the spawn fails.
    init() throws {
        var descriptors: [Int32] = [0, 0]
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
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)

        var childPid: pid_t = 0
        let arguments = [strdup(Self.program), nil]
        defer { arguments.forEach { free($0) } }
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
        let signal = status & 0x7f
        let exitedMark: Int32 = 0
        if signal == exitedMark { return .exited((status >> 8) & 0xff) }
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
