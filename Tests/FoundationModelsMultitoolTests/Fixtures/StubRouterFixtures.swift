import Foundation
import FoundationModels
import FoundationModelsExtras

// `Router.useRunClock(_:)` is internal: only a test gives a router its run
// clock. A debug build compiles Router with testing enabled.
@testable import FoundationModelsRouter
@testable import MultitoolTestSupport

// MARK: - A router over a stub model
//
// The fixtures of this target need a real `ToolContext`: the run plane, the
// elicitation round trip and the mount arbitration all live on one. Router
// makes no context publicly — `ToolContext` has no public initializer, and
// the run plane of a session, `ToolMounting` and the `OperationEventSink` typealias are
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
// therefore receives a genuine context, over a genuine run plane, with no model
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
    /// Counts one token per word. Router asks a container for a counter
    /// since Router's compaction work; the stub model has no tokenizer.
    let tokenCounter: any TokenCounter = StubWordTokenCounter()

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

/// The ``TokenCounter`` of ``StubLLMContainer``: one token per word.
///
/// A word is one run of characters between whitespace. A transcript counts
/// the words of each entry's description. `prefix(of:tokens:)` keeps the
/// first `limit` words, joined with one space.
struct StubWordTokenCounter: TokenCounter {
    func count(_ text: String) -> Int {
        Self.words(of: text).count
    }

    func count(_ transcript: Transcript) throws -> Int {
        transcript.reduce(0) { $0 + count(String(describing: $1)) }
    }

    func prefix(of text: String, tokens limit: Int) -> String {
        guard count(text) > limit else { return text }
        return Self.words(of: text).prefix(max(limit, 0)).joined(separator: " ")
    }

    /// The runs of characters between whitespace in `text`.
    private static func words(of text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace)
    }
}

/// An embedding model that answers a constant vector.
struct StubEmbeddingContainer: LoadedEmbeddingContainer {
    let dimension = 8

    func embed(texts: [String]) async throws -> [[Float]] {
        texts.map { _ in [Float](repeating: 0.5, count: 8) }
    }
}

/// The model reference of the `standard` slot of the stub profile, when a
/// test gives none of its own.
let stubStandardModel: ModelRef = "stub/standard"

/// The model reference of the `embedding` slot of the stub profile.
let stubEmbeddingModel: ModelRef = "stub/embedding"

/// The name prefix of the folder in which a stub router caches and records,
/// when a test gives no folder of its own.
///
/// `TestSupport.makeTemporaryDirectory(named:)` makes the folder, thus the
/// `ownsTemporaryDirectories` trait of the suite removes it when the test
/// ends, also when the test throws.
let stubRouterDirectoryPrefix = "multitool-stub"

/// A loader that downloads nothing and loads the stub containers.
struct StubModelLoader: ModelLoader {
    /// The generation container every `loadLLM` call hands out. The default
    /// is ``StubLLMContainer``; a test that must script its own backend gives
    /// its own container.
    var container: any LoadedLLMContainer = StubLLMContainer()

    func loadLLM(
        ref: ModelRef,
        slot: ModelSlot,
        context: Int,
        reporting: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> any LoadedLLMContainer {
        reporting(DownloadProgress(bytesDownloaded: 1, bytesTotal: 1))
        return container
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
/// session, and the session is what answers an elicitation the
/// context raised.
struct StubRun {
    /// The session every run and every elicitation belongs to.
    let session: any RoutedSession

    /// A real context over the run plane of that session.
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
///
/// A test that must wait for an event waits with
/// ``waitUntil(_:)``: ``append(_:to:)`` resumes each wait whose condition
/// becomes true. Nothing reads a clock or polls.
actor CollectingTranscriptRecorder: TranscriptRecorder {
    /// One wait for a condition on the recorded events.
    private struct EventWaiter {
        /// The condition that ends the wait.
        let isMet: @Sendable ([OperationEvent]) -> Bool

        /// Resumes the wait: `true` when the condition is met, `false` when
        /// the task was cancelled first.
        let continuation: CheckedContinuation<Bool, Never>
    }

    /// Every partial this recorder was handed, in arrival order.
    private(set) var partials: [TranscriptEvent.Partial] = []

    /// Each wait that did not end, by id.
    private var waiters: [Int: EventWaiter] = [:]

    /// The id that the next wait gets.
    private var nextWaiterID = 0

    func append(_ partial: TranscriptEvent.Partial, to directory: URL?) async {
        partials.append(partial)
        resumeMetWaiters()
    }

    /// Waits until `isMet` is true for the recorded operation events.
    ///
    /// The condition is tested now, and again after each append. The wait
    /// reads no clock.
    ///
    /// - Parameter isMet: The condition on every recorded operation event, in
    ///   arrival order. It must not block.
    /// - Returns: `true` when the condition is met, `false` when the task was
    ///   cancelled first.
    func waitUntil(_ isMet: @escaping @Sendable ([OperationEvent]) -> Bool) async -> Bool {
        if isMet(operationEvents) {
            return true
        }
        let id = nextWaiterID
        nextWaiterID += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                    return
                }
                waiters[id] = EventWaiter(isMet: isMet, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancelWait(id: id) }
        }
    }

    /// Resumes each wait whose condition is true now.
    private func resumeMetWaiters() {
        guard !waiters.isEmpty else { return }
        let events = operationEvents
        for (id, waiter) in waiters where waiter.isMet(events) {
            waiters.removeValue(forKey: id)
            waiter.continuation.resume(returning: true)
        }
    }

    /// Ends one wait with `false`, when it did not end yet.
    ///
    /// - Parameter id: The id of the wait.
    private func cancelWait(id: Int) {
        waiters.removeValue(forKey: id)?.continuation.resume(returning: false)
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

/// Stands up a router over the stub model and makes a session that mounts `tools`.
///
/// The session is the whole seam a host holds. ``ToolCallingBackend`` calls the
/// first tool of the list that takes ``CaptureArguments``, thus a test drives
/// one REAL tool call — a live run, with a live ``ToolContext`` bound around it
/// — by asking the session to respond. ``makeStubRun(in:)`` below is one caller,
/// and a test that must read a run's own `SessionEvent` stream is the other:
/// `ToolCallReport` reaches a host on that stream alone.
///
/// - Parameters:
///   - tools: The tools the session mounts.
///   - loader: The loader the router loads its models through. The default
///     hands out ``StubLLMContainer``.
///   - standardModel: The model reference of the `standard` slot. See
///     ``makeStubProfile(recorder:loader:standardModel:in:)``.
///   - directory: Where the router caches and records. A fresh temporary
///     directory per call keeps runs of one suite apart.
///   - runClock: The run clock of the session, or `nil` for the real time.
///     See ``makeStubProfile(recorder:loader:standardModel:in:runClock:)``.
/// - Returns: The session, and the recorder of its transcript.
/// - Throws: Whatever resolving the profile throws.
func makeStubSession(
    mounting tools: [any Tool],
    loader: StubModelLoader = StubModelLoader(),
    standardModel: ModelRef = stubStandardModel,
    in directory: URL = TestSupport.makeTemporaryDirectory(named: stubRouterDirectoryPrefix),
    runClock: (any RunClock)? = nil
) async throws -> (session: any RoutedSession, recorder: CollectingTranscriptRecorder) {
    let recorder = CollectingTranscriptRecorder()
    let profile = try await makeStubProfile(
        recorder: recorder, loader: loader, standardModel: standardModel, in: directory, runClock: runClock)
    return (profile.standard.makeSession(instructions: nil, tools: tools), recorder)
}

/// Stands up a router over the stub model and resolves the stub profile on it.
///
/// The profile is the whole seam a host resolves: its `standard` and `flash`
/// handles vend sessions over ``ToolCallingBackend``, and its `embedding`
/// handle answers ``StubEmbeddingContainer``'s constant vector.
///
/// - Parameters:
///   - recorder: Where the router journals every transcript event. Defaults
///     to a fresh recorder no test reads.
///   - loader: The loader the router loads its models through. The default
///     hands out ``StubLLMContainer``.
///   - standardModel: The model reference of the `standard` slot. Router
///     keeps a loaded model in the process-wide `ModelPool.shared` by its
///     reference, so a test that gives its own container must also give a
///     reference no other test loads. Otherwise the pool hands it the
///     container another test loaded first.
///   - directory: Where the router caches. A fresh temporary directory per
///     call keeps runs of one suite apart. The default folder belongs to the
///     test that runs now, thus its suite needs the
///     `ownsTemporaryDirectories` trait (see ``stubRouterDirectoryPrefix``).
///   - runClock: The run clock of each session of the profile: the timeout
///     of each run, the settle period of each background call, and
///     `ToolContext.wait(completionToken:seconds:)`. `nil` keeps the real
///     time. A test that gives a `ManualRunClock` ends those timers with
///     `ManualRunClock.advance(by:)` in a fixed order, and reads no real time.
/// - Returns: The resolved profile.
/// - Throws: Whatever resolving the profile throws.
func makeStubProfile(
    recorder: CollectingTranscriptRecorder = CollectingTranscriptRecorder(),
    loader: StubModelLoader = StubModelLoader(),
    standardModel: ModelRef = stubStandardModel,
    in directory: URL = TestSupport.makeTemporaryDirectory(named: stubRouterDirectoryPrefix),
    runClock: (any RunClock)? = nil
) async throws -> LanguageModelProfile {
    let router = Router(
        cacheDir: directory,
        recorder: recorder,
        probe: StubMachine(),
        metadataSource: StubMetadata(),
        loader: loader
    )
    if let runClock {
        await router.useRunClock(runClock)
    }
    return try await router.resolve(
        profile: ProfileDefinition(
            name: "stub",
            description: "the stub profile these fixtures run on",
            standard: [standardModel],
            flash: ["stub/flash"],
            embedding: [stubEmbeddingModel]
        ),
        reporting: ResolutionProgress()
    )
}

/// Stands up a router over the stub model and takes a real ``ToolContext``
/// out of a tool call on it.
///
/// - Parameters:
///   - directory: Where the router caches and records. A fresh temporary
///     directory per call keeps runs of one suite apart.
///   - runClock: The run clock of the session, or `nil` for the real time.
///     See ``makeStubProfile(recorder:loader:standardModel:in:runClock:)``.
/// - Returns: The session and its context. The caller owns the session and
///   must close it on every path. ``withStubRun(in:runClock:_:)`` does that.
/// - Throws: Whatever resolving the profile throws, or
///   ``StubRunFailure/noContextCaptured``. Before this function throws after
///   it made the session, it closes the session.
func makeStubRun(
    in directory: URL = TestSupport.makeTemporaryDirectory(named: stubRouterDirectoryPrefix),
    runClock: (any RunClock)? = nil
) async throws -> StubRun {
    let box = CapturedContextBox()
    let stub = try await makeStubSession(
        mounting: [ContextCaptureTool(box: box)], in: directory, runClock: runClock)
    let context: ToolContext
    do {
        _ = try await stub.session.respond(to: "capture", maxTokens: nil)
        guard let captured = box.context else {
            throw StubRunFailure.noContextCaptured
        }
        context = captured
    } catch {
        // No caller gets this session, thus close it here.
        await stub.session.close()
        throw error
    }
    // The capture call above is real, and it posted its own events. Drop them
    // so a test reads only what it caused.
    await stub.recorder.reset()
    return StubRun(session: stub.session, context: context, recorder: stub.recorder)
}

/// Runs `body`, and then closes `session`. It closes the session when `body`
/// returns and when `body` throws.
///
/// Swift has no `defer` that can wait for an `async` call, thus the two
/// paths each close the session. A session that is not closed has no
/// contract: its tasks can still run after the test.
///
/// `RoutedSession.close()` is idempotent. Thus `body` can close the session
/// itself, for example through ``settledOperationEvents(of:ofKind:)``.
///
/// - Parameters:
///   - session: The session to close.
///   - body: The work that uses the session.
/// - Returns: What `body` returned.
/// - Throws: What `body` threw, after the session is closed.
func closing<Result>(
    _ session: any RoutedSession, after body: () async throws -> Result
) async throws -> Result {
    try await ensuring({ await session.close() }, after: body)
}

/// Runs `body`, and then runs `cleanup`. It runs `cleanup` when `body`
/// returns and when `body` throws.
///
/// Swift has no `defer` that can wait for an `async` call. This function is
/// the scoped form of that `defer`.
///
/// - Parameters:
///   - cleanup: The work that must run on every path, for example the
///     release of a gate that holds a run body.
///   - body: The work to do first.
/// - Returns: What `body` returned.
/// - Throws: What `body` threw, after `cleanup` ran.
func ensuring<Result>(
    _ cleanup: () async -> Void, after body: () async throws -> Result
) async throws -> Result {
    let result: Result
    do {
        result = try await body()
    } catch {
        await cleanup()
        throw error
    }
    await cleanup()
    return result
}

/// Makes a stub run, gives it to `body`, and closes its session on every
/// path.
///
/// - Parameters:
///   - directory: Where the router caches and records. See
///     ``makeStubRun(in:runClock:)``.
///   - runClock: The run clock of the session, or `nil` for the real time.
///   - body: The work that uses the run.
/// - Returns: What `body` returned.
/// - Throws: What making the run throws, or what `body` threw.
func withStubRun<Result>(
    in directory: URL = TestSupport.makeTemporaryDirectory(named: stubRouterDirectoryPrefix),
    runClock: (any RunClock)? = nil,
    _ body: (StubRun) async throws -> Result
) async throws -> Result {
    let run = try await makeStubRun(in: directory, runClock: runClock)
    return try await closing(run.session) { try await body(run) }
}

/// Makes a stub session that mounts `tools`, gives it to `body`, and closes
/// the session on every path.
///
/// - Parameters:
///   - tools: The tools the session mounts.
///   - loader: The loader the router loads its models through.
///   - standardModel: The model reference of the `standard` slot.
///   - directory: Where the router caches and records.
///   - runClock: The run clock of the session, or `nil` for the real time.
///   - body: The work that uses the session and its recorder.
/// - Returns: What `body` returned.
/// - Throws: What making the session throws, or what `body` threw.
/// - SeeAlso: ``makeStubSession(mounting:loader:standardModel:in:runClock:)``.
func withStubSession<Result>(
    mounting tools: [any Tool],
    loader: StubModelLoader = StubModelLoader(),
    standardModel: ModelRef = stubStandardModel,
    in directory: URL = TestSupport.makeTemporaryDirectory(named: stubRouterDirectoryPrefix),
    runClock: (any RunClock)? = nil,
    _ body: (any RoutedSession, CollectingTranscriptRecorder) async throws -> Result
) async throws -> Result {
    let stub = try await makeStubSession(
        mounting: tools, loader: loader, standardModel: standardModel, in: directory, runClock: runClock)
    return try await closing(stub.session) { try await body(stub.session, stub.recorder) }
}

/// Runs one mounted call that must go to the background, and moves the run
/// clock past its settle period. No real time passes.
///
/// The order is fixed. The call starts, and the test waits until the timers
/// of the call wait on `clock`
/// (``ManualRunClock/waitForSleepers(atLeast:orUntil:)``). Then the clock
/// moves by `grace`, the settle period ends, and the call answers with its
/// pending envelope. The work of the call must not end by itself before
/// that: hold it on a gate that the test opens later.
///
/// The wait for the timers also ends when the call ends first, or when the
/// task of the test is cancelled. A call that ends with no timer on the clock
/// then gives its answer, and the check of the test on that answer fails.
/// A cancel of the task of the test also cancels the call.
///
/// - Parameters:
///   - clock: The run clock of the session that the call is mounted on.
///   - grace: The settle period of the call, in seconds. It must be the
///     full configured period, or more.
///   - timers: How many timers the call puts on `clock` while it waits for
///     its settle period. The settle period is one timer, and a run timeout
///     is one more.
///   - call: The mounted call.
/// - Returns: What the call answered.
/// - Throws: What the call throws.
func callPastSettlePeriod<Answer: Sendable>(
    on clock: ManualRunClock,
    grace: TimeInterval,
    timers: Int,
    _ call: @escaping @Sendable () async throws -> Answer
) async throws -> Answer {
    let sleepersBefore = clock.sleeperCount
    let answer = Task { try await call() }
    return try await withTaskCancellationHandler {
        await clock.waitForSleepers(atLeast: sleepersBefore + timers, orUntil: { _ = await answer.result })
        clock.advance(by: .seconds(grace))
        return try await answer.value
    } onCancel: {
        answer.cancel()
    }
}

/// How many timers a mounted call with no run timeout puts on the run clock
/// while it waits for its settle period: the settle period alone.
let settlePeriodTimers = 1

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
                "num_key_value_heads":2,"head_dim":16,"hidden_size":128,\
                "max_position_embeddings":8192}
                """.utf8),
            treeJSON: Data(
                """
                [{"type":"file","path":"model.safetensors","size":10000000}]
                """.utf8))
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

/// Every `OperationEvent` of `run`, read after the session is closed, so the
/// journal holds every event the run posted.
///
/// Router merges consecutive progress events of one run into one journal row
/// (Router commit c30d1d41). The first progress event of a run is written at
/// once. The next ones stay in an open row in memory, and that row is written
/// only when a different entry comes or when `RoutedSession.close()` runs.
/// Thus a read of the recorder while the session is open sees the first
/// progress event and not the rest. Each event stays whole inside the row, and
/// the recorder reads every segment of every row, so after `close()` this read
/// returns every progress event, in post order, with none lost and none
/// joined.
///
/// Close the session only when the test is done with it: `close()` settles
/// every run the session holds.
///
/// - Parameters:
///   - run: The stub run whose session to close and whose transcript to read.
///   - kind: The one event kind to keep, or `nil` for every kind.
/// - Returns: The recorded events, in transcript order.
func settledOperationEvents(
    of run: StubRun, ofKind kind: OperationEventKind? = nil
) async -> [OperationEvent] {
    await run.session.close()
    return await recordedOperationEvents(of: run, ofKind: kind)
}

/// The recorded `OperationEvent`s of `run` of one kind, on the runs
/// `correlationIDs` name, read one time with no wait.
///
/// A `.progress` event a verb posts through `ToolContext.post(_:)` is
/// journaled before `post` returns: `SessionOutbox.post(event:)` awaits its
/// own journal write. But Router merges consecutive progress events of one
/// run into one open row that it writes later, so a read while the session is
/// open sees only the first progress event of a run. A test that reads more
/// than one progress event of a run reads with ``settledOperationEvents(of:ofKind:)``.
/// The waiting variant below is for the sweep `RoutedSession.close()` runs on
/// a task of its own.
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
/// The wait is an event: the recorder resumes it when an append brings the
/// count to `count` (``CollectingTranscriptRecorder/waitUntil(_:)``). It
/// reads no clock and does not poll.
///
/// - Parameters:
///   - run: The stub run whose journal to read.
///   - kind: The event kind to keep.
///   - correlatedTo: The runs to keep, by `correlationID`, or `nil` for every
///     run of the session.
///   - count: How many to wait for.
/// - Returns: The events, once `count` of them are there, or whatever was
///   journaled when the task was cancelled.
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
    @Sendable func matching(_ events: [OperationEvent]) -> [OperationEvent] {
        events.filter { event in
            event.kind == kind && (correlationIDs?.contains(event.correlationID) ?? true)
        }
    }
    _ = await run.recorder.waitUntil { matching($0).count >= count }
    return matching(await run.recorder.operationEvents)
}
