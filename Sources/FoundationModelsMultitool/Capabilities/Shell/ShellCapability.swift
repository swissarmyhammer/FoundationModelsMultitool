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
// **There is no permission layer, and no policy parameter.** By the decision of
// 2026-08-24 the seatbelt sandbox is the only gate on a command: the verb asks
// no permission question, it prompts nobody, and it keeps no remembered answer
// — see the header of `Execute.swift`. What a host configures here is the
// confinement itself, through `sandbox`.
//
// **`listProcesses` and `killProcess` are deliberately absent.** eventplan.md §
// "Consolidation of the siblings" removes them: the shared background engine of
// Router owns the run plane now, so `status()` and `cancel(completionToken)`
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
/// `MultiTool.Builder.withShell(storeDirectory:sandbox:outputChunkStream:defaultWorkingDirectory:)`
/// is the short form of `withCapability(ShellCapability(...))`, and it takes the
/// same four arguments. Register this type directly where a host builds the
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

    /// Makes the shell capability over one store, one confinement, one live view
    /// of the output, and one default working directory.
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
    ///   - sandbox: The confinement each command spawns under. The default,
    ///     `nil`, starts the shell directly, with no confinement and with no
    ///     step of confinement on the path at all — see `ShellRunner.sandbox`,
    ///     which states why that is not `UnconfinedSandbox`.
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
        sandbox: (any CommandSandbox)? = nil,
        outputChunkStream: ShellOutputChunkStream? = nil,
        defaultWorkingDirectory: URL? = nil
    ) throws {
        let state: ShellState
        if let storeDirectory {
            state = try ShellState(preferredDirectory: storeDirectory)
        } else {
            state = try ShellState()
        }

        // The runner carries the store, the confinement, the live view and the
        // default directory to the run plane. `Execute` is configured with a
        // runner and with nothing else, which is why the two content-plane
        // verbs take the store straight from here rather than reaching through
        // one.
        var runner = ShellRunner(
            state: state, outputChunkStream: outputChunkStream, sandbox: sandbox)
        runner.defaultWorkingDirectory = defaultWorkingDirectory?.path

        self.tools = [
            Execute(runner: runner),
            GetLines(state: state),
            GrepHistory(state: state),
        ]
    }
}
