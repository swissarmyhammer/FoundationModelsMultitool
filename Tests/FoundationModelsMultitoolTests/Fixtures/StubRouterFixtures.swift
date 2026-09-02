import Foundation
import FoundationModels
import FoundationModelsRouter

// MARK: - A router over a stub model
//
// The fixtures of this target need a real `ToolContext`: the run plane, the
// elicitation round trip and the mount arbitration all live on one. Router
// makes no context publicly — `ToolContext` has no public initializer, and
// `SessionMailbox`, `ToolMounting` and the `OperationEventSink` typealias are
// all internal to that package.
//
// The route that works is to take a real context from a real session. Router
// publishes every seam a session needs, thus this file stands up a router over
// a model that loads nothing and generates nothing:
//
//   ProbeLoader (ModelLoader) -> StubLLMContainer (LoadedLLMContainer)
//     -> ToolCallingBackend (LanguageModelSessionBackend)
//
// A session made over that backend mounts each tool through Router's own
// engine, and the engine binds `ToolContext.$current` around the call. A tool
// that reads `ToolContext.current` from inside its own `call(arguments:)`
// therefore receives a genuine context, over a genuine mailbox, with no model
// and no download. The router session measured the same shape at 0.029 s.
//
// **The container writes all four session factories on purpose.** The public
// default of `makeSession(instructions:tools:)` DROPS `tools` and forwards to
// `makeSession(instructions:)`. A container that writes only the two required
// factories gets a backend with an empty tool list, and a fixture over it
// passes while measuring nothing.

/// The arguments the context-capturing tool takes.
///
/// Its own type rather than a shared one: ``ToolCallingBackend`` finds the tool
/// to call by casting to `any Tool<CaptureArguments, String>`, so the type is
/// how the backend recognizes it.
@Generable
struct CaptureArguments {
    /// Unread. A `@Generable` argument type needs one field.
    var note: String
}

/// Where the captured context is put, so the tool can hand it out.
///
/// A `final class` rather than a value: the tool is a `struct` the engine
/// wraps and copies, and the capture has to survive that.
final class CapturedContextBox: @unchecked Sendable {
    /// The context the tool read, or `nil` before the call ran.
    private(set) var context: ToolContext?

    /// Records the context one call observed.
    ///
    /// - Parameter context: The context the tool read.
    func capture(_ context: ToolContext?) {
        self.context = context
    }
}

/// A tool whose whole job is to read `ToolContext.current` and put it in a box.
struct ContextCaptureTool: Tool {
    let name = "captureContext"
    let description = "Records the ambient tool context."

    /// Where the read context is put.
    let box: CapturedContextBox

    func call(arguments: CaptureArguments) async throws -> String {
        box.capture(ToolContext.current)
        return "captured"
    }
}

/// A session backend that calls the first tool it can rather than generating.
///
/// The tools it receives are already wrapped by Router's mount, and a wrapper
/// preserves the wrapped tool's `Arguments` and `Output`. Thus the cast below
/// still matches, and calling through it runs the wrapper that binds
/// `ToolContext.$current`. That binding is the whole point of this type.
final class ToolCallingBackend: LanguageModelSessionBackend, @unchecked Sendable {
    /// The mounted tools this backend was made over.
    private let tools: [any Tool]

    /// What the session records as its transcript.
    private var entries: [Transcript.Entry] = []

    /// Makes a backend over `tools`.
    ///
    /// - Parameter tools: The mounted tools, already wrapped by the engine.
    init(tools: [any Tool]) {
        self.tools = tools
    }

    /// Calls the first tool that takes ``CaptureArguments``.
    ///
    /// - Returns: What that tool answered, or a marker when none matched.
    /// - Throws: Whatever the tool throws.
    private func callTool() async throws -> String {
        for tool in tools {
            if let typed = tool as? any Tool<CaptureArguments, String> {
                return try await typed.call(arguments: CaptureArguments(note: "capture"))
            }
        }
        return "no tool"
    }

    func respond(to prompt: String, maxTokens: Int?) async throws -> String {
        let answer = try await callTool()
        record(prompt: prompt, answer: answer)
        return answer
    }

    func respond(
        to prompt: String, following grammar: Grammar, maxTokens: Int?
    ) async throws -> String {
        try await respond(to: prompt, maxTokens: maxTokens)
    }

    func streamResponse(
        to prompt: String, maxTokens: Int?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let answer = try await self.callTool()
                    self.record(prompt: prompt, answer: answer)
                    continuation.yield(answer)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func makeFork() -> any LanguageModelSessionBackend {
        ToolCallingBackend(tools: tools)
    }

    func transcriptEntries() -> [Transcript.Entry] { entries }

    func usageTokenCounts() -> (input: Int, output: Int)? { (1, 1) }

    /// Appends one prompt and one response to the recorded transcript.
    private func record(prompt: String, answer: String) {
        entries.append(
            .prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: prompt))])))
        entries.append(
            .response(
                Transcript.Response(segments: [.text(Transcript.TextSegment(content: answer))])))
    }
}

/// A resident model that hands every session a ``ToolCallingBackend``.
///
/// All four factories are written out. See the file comment: the public
/// default of `makeSession(instructions:tools:)` drops `tools`.
struct StubLLMContainer: LoadedLLMContainer {
    func makeSession(instructions: String?) -> any LanguageModelSessionBackend {
        ToolCallingBackend(tools: [])
    }

    func makeSession(
        instructions: String?, tools: [any Tool]
    ) -> any LanguageModelSessionBackend {
        ToolCallingBackend(tools: tools)
    }

    func makeSession(transcript: Transcript) -> any LanguageModelSessionBackend {
        ToolCallingBackend(tools: [])
    }

    func makeSession(
        transcript: Transcript, tools: [any Tool]
    ) -> any LanguageModelSessionBackend {
        ToolCallingBackend(tools: tools)
    }
}

/// An embedding model that answers a constant vector.
struct StubEmbeddingContainer: LoadedEmbeddingContainer {
    let dimension = 8

    func embed(texts: [String]) async throws -> [[Float]] {
        texts.map { _ in [Float](repeating: 0.5, count: 8) }
    }
}

/// A loader that downloads nothing and loads the stub containers.
struct StubModelLoader: ModelLoader {
    func loadLLM(
        ref: ModelRef,
        slot: ModelSlot,
        context: Int,
        reporting: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> any LoadedLLMContainer {
        reporting(DownloadProgress(bytesDownloaded: 1, bytesTotal: 1))
        return StubLLMContainer()
    }

    func loadEmbedder(
        ref: ModelRef,
        slot: ModelSlot,
        reporting: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> any LoadedEmbeddingContainer {
        reporting(DownloadProgress(bytesDownloaded: 1, bytesTotal: 1))
        return StubEmbeddingContainer()
    }

    func preload(container: any LoadedModelContainer) async throws {}
}

/// A machine large enough that slot fitting never becomes a variable.
struct StubMachine: MachineProbe {
    let chip = "Apple Stub"
    let totalRAM: Int64 = 64 << 30
    let recommendedMaxWorkingSetSize: Int64 = 48 << 30
}

/// A session over the stub model, and a real ``ToolContext`` taken from inside
/// one of its tool calls.
///
/// The two are handed out together because the fixtures need both and they
/// must belong to each other: the context reads the run plane of this
/// session's mailbox, and the session is what answers an elicitation the
/// context raised.
struct StubRun {
    /// The session every run and every elicitation belongs to.
    let session: RoutedSession

    /// A real context over that session's mailbox.
    let context: ToolContext

    /// Where every recorded transcript event of this session is kept.
    let recorder: CollectingTranscriptRecorder
}

/// A `TranscriptRecorder` that keeps every partial in memory.
///
/// The stub router is given one because `Router.init(recorder:)` defaults to
/// `nil`, and with no recorder nothing is journaled at all — which makes
/// `TranscriptEvent.merged(under:)` read an empty set and every event
/// assertion silently observe nothing.
actor CollectingTranscriptRecorder: TranscriptRecorder {
    /// Every partial this recorder was handed, in arrival order.
    private(set) var partials: [TranscriptEvent.Partial] = []

    func append(_ partial: TranscriptEvent.Partial, to directory: URL?) async {
        partials.append(partial)
    }

    /// Drops everything recorded so far.
    ///
    /// Called once the stub run is stood up: capturing the context takes a real
    /// tool call, and that call posts operation events of its own. A test that
    /// read them would see the setup's terminal event ahead of its own, which
    /// is what made four correlation assertions fail.
    func reset() {
        partials.removeAll()
    }

    /// Every `OperationEvent` the recorded entries carry, in arrival order.
    ///
    /// A structure segment that is not an operation event fails to decode and
    /// is dropped, so this never names Router's internal segment type or its
    /// schema name.
    var operationEvents: [OperationEvent] {
        partials.flatMap { partial in
            (partial.entry?.segments ?? []).compactMap { segment -> OperationEvent? in
                guard case .structure(_, _, let contentJSON) = segment else { return nil }
                return try? JSONDecoder().decode(
                    OperationEvent.self, from: Data(contentJSON.utf8))
            }
        }
    }
}

/// Stands up a router over the stub model and takes a real ``ToolContext``
/// out of a tool call on it.
///
/// - Parameter directory: Where the router caches and records. A fresh
///   temporary directory per call keeps runs of one suite apart.
/// - Returns: The session and its context.
/// - Throws: Whatever resolving the profile throws.
func makeStubRun(in directory: URL = FileManager.default.temporaryDirectory
    .appendingPathComponent("multitool-stub-\(ULID.generate())")) async throws -> StubRun
{
    let recorder = CollectingTranscriptRecorder()
    let router = Router(
        cacheDir: directory,
        recorder: recorder,
        probe: StubMachine(),
        metadataSource: StubMetadata(),
        loader: StubModelLoader()
    )
    let profile = try await router.resolve(
        profile: ProfileDefinition(
            name: "stub",
            description: "the stub profile these fixtures run on",
            standard: ["stub/standard"],
            flash: ["stub/flash"],
            embedding: ["stub/embedding"]
        ),
        reporting: ResolutionProgress()
    )
    let box = CapturedContextBox()
    let session = profile.standard.makeSession(
        instructions: nil, tools: [ContextCaptureTool(box: box)])
    _ = try await session.respond(to: "capture", maxTokens: nil)
    guard let context = box.context else {
        throw StubRunFailure.noContextCaptured
    }
    // The capture call above is real, and it posted its own events. Drop them
    // so a test reads only what it caused.
    await recorder.reset()
    return StubRun(session: session, context: context, recorder: recorder)
}

/// What standing up a stub run could not do.
enum StubRunFailure: Error, CustomStringConvertible {
    /// The capture tool ran but read no ambient context, or never ran at all.
    case noContextCaptured

    var description: String {
        switch self {
        case .noContextCaptured:
            return
                "the capture tool read no ToolContext — the mount did not bind one, or the "
                + "backend never called the tool"
        }
    }
}

/// Metadata for a model small enough to fit ``StubMachine`` trivially.
///
/// The numbers are the ones the router session measured as sufficient. The
/// lower bound is unprobed: a resolve that starts failing after these shrink
/// is this, and not a fault in the caller.
struct StubMetadata: MetadataSource {
    func fetchRawMetadata(repo: String, revision: String?) async throws -> RawRepoMetadata {
        RawRepoMetadata(
            configJSON: Data(
                """
                {"num_hidden_layers":2,"num_attention_heads":8,\
                "num_key_value_heads":2,"head_dim":16,"hidden_size":128}
                """.utf8),
            treeJSON: Data(
                """
                [{"type":"file","path":"model.safetensors","size":10000000}]
                """.utf8))
    }
}

/// The terminal `OperationEvent` of each settled run of `session`, read off
/// the session's own event stream.
///
/// `SessionEvent.runSettled` is the only public route to a run's terminal
/// event: a host cannot inject an `OperationEventSink`, because nothing public
/// of Router accepts one.
///
/// - Parameters:
///   - session: The session whose runs to read.
///   - count: How many settled runs to wait for.
///   - seconds: How long to wait before giving up.
/// - Returns: The terminal events, in arrival order, or fewer on a timeout.
func settledEvents(
    on session: RoutedSession, count: Int, seconds: Double = 10
) async -> [OperationEvent] {
    // The deadline races the stream rather than being checked inside it. A
    // `for await` over `streamSessionEvents()` suspends until the next event,
    // and the stream does not end on its own, so a deadline tested in the loop
    // body is never reached when no event arrives — the call blocks forever.
    await withTaskGroup(of: [OperationEvent]?.self) { group in
        group.addTask {
            var settled: [OperationEvent] = []
            for await event in await session.streamSessionEvents() {
                if case .runSettled(let operation) = event { settled.append(operation) }
                if settled.count >= count { break }
            }
            return settled
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        var collected: [OperationEvent] = []
        for await result in group {
            if let result { collected = result }
            group.cancelAll()
            break
        }
        return collected
    }
}

/// Every `OperationEvent` the runs of `run` recorded, read off the session's
/// own recorded transcript.
///
/// This is the route to a `.progress` or `.elicitation` event. A host cannot
/// inject an `OperationEventSink` — nothing public of Router accepts one — and
/// `SessionEvent` carries only the terminal event, as `runSettled`. What a host
/// CAN supply is a `TranscriptRecorder`, and every drained event is journaled
/// through it as a structured segment.
///
/// - Parameters:
///   - run: The stub run whose transcript to read.
///   - kind: The one event kind to keep, or `nil` for every kind.
/// - Returns: The recorded events, in transcript order.
func recordedOperationEvents(
    of run: StubRun, ofKind kind: OperationEventKind? = nil
) async -> [OperationEvent] {
    let events = await run.recorder.operationEvents
    guard let kind else { return events }
    return events.filter { $0.kind == kind }
}

/// The terminal `OperationEvent`s of `session` that carry `correlationID`.
///
/// A snippet that makes an inner call settles more than one run, and the
/// stream carries each. A test that wants one run's terminal asks for it by
/// correlation rather than by arrival position.
///
/// Subscribe BEFORE the run settles: `streamSessionEvents()` is live and has
/// no replay.
///
/// - Parameters:
///   - session: The session whose runs to read.
///   - correlationID: The run whose terminal to keep.
///   - count: How many matching terminals to wait for.
///   - seconds: How long to wait before giving up.
/// - Returns: The matching terminal events, in arrival order.
func settledEvents(
    on session: RoutedSession, correlationID: String, count: Int = 1, seconds: Double = 10
) async -> [OperationEvent] {
    await withTaskGroup(of: [OperationEvent]?.self) { group in
        group.addTask {
            var settled: [OperationEvent] = []
            for await event in await session.streamSessionEvents() {
                guard case .runSettled(let operation) = event else { continue }
                guard operation.correlationID == correlationID else { continue }
                settled.append(operation)
                if settled.count >= count { break }
            }
            return settled
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        var collected: [OperationEvent] = []
        for await result in group {
            if let result { collected = result }
            group.cancelAll()
            break
        }
        return collected
    }
}

/// The recorded `OperationEvent`s of `run` of one kind, on the runs
/// `correlationIDs` name, read one time with no wait.
///
/// A `.progress` event a verb posts through `ToolContext.post(_:)` is
/// journaled before `post` returns: `SessionOutbox.post(event:)` awaits its
/// own journal write. Thus a test that reads right after the call that posted
/// the event needs no poll, and a read here that comes back short is a fault
/// in the route and not a race in the test. The polling variant below is for
/// the sweep `RoutedSession.close()` runs on a task of its own.
///
/// - Parameters:
///   - run: The stub run whose transcript to read.
///   - kind: The one event kind to keep.
///   - correlationIDs: The runs to keep, by `correlationID`.
/// - Returns: The matching events, in transcript order.
func recordedOperationEvents(
    of run: StubRun, ofKind kind: OperationEventKind, correlatedTo correlationIDs: Set<String>
) async -> [OperationEvent] {
    await recordedOperationEvents(of: run, ofKind: kind).filter { correlationIDs.contains($0.correlationID) }
}

/// The recorded `OperationEvent`s of `run` of one kind, waited for until at
/// least `count` of them have been journaled.
///
/// A single read races the journal. `RoutedSession.close()` sweeps and journals
/// the terminal events it produces, but the write reaches the recorder on its
/// own task, so a read taken the instant `close()` returns can see fewer than
/// the sweep produced. It passed on a warm machine and failed on CI, which is
/// the shape of that race exactly.
///
/// - Parameters:
///   - run: The stub run whose journal to read.
///   - kind: The event kind to keep.
///   - count: How many to wait for.
/// - Returns: The events, once `count` of them are there, or whatever was
///   journaled when the deadline passed.
///   - correlatedTo: The runs to keep, by `correlationID`, or `nil` for every
///     run of the session.
///
/// **Pass `correlatedTo` for anything that sweeps.** `RoutedSession.close()`
/// settles EVERY background run the session holds, and one of those is the
/// capture run ``makeStubRun(in:)`` makes to obtain its `ToolContext`. That run
/// is fixture scaffolding rather than anything a test asked for, and whether it
/// is still on the plane at sweep time is a matter of timing: it had settled on
/// a warm machine and had not on CI, which is how it reached an assertion as a
/// second terminal nobody expected.
func recordedOperationEvents(
    of run: StubRun,
    ofKind kind: OperationEventKind,
    correlatedTo correlationIDs: Set<String>? = nil,
    awaiting count: Int
) async -> [OperationEvent] {
    func matching() async -> [OperationEvent] {
        guard let correlationIDs else { return await recordedOperationEvents(of: run, ofKind: kind) }
        return await recordedOperationEvents(of: run, ofKind: kind, correlatedTo: correlationIDs)
    }
    let deadline = ContinuousClock.now.advanced(by: TestPoll.deadline)
    var events = await matching()
    while events.count < count, ContinuousClock.now < deadline {
        try? await Task.sleep(for: TestPoll.interval)
        events = await matching()
    }
    return events
}
