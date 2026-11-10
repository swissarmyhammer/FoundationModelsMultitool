// `ShellCapability` — the `shell` noun, and the three verbs that render under
// it.
//
// eventplan.md § "Registration of capabilities: noun/verb": "Built-in
// capabilities and user capabilities are the same thing. `withShell()` is a
// short form of `withCapability(ShellCapability(...))`." So this type holds no
// logic of its own. It names the noun one time, and it composes the three
// verbs that were already written as plain `FoundationModels.Tool` conformers.
//
// **The capability is what makes the three verbs one session.** Each verb's own
// doc comment promises that "the store it records into is the store the
// capability owns", and this type is where that promise is kept: one
// `ShellState` reaches the run-plane verb through its runner and reaches the
// two content-plane verbs directly, thus `tools.shell.getLines` reads what
// `tools.shell.execute` just wrote.
//
// **The capability is off by default**, and nothing here makes it otherwise.
// eventplan.md § "The capability contract": "The modules are opt-in ... They
// are off by default. This keeps the permission posture at the registry
// boundary." A host that never calls `MultiTool.Builder.withShell(...)` renders
// no `tools.shell` namespace at all.
//
// **There is no permission layer, no policy parameter and no confinement.** The
// verb asks no permission question, it prompts nobody, and it keeps no
// remembered answer — see the header of `Execute.swift`. Each command runs as
// `/bin/sh -c` with the rights of the user of this process. A host that must
// not give a shell registers none: in the `sandboxed` tool mode the builder
// refuses this capability.
//
// **`listProcesses` and `killProcess` are deliberately absent.** eventplan.md §
// "Consolidation of the siblings" removes them: the shared background engine of
// FoundationModelsExtras owns the run plane now, so `status()` and `cancel(completionToken)`
// answer those two questions for every capability at once rather than for this
// one alone.

import Foundation
import FoundationModels

/// The shell capability: one noun, and the three verbs of the virtual shell.
///
/// ```swift
/// let surface = try MultiTool.Builder()
///     .withShell()                        // tools.shell.execute, .getLines, .grepHistory
///     .build()
/// ```
///
/// `MultiTool.Builder.withShell(storeDirectory:outputChunkStream:defaultWorkingDirectory:)`
/// is the short form of `withCapability(ShellCapability(...))`, and it takes the
/// same three arguments. Register this type directly where a host builds the
/// capability once and hands it on.
///
/// The three verbs render in the order they are listed:
///
/// | Path | What it does |
/// |---|---|
/// | `tools.shell.execute` | Runs one command, and answers with the tail of its output. |
/// | `tools.shell.getLines` | Reads the captured output of one run, by line number. |
/// | `tools.shell.grepHistory` | Searches the captured output of this session's runs. |
public struct ShellCapability: Capability {

    /// The one namespace each verb of this capability renders under — the first
    /// segment of `tools.shell.<verb>`.
    ///
    /// The capability OWNS this noun: `MultiTool.Builder.withCapability(_:)`
    /// claims the whole `tools.shell` namespace, so a second registration under
    /// it fails loudly at `buildRegistry()` rather than quietly at dispatch.
    public let noun = "shell"

    /// The three verbs of the shell, in the order they render.
    ///
    /// Each one supplies its own second segment through `Tool.name`, so this
    /// array and the noun above are the whole of what the surface needs.
    public let tools: [any Tool]

    /// Makes the shell capability over one store, one live view of the output,
    /// and one default working directory.
    ///
    /// **This initializer throws, and `MultiTool.Builder.withShell(...)` throws
    /// with it.** That is resource acquisition rather than validation: the
    /// store prepares a directory on disk, and a store that cannot prepare has
    /// nowhere to record a run. It is never a `MultiToolBuilderError` — every
    /// rule that type reports is still examined one time, at `buildRegistry()`,
    /// exactly as the documentation of `MultiToolBuilderError` states.
    ///
    /// - Parameters:
    ///   - storeDirectory: The directory the history and the captured output of
    ///     each run are written into. The default, `nil`, takes `<cwd>/.shell`,
    ///     which is where `ShellState` roots a store of its own — see
    ///     `ShellDotfolder.currentDirectory()`. A store that cannot prepare
    ///     there falls back to a temporary directory rather than throwing, so
    ///     this initializer throws only when neither prepares.
    ///   - outputChunkStream: The live view of the output a subscribed host
    ///     reads. The default, `nil`, tees nothing.
    ///   - defaultWorkingDirectory: The directory a `tools.shell.execute` call
    ///     runs in when it omits `workingDirectory`. The default, `nil`, keeps
    ///     the current directory of this process. A host with a session root
    ///     passes that root, thus a plain command runs where the session
    ///     stands and not where the host process happens to stand — see
    ///     `ShellRunner.defaultWorkingDirectory`.
    /// - Throws: What `ShellState` throws when neither the store directory nor
    ///   the temporary fallback prepares.
    public init(
        storeDirectory: URL? = nil,
        outputChunkStream: ShellOutputChunkStream? = nil,
        defaultWorkingDirectory: URL? = nil
    ) throws {
        self.init(
            store: try ShellStore(storeDirectory: storeDirectory),
            outputChunkStream: outputChunkStream,
            defaultWorkingDirectory: defaultWorkingDirectory)
    }

    /// Makes the shell capability over a store that other capabilities may
    /// share, with its own live view and default working directory.
    ///
    /// A host that runs several sessions in one working directory makes one
    /// `ShellStore` and hands it to the capability of each session. Then each
    /// session's `tools.shell.getLines` and `tools.shell.grepHistory` see every
    /// command of the store, whichever session ran it. The store already
    /// prepared its directory, thus this initializer does not throw.
    ///
    /// - Parameters:
    ///   - store: The history and output store this capability records into.
    ///   - sessionID: The session this capability runs commands for, read
    ///     each time a command runs, or `nil` — the default — for none. Each
    ///     command records the value at its run, and the `sessionID` field of
    ///     the `execute`, `getLines` and `grepHistory` results gives it back,
    ///     thus each session on a shared store can tell whose command it
    ///     reads. A closure, because a host builds its tools before it knows
    ///     its session, and can replace the session under the same tools.
    ///   - outputChunkStream: The live view of the output a subscribed host
    ///     reads. The default, `nil`, tees nothing.
    ///   - defaultWorkingDirectory: The directory a `tools.shell.execute` call
    ///     runs in when it omits `workingDirectory`. The default, `nil`, keeps
    ///     the current directory of this process.
    public init(
        store: ShellStore,
        sessionID: @escaping @Sendable () -> String? = { nil },
        outputChunkStream: ShellOutputChunkStream? = nil,
        defaultWorkingDirectory: URL? = nil
    ) {
        // The runner carries the store, the live view and the default
        // directory to the run plane.
        var runner = ShellRunner(state: store.state, outputChunkStream: outputChunkStream)
        runner.defaultWorkingDirectory = defaultWorkingDirectory?.path
        runner.sessionID = sessionID
        self.init(runner: runner)
    }

    /// Makes the shell capability over one configured runner.
    ///
    /// `Execute` is configured with the runner and with nothing else. The two
    /// content-plane verbs take the store of the runner, thus each verb of one
    /// capability reads the same store. A test gives a runner with a hook of
    /// its own here, and the capability stays the type a host registers.
    ///
    /// - Parameter runner: The runner each command of `tools.shell.execute`
    ///   spawns through.
    init(runner: ShellRunner) {
        self.tools = [
            Execute(runner: runner),
            GetLines(state: runner.state),
            GrepHistory(state: runner.state),
        ]
    }
}
