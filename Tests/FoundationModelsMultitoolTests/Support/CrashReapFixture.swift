// `CrashReapFixture` — what the crash reap suites share: the dead owner, the
// record key, the start time offset, the directory helper, and the two reap
// rules that each spawn path must keep.
//
// The shell store and the stdio server process reap leftovers by the same
// rules. Each suite gives only the step that is its own: how it writes the
// record of a crashed host and how it makes the new store or server.

import Darwin
import Foundation
import Testing

@testable import FoundationModelsMultitool

/// The shared fixture of the suites that test the reap of leftover children.
enum CrashReapFixture {
    /// The offset, in seconds, that makes a start time differ from the real
    /// one. It stands for a pid that another process took.
    static let otherStartOffset: Int64 = 1

    /// The key of the record that a test writes.
    static let recordKey = "leftover"

    /// An owner that is not alive: the pid of this process with a start time
    /// that this process never had.
    static var deadOwner: ProcessIdentity {
        ProcessIdentity(pid: getpid(), startSeconds: 0, startMicroseconds: 0)
    }

    /// The step of a suite that leaves a record and then makes a new store or
    /// server over it, so the reap runs.
    ///
    /// - Parameters:
    ///   - child: The identity that the record holds for the child.
    ///   - owner: The host that wrote the record.
    typealias ReapAfterCrash = (_ child: ProcessIdentity, _ owner: ProcessIdentity) throws -> Void

    /// A temporary directory that the test owns. The suite must have the
    /// `ownsTemporaryDirectories` trait.
    ///
    /// - Parameter prefix: The name prefix of the directory.
    /// - Returns: The directory, made on disk.
    static func makeDirectory(prefix: String) -> URL {
        TestSupport.makeTemporaryDirectory(named: prefix)
    }

    /// Checks that the reap kills a leftover whose pid and start time match.
    ///
    /// - Parameter reapAfterCrash: The step that leaves the record and reaps.
    static func expectMatchingLeftoverKilled(reapAfterCrash: ReapAfterCrash) throws {
        let leftover = try OwnedChild()
        let identity = try #require(ProcessIdentity.of(pid: leftover.pid))

        try reapAfterCrash(identity, deadOwner)

        #expect(leftover.finish() == .signaled(SIGKILL))
    }

    /// Checks that the reap spares a process that has the pid of the record
    /// and another start time.
    ///
    /// - Parameter reapAfterCrash: The step that leaves the record and reaps.
    static func expectReusedPidSpared(reapAfterCrash: ReapAfterCrash) throws {
        let bystander = try OwnedChild()
        var identity = try #require(ProcessIdentity.of(pid: bystander.pid))
        identity.startSeconds += otherStartOffset

        try reapAfterCrash(identity, deadOwner)

        #expect(bystander.finish() == .exited(0))
    }
}
