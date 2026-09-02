import Foundation
import FoundationModelsRouter
import Synchronization

@testable import FoundationModelsMultitool

// MARK: - The one seam a gated harness has onto the run plane of a live session
//
// `ToolContext.current` is the ONLY route to a session's run plane. Router
// publishes no `backgroundRuns`, no `wait(completionToken:)` and no
// `cancel(completionToken:)` on `RoutedSession`; `RoutedSessionActor` and every
// run-plane member of `SessionMailbox` are internal to that package. So a
// scenario that has to read what a live session's shell run is doing needs a
// tool to hand it a context, and there is exactly one place a tool does that.
//
// `Execute` asks its sandbox to `preflight` from INSIDE its own call, before it
// spawns anything (`CommandSandbox.preflight`, whose own documentation names
// that verb as its caller). `ToolContext.current` there is the SHELL run's own
// context — its completion token, its session and its mailbox. The root
// package's `RegisteredJournalOpTests` already reads the journal op through this
// same seam, with the same shape of probe.
//
// The seam is the shipped configuration and not a back door:
// `MultiTool.Builder.withShell(storeDirectory:sandbox:outputChunkStream:defaultWorkingDirectory:)` takes
// the sandbox a host configures, so a scenario that passes this probe is running
// the surface a host runs, with the confinement a host chose — here, none.

/// A `CommandSandbox` that confines nothing and keeps the ambient
/// ``FoundationModelsRouter/ToolContext`` of each `tools.shell.execute` run.
///
/// `wrap` gives the shell invocation back exactly as it came in, so a command
/// starts as it starts with no sandbox at all and the probe changes only what is
/// observed. That matters twice over here: a gated run must not depend on
/// `/usr/bin/sandbox-exec` being present, and a Seatbelt profile refusing the
/// scenario's command would end the turn instead of the run this suite grades.
///
/// A locked reference type rather than an actor, because `wrap` is a
/// SYNCHRONOUS requirement of `CommandSandbox`, which an actor answers only from
/// outside its own isolation. It is also the shape a runner needs: a
/// `ShellRunner` is a value and is copied, so a value probe would record into a
/// copy the caller never reads.
final class ShellRunContextProbe: CommandSandbox {

    /// The ambient context of each run that consulted this probe, in call order.
    private let observed = Mutex<[ToolContext]>([])

    /// The ambient context of each run that consulted this probe, in call order.
    ///
    /// A run that consulted the probe under no ambient context at all is not
    /// recorded: it has no completion token, so it names nothing on the run
    /// plane and there is nothing for a scenario to read it by.
    var observedContexts: [ToolContext] {
        observed.withLock { $0 }
    }

    /// Keeps the ambient context of this run, and proves nothing about the
    /// confinement.
    ///
    /// - Parameters:
    ///   - workingDirectory: Not read — nothing is proved.
    ///   - temporaryDirectory: Not read — nothing is proved.
    func preflight(workingDirectory: String, temporaryDirectory: String) async {
        guard let context = ToolContext.current else { return }
        observed.withLock { $0.append(context) }
    }

    /// Gives back `shellPath` and `shellArguments` unchanged.
    ///
    /// - Parameters:
    ///   - shellPath: The absolute path of the shell to run.
    ///   - shellArguments: The arguments of that shell.
    ///   - workingDirectory: Not read — no confinement is applied.
    ///   - temporaryDirectory: Not read — no confinement is applied.
    /// - Returns: The shell invocation as it came in.
    func wrap(
        shellPath: String,
        shellArguments: [String],
        workingDirectory: String,
        temporaryDirectory: String
    ) -> SandboxedInvocation {
        SandboxedInvocation(executable: shellPath, arguments: shellArguments)
    }
}
