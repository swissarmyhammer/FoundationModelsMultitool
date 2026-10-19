import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing
import ULID
import os

@testable import FoundationModelsMultitool

/// The `(tool, op)` pair a `ToolCallWitness` sees for each inner `tools.*`
/// call of one `runCode` snippet.
///
/// FoundationModelsRouter counts the file edits and the code reads of a root
/// session through `ToolCallWitness`, and its default matchers key on the op
/// of each inner call. Router does not depend on this package, so it cannot
/// read the real strings itself. This suite pins them.
///
/// ## How the pair is formed
///
/// `MultiTool.makeLiveTools(for:)` gives each live verb the
/// `APISurface.Entry.journalOp` of its entry, `"<verb> <group>"`. The binding
/// of a `tools.*` call mounts the verb through `ToolContext.mount(_:op:as:)`
/// with that op, and the site of that mount reports the start of the call to
/// the witness of the session: `tool` is the bare `Tool.name` of the verb, and
/// `op` is the op of the mount.
///
/// ## The mount
///
/// The witness stands on the `MountSite` of the session, and the outer
/// `MultiTool` is mounted on that site through `ToolMounting.makeWrapped`, as
/// a Router session mounts it. A site never reports its own outer calls, so
/// the outer `runCode` call is not among the witnessed calls.
///
/// `MultiTool` declares a background mount, so the outer call waits only for
/// its settle period. A period of `0` sends the snippet to the background at
/// once on every machine. The test then waits on the run plane for the end of
/// the run, and reads the witness after it.
@Suite("InnerCallWitnessOp", .ownsTemporaryDirectories)
struct InnerCallWitnessOpTests {

    /// Owns the temporary directories this test makes, so they go away when the
    /// test ends rather than collecting in `$TMPDIR`.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test, so a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "inner-call-witness-op-tests"

    /// The file the snippet reads and then edits.
    private static let seededFileName = "code.txt"

    /// The seeded content of ``seededFileName``: three lines, and the middle
    /// one is the edit target.
    private static let seededContent = "one\ntwo\nthree\n"

    /// The `find` text of the edit.
    private static let findText = "two"

    /// The `replace` text of the edit.
    private static let replacementText = "TWO"

    /// The group the stub code-reading verb registers under, the name the
    /// Router expects a code-context host to register.
    private static let codeContextGroup = "code_context"

    /// The `Tool.name` of the stub code-reading verb.
    private static let getSymbolVerb = "getSymbol"

    /// The `(tool, op)` pairs the witness must see, in call order: the bare
    /// verb, and the `"<verb> <group>"` op of its registration.
    private static let expectedPairs: [WitnessedPair] = [
        WitnessedPair(tool: "read", op: "read files"),
        WitnessedPair(tool: "edit", op: "edit files"),
        WitnessedPair(tool: "getSymbol", op: "getSymbol code_context"),
    ]

    @Test("a witness sees each inner tools.* call of a runCode snippet as its bare verb and its \"<verb> <group>\" op")
    func aWitnessSeesEachInnerCallAsItsVerbAndOp() async throws {
        let session = WitnessedSession()
        let terminal = try await session.run(Self.snippet(), over: try makeRegistry())

        #expect(terminal.kind == .completed, "the run ended with: \(terminal.detail)")
        let calls = session.witness.calls
        #expect(calls.map { WitnessedPair(tool: $0.tool, op: $0.op) } == Self.expectedPairs)
        #expect(calls.allSatisfy { $0.sessionID == session.sessionID })
    }

    // MARK: - The ground of one test

    /// The snippet that reads the seeded file, edits it, and calls the stub
    /// code-reading verb, in that order. Each call waits for the one before
    /// it, so the witness sees them in that order.
    ///
    /// - Returns: The snippet source.
    private static func snippet() -> String {
        """
        const read = await tools.files.read({ path: "\(seededFileName)" });
        if (read.correction) { return read.correction; }
        const edited = await tools.files.edit({ path: "\(seededFileName)", find: "\(findText)", replace: "\(replacementText)" });
        if (edited.correction) { return edited.correction; }
        const symbol = await tools.\(codeContextGroup).\(getSymbolVerb)();
        return { status: edited.status, symbol };
        """
    }

    /// Builds a registry that holds the files capability over a temporary root
    /// with one seeded file, and the stub code-reading verb under its group.
    ///
    /// - Returns: The rendered catalog paired with the live verbs.
    /// - Throws: What `makeDirectory(prefix:)`, the seed write or
    ///   `buildRegistry()` throws.
    private func makeRegistry() throws -> MultiTool.Registry {
        let root = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        try Data(Self.seededContent.utf8)
            .write(to: root.appendingPathComponent(Self.seededFileName, isDirectory: false))
        return try MultiTool.Builder()
            .withFiles(root: root)
            .addGroup(named: Self.codeContextGroup, [AmbientRecordingTool(name: Self.getSymbolVerb)])
            .buildRegistry()
    }
}

/// The two strings of one ``WitnessedToolCall`` that the Router keys on.
private struct WitnessedPair: Equatable, CustomStringConvertible {
    /// The name of the called tool.
    let tool: String

    /// The op of the mount of the call.
    let op: String

    /// The pair as `(tool, op)`, so a failed comparison reads plainly.
    var description: String {
        "(\(tool), \(op))"
    }
}

/// A `ToolCallWitness` that keeps each call it sees, in report order.
///
/// A locked class rather than an actor, because
/// `toolCallWillBegin(_:)` is a synchronous requirement that must return at
/// once.
private final class RecordingWitness: ToolCallWitness {
    /// Each call this witness saw, in report order.
    private let callsBox = OSAllocatedUnfairLock<[WitnessedToolCall]>(initialState: [])

    /// Each call this witness saw, in report order.
    var calls: [WitnessedToolCall] {
        callsBox.withLock { $0 }
    }

    /// Keeps `call`.
    ///
    /// - Parameter call: The call that begins.
    func toolCallWillBegin(_ call: WitnessedToolCall) {
        callsBox.withLock { $0.append(call) }
    }
}

/// One session that a test owns: its run plane, its sink, its witness, and
/// the mount site that carries the witness.
private struct WitnessedSession {
    /// The id of the session.
    let sessionID = ULID()

    /// The run plane of the session.
    let runPlane = RunPlane()

    /// The sink of the session.
    let sink = RecordingEventSink()

    /// The witness of each inner call of the session.
    let witness = RecordingWitness()

    /// The site each outer call of the session mounts on.
    let site: MountSite

    /// Makes the session, with ``witness`` on its site.
    init() {
        site = MountSite(sessionID: sessionID, runPlane: runPlane, sink: sink, callWitness: witness)
    }

    /// Mounts a `MultiTool` over `registry` on ``site``, calls it once with
    /// `code`, and waits for the end of the run.
    ///
    /// - Parameters:
    ///   - code: The snippet to run.
    ///   - registry: The catalog the snippet's `tools.*` calls dispatch into.
    /// - Returns: The terminal event of the run.
    /// - Throws: When the mount is not a `runCode` tool, when the call does
    ///   not answer with a pending envelope, or when the run does not settle.
    func run(_ code: String, over registry: MultiTool.Registry) async throws -> OperationEvent {
        let multiTool = MultiTool(
            registry: registry, configuration: MultiToolConfiguration(inlineSettleGrace: 0))
        let mounted = try #require(
            ToolMounting.makeWrapped(tool: multiTool, site: site, configuration: .synchronous)
                as? any Tool<RunCodeArguments, String>)
        let output = try await mounted.call(arguments: RunCodeArguments(code: code))
        try #require(PendingRunEnvelope.isRendered(text: output), "answer was: \(output)")
        let token = try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(output.utf8)).completionToken
        return try await TerminalDetail.settledEvent(of: token, on: runPlane)
    }
}
