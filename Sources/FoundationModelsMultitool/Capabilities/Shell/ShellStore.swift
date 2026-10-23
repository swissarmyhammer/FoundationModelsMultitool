// `ShellStore` — the shell history several capabilities of one process share.
//
// An ACP host runs several sessions in one process, and the sessions that
// stand in one working directory share ONE shell store: one history, one log,
// one list of command records. The host makes one `ShellStore` for each such
// directory and hands it to `ShellCapability.init(store:...)` for each session.
// The confinement, the live view of the output and the default working
// directory stay per capability, thus per session; only the store is shared.
//
// Every capability on one store reaches the one `ShellState` actor, thus
// `tools.shell.getLines` and `tools.shell.grepHistory` of each session see
// every command of the store. The command ids need no partition: each one is
// the completion token the run plane mints, a ULID no other run shares.

import Foundation

/// One shell history — its command records and its `.shell/log` — that any
/// number of `ShellCapability` values share.
///
/// ```swift
/// let store = try ShellStore(storeDirectory: cwd.appendingPathComponent(".shell"))
/// let sessionA = ShellCapability(store: store, defaultWorkingDirectory: cwd)
/// let sessionB = ShellCapability(store: store, defaultWorkingDirectory: cwd)
/// // sessionB's getLines reads what sessionA's execute ran.
/// ```
public final class ShellStore: Sendable {

    /// The history actor every capability on this store reads and writes.
    let state: ShellState

    /// The directory the history and the captured output are written into —
    /// the directory the store asked for, or the temporary fallback when that
    /// one did not prepare.
    public var directory: URL {
        state.logURL.deletingLastPathComponent()
    }

    /// Makes a store over one directory.
    ///
    /// **This initializer throws**, for the reason `ShellCapability.init`
    /// throws: the store prepares a directory on disk, and a store that cannot
    /// prepare has nowhere to record a run.
    ///
    /// - Parameter storeDirectory: The directory the history and the captured
    ///   output of each run are written into. The default, `nil`, takes
    ///   `<cwd>/.shell` — see `ShellDotfolder.currentDirectory()`. A store that
    ///   cannot prepare there falls back to a temporary directory rather than
    ///   throwing.
    /// - Throws: What `ShellState` throws when neither the store directory nor
    ///   the temporary fallback prepares.
    public init(storeDirectory: URL? = nil) throws {
        if let storeDirectory {
            state = try ShellState(preferredDirectory: storeDirectory)
        } else {
            state = try ShellState()
        }
    }
}
