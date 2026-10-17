import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsRouter

@testable import MultitoolTestSupport

// MARK: - Phase-1 sandbox-globals fixtures (eventplan.md § "The sandbox
// globals")
//
// The background runs a snippet's `status()`/`cancel()` observe are
// the session's own runs, and the answer its `elicit()` waits for arrives
// through the same run plane of the session. Both are scripted here rather than
// simulated: a real run plane, a real background run, and a real elicitation
// reply — so what these tests exercise is the actual Router surface, not a
// stand-in.
//
// A run goes to the background the way a real one does. The site mounts the
// call in the background, so the mount engine backgrounds it and hands back
// the pending envelope. Nothing here registers a run by hand: the run plane's
// bookkeeping is Router's own wiring, and a host reads it only through
// `ToolContext` (Router task ^k0mecjp).

/// A one-shot gate that holds a scripted background run going until a test
/// decides it should finish.
///
/// An `actor` rather than a lock-guarded class because both sides of the gate
/// are already `async`: the background run's finishing `Task` suspends on
/// ``wait()``, and the test resumes it from ``open()``.
actor SettlementGate {
    /// Whether ``open()`` has already been called — a run that arrives late
    /// must not suspend forever.
    private var isOpen = false

    /// Every settling `Task` currently suspended on this gate.
    private var suspended: [CheckedContinuation<Void, Never>] = []

    /// Suspends until ``open()`` is called, or returns immediately when it
    /// already has been.
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { suspended.append($0) }
    }

    /// Resumes every suspended waiter and lets every later ``wait()`` through.
    func open() {
        guard !isOpen else { return }
        isOpen = true
        let waiting = suspended
        suspended = []
        for continuation in waiting {
            continuation.resume()
        }
    }
}

/// One scripted background run: the row a snippet's `status()` lists, and the
/// gate that decides when the run finishes.
struct ScriptedRun: Sendable {
    /// The run's completion token — also its terminal event's
    /// `correlationID`. Minted by the engine, read back out of the pending
    /// envelope the backgrounded call returned.
    let completionToken: String

    /// The tool's name that owns the run.
    let tool: String

    /// The op string of the backgrounded operation. The engine stamps a run
    /// with its tool's own name, so this is `tool` — assert against this field
    /// rather than a literal, and the fixture stays the one source of it.
    let op: String

    /// The gate that holds the run going.
    let gate: SettlementGate
}

/// The outcome a scripted run's cancellation reports — cooperative
/// cancellation of a `RunKind/swiftTask`, requested but not certain. The
/// engine's own canceler reports it; this names the value a test expects.
let scriptedRunCancelOutcome: OperationOutcome = .cancelled

/// The deadline a fixture gives `ToolContext.wait(completionToken:seconds:)`
/// when it waits for a run plane to record a settlement: `nil`, no deadline.
///
/// This is a synchronization point, not a timing assertion — the wait
/// resolves the instant the run plane records the terminal event. No clock ends
/// it (card `^tm4x2hp`: no test checks the speed of the machine). A run that
/// never settles makes the test hang, and that hang is the failure.
let scriptedRunSettlementSeconds: Double? = nil

/// What a scripted run could not do.
enum ScriptedRunFailure: Error, CustomStringConvertible {
    /// The call returned something other than a pending envelope, so the run
    /// never went to the background — the text it returned instead.
    case didNotBackground(String)

    /// The run posted its progress detail, but the run's status row did not
    /// show it — the detail that was awaited.
    case progressNeverArrived(String)

    var description: String {
        switch self {
        case .didNotBackground(let text):
            return "the call returned \"\(text)\" instead of going to the background"
        case .progressNeverArrived(let detail):
            return "progress \"\(detail)\" never reached the run's status row"
        }
    }
}

/// The failure a scripted run raises when a test asks it to fail rather than
/// deliver a result.
///
/// Thrown from the tool's own `call(arguments:)`, so the terminal event the
/// engine records carries the outcome a genuinely failing tool produces —
/// which is what a run reporting `error` has to be measured against.
struct ScriptedToolFailure: Error, CustomStringConvertible {
    /// What the tool reports as its reason for failing.
    let description: String
}

/// A tool whose call blocks until its gate opens.
///
/// Genuinely slow: the call blocks until its gate opens, so the run stays
/// going while a test reads it and drives it.
final class GatedScriptedTool: Tool, Sendable {
    let name: String
    let description = "Blocks until its gate opens, then returns its scripted detail."

    /// The gate that holds the call — and so the run — open.
    private let gate: SettlementGate

    /// The gate the fixture opens once the run is in the background.
    private let backgrounded: SettlementGate

    /// The gate the call opens once its progress post returned. A cancel of
    /// the task of a waiter ends its wait, thus a test can also end the wait
    /// on the end of the run.
    private let progressPosted: TestGate

    /// What the call returns once the gate opens; the terminal event's
    /// detail. Also the reason it throws, when `fails` is set.
    private let detail: String

    /// The progress detail to post once backgrounded, or `nil` to post none.
    private let progress: String?

    /// Whether the call throws once its gate opens rather than returning.
    private let fails: Bool

    /// Creates a gated tool.
    ///
    /// - Parameters:
    ///   - name: the tool's name, which the engine also stamps as the run's op.
    ///   - gate: the gate to block on.
    ///   - backgrounded: the gate that reports the run is in the background.
    ///   - progressPosted: the gate the call opens once its progress post
    ///     returned.
    ///   - detail: what to return once the gate opens.
    ///   - progress: the progress detail to post once backgrounded, or `nil`.
    ///   - fails: whether to throw once the gate opens rather than return.
    init(
        name: String,
        gate: SettlementGate,
        backgrounded: SettlementGate,
        progressPosted: TestGate,
        detail: String,
        progress: String?,
        fails: Bool
    ) {
        self.name = name
        self.gate = gate
        self.backgrounded = backgrounded
        self.progressPosted = progressPosted
        self.detail = detail
        self.progress = progress
        self.fails = fails
    }

    func call(arguments: NoArguments) async throws -> String {
        if let progress {
            // Only once the run is in the background. The mount engine
            // records a progress detail against the run's status row
            // (`RunPlane.updateProgress`). `RunPlane.start` makes
            // that row, and a post that arrives before it updates nothing.
            // `BackgroundToolRunner` holds this body on a start gate until
            // after it tracks the run, so that order already holds. This gate
            // states the order at the fixture too, and the tests that read
            // `latestProgress` do not depend on that internal step.
            await backgrounded.wait()
            // The run records the detail on its status row before this post
            // returns (`ToolRun.post(event:)` awaits
            // `RunPlane.updateProgress`). Thus the gate opens after the row
            // shows the detail, in a fixed order.
            await ToolContext.current?.progress(progress)
            progressPosted.open()
        }
        await gate.wait()
        if fails { throw ScriptedToolFailure(description: detail) }
        return detail
    }
}

// The run plane is read through the `ToolContext` a stub session hands out.
// The run plane of a session is internal to Router, so a test cannot own it.
// What the test owns instead is a real session, and the context that session binds around a
// tool call reads that session's own run plane. See `StubRouterFixtures.swift`.

/// Starts a scripted background run on the run plane of `context` and returns the handle a test
/// drives it through.
///
/// The run keeps going — and so stays visible to `status()` — until
/// ``settle(_:on:)`` opens its gate.
///
/// The call waits for the settle period of the session before it answers
/// with the pending envelope. That period waits on `clock`, and this moves
/// `clock` past it after its timer waits
/// (``callPastSettlePeriod(on:grace:timers:_:)``). Thus no real time passes.
///
/// - Parameters:
///   - context: the session context to start the run on.
///   - clock: the run clock of the session of `context`.
///   - tool: the tool's name that owns the run; also the run's op.
///   - detail: what the call returns once it finishes — the detail a finished
///     run reports. Also the reason it throws when `failing`.
///   - progress: the latest progress detail `status()` should report, or
///     `nil` to let the run post none. When given, this returns only once that
///     detail has reached the run's status row, so a following assertion never
///     races the post.
///   - failing: whether the run throws once its gate opens rather than
///     returning `detail`, so its terminal event reports a failure.
/// - Returns: the background run's handle.
/// - Throws: ``ScriptedRunFailure`` when the call never went to the
///   background, or when a requested progress detail never arrived.
func startScriptedRun(
    on context: ToolContext,
    clock: ManualRunClock,
    tool: String = "shell",
    detail: String = "scripted-terminal-detail",
    progress: String? = nil,
    failing: Bool = false
) async throws -> ScriptedRun {
    let gate = SettlementGate()
    let backgrounded = SettlementGate()
    let progressPosted = TestGate()
    let engine = context.mount(
        GatedScriptedTool(
            name: tool,
            gate: gate,
            backgrounded: backgrounded,
            progressPosted: progressPosted,
            detail: detail,
            progress: progress,
            fails: failing
        ),
        // The scripted tool declares no mount of its own, so the site puts it
        // in the background: the call answers the envelope when the settle
        // period of the session ends, and the body goes on behind it under no
        // timeout.
        as: ToolMount(mode: .background, timeout: nil)
    )
    // The gate holds the body, thus the call answers only when the clock
    // moves past the settle period.
    let rendered = try await callPastSettlePeriod(
        on: clock, grace: context.inlineSettleGrace, timers: settlePeriodTimers
    ) {
        try await engine.call(arguments: NoArguments())
    }
    let completionToken: String
    do {
        guard PendingRunEnvelope.isRendered(text: rendered) else {
            throw ScriptedRunFailure.didNotBackground(rendered)
        }
        completionToken = try JSONDecoder()
            .decode(PendingRunEnvelope.self, from: Data(rendered.utf8))
            .completionToken
        if let progress {
            // The envelope is proof the run is in the background, so the call may
            // post now. The wait for the post also ends when the run ends: a
            // run that ended has no status row, and the check below then
            // throws.
            await backgrounded.open()
            let token = completionToken
            try await EventRace.firstOf(
                { try? await progressPosted.wait() },
                or: { await TerminalDetail.waitForEnd(of: token, in: context) })
            try await expectProgress(progress, of: completionToken, on: context)
        }
    } catch {
        // No caller gets the gate. Open the gates, so that the run body ends
        // and the close of the session does not wait for it.
        await backgrounded.open()
        await gate.open()
        throw error
    }
    return ScriptedRun(completionToken: completionToken, tool: tool, op: tool, gate: gate)
}

/// Starts a scripted background run, gives it to `body`, and opens its gate
/// on every path after `body`.
///
/// `SettlementGate.wait()` does not end on cancellation. Thus a run body that
/// is held on the gate does not end when the session closes, and
/// `RoutedSession.close()` waits for each run body to end. Use this form when
/// the test does not settle the run itself. The gate opens after the last
/// statement of `body`, thus it does not change what `body` checks.
///
/// - Parameters:
///   - context: the session context to start the run on.
///   - clock: the run clock of the session of `context`.
///   - tool: the tool's name that owns the run; also the run's op.
///   - detail: what the call returns once it finishes.
///   - progress: the latest progress detail `status()` should report, or `nil`.
///   - failing: whether the run throws once its gate opens.
///   - body: the work that uses the run.
/// - Returns: what `body` returned.
/// - Throws: what ``startScriptedRun(on:clock:tool:detail:progress:failing:)``
///   throws, or what `body` threw.
func withScriptedRun<Result>(
    on context: ToolContext,
    clock: ManualRunClock,
    tool: String = "shell",
    detail: String = "scripted-terminal-detail",
    progress: String? = nil,
    failing: Bool = false,
    _ body: (ScriptedRun) async throws -> Result
) async throws -> Result {
    let run = try await startScriptedRun(
        on: context, clock: clock, tool: tool, detail: detail, progress: progress, failing: failing)
    return try await ensuring({ await run.gate.open() }) { try await body(run) }
}

/// Checks one time that the run's status row reports `detail` as its latest
/// progress.
///
/// The caller calls this after the post of the tool returned. The run records
/// the detail on the status row before that post returns, thus one read is
/// enough, and nothing waits on a clock or polls.
///
/// - Parameters:
///   - detail: the progress detail to find.
///   - completionToken: the run that posted it.
///   - context: the session context the run is registered on.
/// - Throws: ``ScriptedRunFailure/progressNeverArrived(_:)`` when the row does
///   not show it.
private func expectProgress(
    _ detail: String, of completionToken: String, on context: ToolContext
) async throws {
    let row = await context.backgroundRuns().first { $0.completionToken == completionToken }
    guard row?.latestProgressDetail == detail else {
        throw ScriptedRunFailure.progressNeverArrived(detail)
    }
}

/// Settles a scripted background run and returns only once the run plane has
/// recorded its terminal event — a synchronization point, so a following
/// `status()` or `cancel()` assertion never races the settlement.
///
/// - Parameters:
///   - run: the background run to settle.
///   - context: the session context the run is registered on.
func settle(_ run: ScriptedRun, on context: ToolContext) async {
    await run.gate.open()
    _ = await context.wait(
        completionToken: run.completionToken, seconds: scriptedRunSettlementSeconds
    )
}

/// Answers every elicitation a run raises with one scripted response.
///
/// A consumer cannot inject an `OperationEventSink`, so this cannot observe
/// events by being handed them. It watches the run's journal instead — the
/// route that does carry `.elicitation` events — and answers through
/// `RoutedSession.respond(elicitationId:response:)`.
///
/// Make it with ``withScriptedElicitationSink(run:answering:_:)``. The watch
/// starts as soon as this is made, so make it BEFORE the snippet that
/// elicits. A URL-mode accept is a two-step flow: `respond` records the
/// accept and the snippet stays suspended, so an `.acceptedAwaitingCompletion`
/// delivery is followed by `complete(elicitationId:)`, exactly as a real
/// host's out-of-band flow would.
///
/// The watch waits on the recorder of the run
/// (``CollectingTranscriptRecorder/waitUntil(_:)``): it wakes when the journal
/// gets an elicitation that it did not answer yet. It reads no clock and does
/// not poll. The watch task is not a task of the session, thus the close of
/// the session does not end it. The scoped form ends it with ``stop()`` on
/// every path, so that no watch of one test waits on after that test.
///
/// The call to `respond` (or to `complete`) resumes the snippet before the
/// watch records the report of the session. Thus the snippet can return
/// before the log holds that report. A test reads the reports only with
/// ``deliveries(count:)`` and ``completions(count:)``: each one waits until
/// the log recorded the given count of reports. It waits on the record event,
/// not on a clock.
final class ScriptedElicitationSink: Sendable {
    /// What the watch observed and what the session reported.
    private let log: ElicitationAnswerLog

    /// The task that watches the journal and answers.
    private let watchTask: Task<Void, Never>

    /// Makes an answerer and starts watching at once.
    ///
    /// - Parameters:
    ///   - run: the run to watch and answer through.
    ///   - response: the answer to give.
    ///   - recordGate: a test hook. When it is not `nil`, the watch waits at
    ///     this gate before it records each delivery, and the log opens the
    ///     gate when a read of the reports starts to wait.
    fileprivate init(run: StubRun, answering response: ElicitationResponse, holdingRecordAt recordGate: TestGate?) {
        let log = ElicitationAnswerLog(readerWaits: recordGate)
        self.log = log
        watchTask = Task {
            await Self.watch(run, answering: response, into: log, holdingRecordAt: recordGate)
            await log.recordWatchEnd()
        }
    }

    /// Cancels the watch, and waits until the watch task ended.
    ///
    /// The wait on the recorder ends with `false` on a cancel, and the loop
    /// of the watch stops on a cancel. Thus the wait for the task ends.
    fileprivate func stop() async {
        watchTask.cancel()
        await watchTask.value
    }

    /// Whether the watch task ended.
    var watchEnded: Bool {
        get async { await log.watchEnded }
    }

    /// Every elicitation request observed, in arrival order.
    var requests: [ElicitationRequest] {
        get async { await log.requests }
    }

    /// What the session reported for each delivered answer, in delivery order.
    ///
    /// - Parameter count: the count of deliveries to wait for. The read
    ///   returns when the log recorded this count, or when the watch ended.
    /// - Returns: each recorded delivery.
    func deliveries(count: Int) async -> [ElicitationAnswerDelivery] {
        await log.deliveries(count: count)
    }

    /// What the session reported for each URL-mode completion.
    ///
    /// - Parameter count: the count of completions to wait for. The read
    ///   returns when the log recorded this count, or when the watch ended.
    /// - Returns: each recorded completion.
    func completions(count: Int) async -> [ElicitationCompletionDelivery] {
        await log.completions(count: count)
    }

    /// The first observed request, or `nil` when none arrived.
    var observedRequest: ElicitationRequest? {
        get async { await log.requests.first }
    }

    /// Answers each elicitation of the journal of `run` exactly one time.
    ///
    /// Each turn waits until the journal holds an elicitation that the log
    /// did not claim, and then answers each new one. `SessionEvent` carries no
    /// elicitation case, and the journal is where a drained elicitation lands.
    ///
    /// - Parameters:
    ///   - run: the run to watch and answer through.
    ///   - response: the answer to give.
    ///   - log: where the watch records what it observed.
    ///   - recordGate: the test hook where the watch waits before it records
    ///     each delivery, or `nil`.
    private static func watch(
        _ run: StubRun, answering response: ElicitationResponse, into log: ElicitationAnswerLog,
        holdingRecordAt recordGate: TestGate?
    ) async {
        while !Task.isCancelled {
            let answered = await log.answered
            let arrived = await run.recorder.waitUntil { events in
                events.contains { event in
                    guard event.kind == .elicitation, let request = event.elicitation else { return false }
                    return !answered.contains(request.elicitationId.description)
                }
            }
            guard arrived else { return }
            for event in await recordedOperationEvents(of: run, ofKind: .elicitation) {
                guard let request = event.elicitation, await log.claim(request) else { continue }
                let id = request.elicitationId.description
                let delivery = await run.session.respond(elicitationId: id, response: response)
                // The snippet can resume and return before this record.
                if let recordGate {
                    do { try await recordGate.wait() } catch { return }
                }
                await log.record(delivery: delivery)
                guard delivery == .acceptedAwaitingCompletion else { continue }
                await log.record(completion: await run.session.complete(elicitationId: id))
            }
        }
    }
}

/// Makes a ``ScriptedElicitationSink`` that answers each elicitation of
/// `run`, gives it to `body`, and ends its watch task on every path after
/// `body`.
///
/// The watch task is not a task of the session. Thus the close of the
/// session does not end it, and a watch that nobody stops waits on the
/// recorder after the test. Use this form inside the scope of the session,
/// so that the watch ends before the session closes.
///
/// - Parameters:
///   - run: the run to watch and answer through.
///   - response: the answer to give.
///   - recordGate: a test hook. When it is not `nil`, the watch waits at this
///     gate before it records each delivery, and the log opens the gate when
///     a read of the reports starts to wait. The default is `nil`.
///   - body: the work that elicits.
/// - Returns: what `body` returned.
/// - Throws: what `body` threw, after the watch ended.
func withScriptedElicitationSink<Result>(
    run: StubRun, answering response: ElicitationResponse,
    holdingRecordAt recordGate: TestGate? = nil,
    _ body: (ScriptedElicitationSink) async throws -> Result
) async throws -> Result {
    let sink = ScriptedElicitationSink(run: run, answering: response, holdingRecordAt: recordGate)
    return try await ensuring({ await sink.stop() }) { try await body(sink) }
}

/// What a ``ScriptedElicitationSink`` observed, and what the session reported
/// for each answer.
actor ElicitationAnswerLog {
    /// One read that waits until a list of the log holds a count of entries.
    private struct Waiter {
        /// The count of entries that ends the wait.
        let count: Int

        /// The read to resume.
        let continuation: CheckedContinuation<Void, Never>
    }

    /// Every elicitation request claimed, in arrival order.
    private(set) var requests: [ElicitationRequest] = []

    /// What the session reported for each delivered answer, in delivery order.
    private var recordedDeliveries: [ElicitationAnswerDelivery] = []

    /// What the session reported for each URL-mode completion.
    private var recordedCompletions: [ElicitationCompletionDelivery] = []

    /// Each read of ``deliveries(count:)`` that waits.
    private var deliveryWaiters: [Waiter] = []

    /// Each read of ``completions(count:)`` that waits.
    private var completionWaiters: [Waiter] = []

    /// The test hook that the log opens when a read starts to wait, or `nil`.
    private let readerWaits: TestGate?

    /// The elicitation ids already claimed, so the watch answers each one time.
    private(set) var answered: Set<String> = []

    /// Makes an empty log.
    ///
    /// - Parameter readerWaits: the test hook that the log opens when a read
    ///   starts to wait, or `nil`.
    init(readerWaits: TestGate?) {
        self.readerWaits = readerWaits
    }

    /// Waits until the log recorded `count` deliveries, or until the watch
    /// ended, and then returns each recorded delivery.
    ///
    /// - Parameter count: the count of deliveries to wait for.
    /// - Returns: each recorded delivery, in delivery order.
    func deliveries(count: Int) async -> [ElicitationAnswerDelivery] {
        if recordedDeliveries.count < count && !watchEnded {
            await withCheckedContinuation { continuation in
                deliveryWaiters.append(Waiter(count: count, continuation: continuation))
                readerWaits?.open()
            }
        }
        return recordedDeliveries
    }

    /// Waits until the log recorded `count` completions, or until the watch
    /// ended, and then returns each recorded completion.
    ///
    /// - Parameter count: the count of completions to wait for.
    /// - Returns: each recorded completion, in completion order.
    func completions(count: Int) async -> [ElicitationCompletionDelivery] {
        if recordedCompletions.count < count && !watchEnded {
            await withCheckedContinuation { continuation in
                completionWaiters.append(Waiter(count: count, continuation: continuation))
                readerWaits?.open()
            }
        }
        return recordedCompletions
    }

    /// Resumes each waiter whose count is reached, and keeps the others.
    ///
    /// - Parameters:
    ///   - waiters: the waiters of one list.
    ///   - count: the count of entries in that list now.
    /// - Returns: the waiters that still wait.
    private static func resume(_ waiters: [Waiter], reaching count: Int) -> [Waiter] {
        var waiting: [Waiter] = []
        for waiter in waiters {
            if waiter.count <= count {
                waiter.continuation.resume()
            } else {
                waiting.append(waiter)
            }
        }
        return waiting
    }

    /// Claims `request` for one answer.
    ///
    /// - Parameter request: the observed request.
    /// - Returns: `true` the first time, `false` when it was claimed before.
    func claim(_ request: ElicitationRequest) -> Bool {
        guard answered.insert(request.elicitationId.description).inserted else { return false }
        requests.append(request)
        return true
    }

    /// Records what the session reported for one answer.
    ///
    /// - Parameter delivery: the report of the session.
    func record(delivery: ElicitationAnswerDelivery) {
        recordedDeliveries.append(delivery)
        deliveryWaiters = Self.resume(deliveryWaiters, reaching: recordedDeliveries.count)
    }

    /// Records what the session reported for one URL-mode completion.
    ///
    /// - Parameter completion: the report of the session.
    func record(completion: ElicitationCompletionDelivery) {
        recordedCompletions.append(completion)
        completionWaiters = Self.resume(completionWaiters, reaching: recordedCompletions.count)
    }

    /// Whether the watch task ended.
    private(set) var watchEnded = false

    /// Records that the watch task ended, and ends each read that waits: no
    /// record comes after this.
    func recordWatchEnd() {
        watchEnded = true
        deliveryWaiters = Self.resume(deliveryWaiters, reaching: .max)
        completionWaiters = Self.resume(completionWaiters, reaching: .max)
    }
}

/// Reads the string case of one property of a requested schema as an
/// optional, thus a test can unwrap it with the require macro and does not
/// need a `guard case`.
extension ElicitationPrimitiveSchema {
    /// The string schema of the property, or `nil` when the property is a
    /// different case.
    var stringSchema: ElicitationStringSchema? {
        if case .string(let schema) = self {
            return schema
        }
        return nil
    }
}
