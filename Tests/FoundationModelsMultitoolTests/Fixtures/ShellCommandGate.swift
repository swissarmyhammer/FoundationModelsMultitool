// `ShellCommandGate` — a shell command that runs until the test releases it.
//
// A test that needs a child process that is still running uses this gate in
// place of `sleep N`. The command reads one line from a FIFO that the gate
// makes. The read blocks until the test writes the line. Thus the command
// ends at a point that the test chose, and no test waits on real time.

import Darwin
import Foundation

/// A named pipe (FIFO) that holds a shell command until the test releases it.
///
/// ``waitCommand`` is a shell fragment that blocks on the FIFO. ``release()``
/// opens the FIFO for writing, writes one line, and closes it. The open for
/// writing blocks until the command opened the FIFO for reading, thus the
/// release always reaches the command that waits, also when the command
/// starts after the call of ``release()``.
final class ShellCommandGate: Sendable {
    /// What a FIFO could not do.
    struct Failure: Error, CustomStringConvertible {
        /// What went wrong.
        let description: String
    }

    /// The path of the FIFO.
    let path: String

    /// The line that ``release()`` writes.
    private static let releaseLine = "go\n"

    /// The mode of the FIFO: read and write for the owner only.
    private static let fifoMode: mode_t = 0o600

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

    /// A shell fragment that blocks until ``release()`` writes its line.
    var waitCommand: String {
        "read gate < '\(path)'"
    }

    /// Lets the command that waits on the FIFO go on.
    ///
    /// The open for writing blocks until a reader opened the FIFO. The block
    /// is on a thread of a global dispatch queue, and not on a thread of the
    /// cooperative pool. A command that never starts makes the release wait,
    /// and that wait is the failure of the test.
    ///
    /// - Throws: ``Failure`` when the FIFO does not open or the write fails.
    func release() async throws {
        let path = path
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global().async {
                let descriptor = open(path, O_WRONLY)
                guard descriptor >= 0 else {
                    continuation.resume(throwing: Failure(description: "open failed for \(path): errno \(errno)"))
                    return
                }
                defer { close(descriptor) }
                let line = Array(Self.releaseLine.utf8)
                let written = line.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
                guard written == line.count else {
                    continuation.resume(throwing: Failure(description: "write failed for \(path): errno \(errno)"))
                    return
                }
                continuation.resume()
            }
        }
    }
}
