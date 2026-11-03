// `ProcessLedger` — the files that let a new host kill the children that a
// crashed host left running.
//
// The `atexit` sweep of `ProcessRegistry.global` runs on a normal exit only.
// A crash, or a `SIGKILL`, gives it no chance to run. The children then stay
// alive, and a restored run can start the same command again while the old
// one still writes to the same working tree.
//
// For each child, the host writes one record file at the spawn and removes it
// after the reap. A record holds two identities, and each identity is a pid
// AND a start time:
//
//   * the child, and
//   * the owner, which is the host process that wrote the record.
//
// A new host reads the records, and it kills the process group of a child only
// when all of these hold:
//
//   1. The owner is not alive. A live owner (this process included) can still
//      run the child on purpose. A process is alive when a process with the
//      pid of the owner has the start time of the owner.
//   2. A live process has the pid of the child AND the start time of the
//      child. The kernel can give a pid to a new process after the old one
//      ended. The start time tells the two apart, thus a reused pid is never
//      killed.
//
// The start time comes from the kernel (`proc_pidinfo`). There is a short
// gap between the check of the start time and the kill. A process that
// the kernel starts inside that gap with the same pid is not a case to
// handle: the kernel does not give a pid again before it went through the
// whole pid range.

import Darwin
import Foundation

/// One process, named by its pid and the time the kernel started it.
///
/// The pid alone is not an identity: the kernel gives a pid to a new process
/// after the old one ended. The pair is.
struct ProcessIdentity: Codable, Equatable, Sendable {
    /// The pid of the process.
    var pid: Int32

    /// The whole seconds of the start time, since the epoch.
    var startSeconds: Int64

    /// The microseconds of the start time, after ``startSeconds``.
    var startMicroseconds: Int64

    /// The identity of this process.
    static let own = of(pid: getpid()) ?? ProcessIdentity(pid: getpid(), startSeconds: 0, startMicroseconds: 0)

    /// The identity of the live process with `pid`.
    ///
    /// - Parameter pid: The pid to read.
    /// - Returns: The identity, or `nil` when no process has this pid.
    static func of(pid: pid_t) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard written == size else { return nil }
        return ProcessIdentity(
            pid: pid, startSeconds: Int64(info.pbi_start_tvsec),
            startMicroseconds: Int64(info.pbi_start_tvusec))
    }

    /// Whether a live process is this identity.
    var isAlive: Bool {
        Self.of(pid: pid) == self
    }
}

/// The record files of the children of one host, in one directory.
struct ProcessLedger: Sendable {
    /// What one record file holds.
    private struct Record: Codable {
        /// The child that the host spawned.
        let child: ProcessIdentity
        /// The host process that wrote this record.
        let owner: ProcessIdentity
    }

    /// The extension of a record file.
    private static let fileExtension = "json"

    /// The directory that holds the record files. It is made on the first
    /// write.
    let directory: URL

    /// Makes a ledger over `directory`.
    ///
    /// - Parameter directory: The directory for the record files.
    init(directory: URL) {
        self.directory = directory
    }

    /// Writes the record of one child.
    ///
    /// - Parameters:
    ///   - key: The name of the record. A new record replaces an old record
    ///     with the same key. The key must be a valid file name.
    ///   - child: The child to record.
    ///   - owner: The host that runs the child. It is this process by default.
    /// - Throws: What the encoding or the write throws.
    func record(key: String, child: ProcessIdentity, owner: ProcessIdentity = .own) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Record(child: child, owner: owner))
        try data.write(to: url(forKey: key), options: .atomic)
    }

    /// Removes the record of one child. Nothing happens when there is none.
    ///
    /// - Parameter key: The name of the record.
    func remove(key: String) {
        try? FileManager.default.removeItem(at: url(forKey: key))
    }

    /// The keys of the records that are in the directory, sorted.
    func recordedKeys() -> [String] {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == Self.fileExtension }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    /// Kills the leftover children of hosts that are not alive, and removes
    /// every record that it read.
    ///
    /// A record of a live host stays: that host runs the child. A record that
    /// cannot be decoded is removed, because nothing can use it.
    ///
    /// - Returns: How many process groups it killed.
    @discardableResult
    func reapLeftovers() -> Int {
        var killed = 0
        for key in recordedKeys() {
            let file = url(forKey: key)
            guard let record = Self.read(file) else {
                remove(key: key)
                continue
            }
            if record.owner.isAlive { continue }
            if Self.killGroup(of: record.child) { killed += 1 }
            remove(key: key)
        }
        return killed
    }

    /// The file of the record with `key`.
    private func url(forKey key: String) -> URL {
        directory.appendingPathComponent(key).appendingPathExtension(Self.fileExtension)
    }

    /// Reads one record file.
    ///
    /// - Parameter file: The file to read.
    /// - Returns: The record, or `nil` when the file does not decode.
    private static func read(_ file: URL) -> Record? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    /// Kills the process group of `child`, only when a live process is the
    /// child: the pid AND the start time match.
    ///
    /// The child led its own group at the spawn, thus its pid names the group.
    /// A matching process that leads no group of the same id gets the kill
    /// itself and nothing more.
    ///
    /// - Parameter child: The recorded identity.
    /// - Returns: `true` when a kill went out.
    private static func killGroup(of child: ProcessIdentity) -> Bool {
        guard child.isAlive else { return false }
        if getpgid(child.pid) == child.pid {
            return killpg(child.pid, SIGKILL) == 0
        }
        return kill(child.pid, SIGKILL) == 0
    }
}
