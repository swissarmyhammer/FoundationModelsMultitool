import Foundation
import FoundationModels
import FoundationModelsRouter
import os

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

// MARK: - A session that records the mail it gets
//
// Router delivers the terminal event of a settled background run to the
// session as mail: the pump puts it into the prompt of the next submission
// (`generation-queue.md` §5.5 rule 1). A unit test cannot read that prompt
// through the public session API. It can read it at the backend, because the
// backend is the code that gets each submission's prompt. Thus the backend of
// this file records the prompt of each submission, and it runs a scripted
// step of `runCode` calls in each one.

/// The code the gated fixture tool returns. No other text in a test prompt
/// contains it, thus a prompt that contains it carries the result of that
/// tool.
let mailProbeResultCode = "MAILPROBE7Q4X"

/// The arguments of ``GatedCodeTool``.
@Generable
struct GatedCodeArguments {
    /// Not read. A `@Generable` argument type needs one field.
    @Guide(description: "Not used.")
    var note: String?
}

/// The output of ``GatedCodeTool``.
@Generable
struct GatedCodeOutput {
    /// Always ``mailProbeResultCode``.
    var code: String
}

/// A tool that holds its call on a gate, and then returns
/// ``mailProbeResultCode``.
struct GatedCodeTool: Tool {
    /// The `tools.*` path of this tool.
    static let path = "gatedCode"

    let name = GatedCodeTool.path
    let description = "Returns a code after a gate opens."

    /// The gate the call waits on.
    let gate: ReleaseGate

    func call(arguments: GatedCodeArguments) async throws -> GatedCodeOutput {
        await gate.wait()
        return GatedCodeOutput(code: mailProbeResultCode)
    }
}

/// The snippet that returns the code of ``GatedCodeTool``.
let gatedCodeSnippet = "return (await tools.\(GatedCodeTool.path)({})).code;"

/// One scripted submission: what the backend does with the mounted `runCode`
/// before it answers.
///
/// - Parameters:
///   - index: The index of the submission, from `0`.
///   - runCode: The mounted `runCode`, as the model would call it.
/// - Returns: The answer text of the submission.
typealias MailProbeStep = @Sendable (
    _ index: Int, _ runCode: any Tool<RunCodeArguments, String>
) async throws -> String

/// The prompts a ``MailProbeBackend`` got, in order.
///
/// A `final class` behind a lock, because the backend and the test read and
/// write it from different tasks.
final class MailProbePrompts: Sendable {
    /// The prompts so far.
    private let prompts = OSAllocatedUnfairLock<[String]>(initialState: [])

    /// Records one prompt.
    ///
    /// - Parameter prompt: The prompt of one submission.
    /// - Returns: The index of that submission, from `0`.
    func record(_ prompt: String) -> Int {
        prompts.withLock { all in
            all.append(prompt)
            return all.count - 1
        }
    }

    /// The prompts so far, in order.
    var all: [String] {
        prompts.withLock { $0 }
    }

    /// Waits until at least `count` prompts are recorded, or until
    /// `TestPoll.deadline` passes.
    ///
    /// - Parameter count: How many prompts to wait for.
    /// - Returns: The prompts at that time.
    func awaiting(_ count: Int) async -> [String] {
        let deadline = ContinuousClock.now.advanced(by: TestPoll.deadline)
        var current = all
        while current.count < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: TestPoll.interval)
            current = all
        }
        return current
    }
}

/// A session backend that records each submission's prompt and runs one
/// scripted ``MailProbeStep`` in it.
///
/// A plain `Sendable` conformance: every stored property is immutable and
/// `Sendable`, and the one mutable state, the transcript, is behind a lock.
final class MailProbeBackend: LanguageModelSessionBackend, Sendable {
    /// The mounted tools this backend was made over.
    private let tools: [any Tool]

    /// Where each prompt goes.
    private let prompts: MailProbePrompts

    /// What each submission does.
    private let step: MailProbeStep

    /// What the session records as its transcript.
    private let entries = OSAllocatedUnfairLock<[Transcript.Entry]>(initialState: [])

    /// Makes a backend over `tools`.
    ///
    /// - Parameters:
    ///   - tools: The mounted tools, already wrapped by the engine.
    ///   - prompts: Where each prompt goes.
    ///   - step: What each submission does.
    init(tools: [any Tool], prompts: MailProbePrompts, step: @escaping MailProbeStep) {
        self.tools = tools
        self.prompts = prompts
        self.step = step
    }

    /// Records `prompt`, runs the step of its submission, and records the
    /// answer.
    ///
    /// - Parameter prompt: The prompt of the submission.
    /// - Returns: The answer of the step.
    /// - Throws: ``MailProbeFailure/noRunCode`` when no mounted tool takes
    ///   `RunCodeArguments`, and what the step throws.
    private func answer(_ prompt: String) async throws -> String {
        let index = prompts.record(prompt)
        guard let runCode = tools.lazy.compactMap({ $0 as? any Tool<RunCodeArguments, String> }).first else {
            throw MailProbeFailure.noRunCode
        }
        let answer = try await step(index, runCode)
        entries.withLock { all in
            all.append(.prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: prompt))])))
            all.append(.response(Transcript.Response(segments: [.text(Transcript.TextSegment(content: answer))])))
        }
        return answer
    }

    func respond(to prompt: String, maxTokens: Int?) async throws -> String {
        try await answer(prompt)
    }

    func respond(
        to prompt: String, following grammar: Grammar, maxTokens: Int?
    ) async throws -> String {
        try await answer(prompt)
    }

    func streamResponse(
        to prompt: String, maxTokens: Int?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(try await self.answer(prompt))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func makeFork() -> any LanguageModelSessionBackend {
        MailProbeBackend(tools: tools, prompts: prompts, step: step)
    }

    func transcriptEntries() -> [Transcript.Entry] {
        entries.withLock { $0 }
    }

    func usageTokenCounts() -> (input: Int, output: Int)? { (1, 1) }
}

/// A resident model that hands each session a ``MailProbeBackend``.
///
/// All four factories are written out, for the reason ``StubLLMContainer``
/// states.
struct MailProbeContainer: LoadedLLMContainer {
    /// Counts one token per word, as ``StubLLMContainer`` does.
    let tokenCounter: any TokenCounter = StubWordTokenCounter()

    /// Where each backend records its prompts.
    let prompts: MailProbePrompts

    /// What each submission does.
    let step: MailProbeStep

    func makeSession(instructions: String?) -> any LanguageModelSessionBackend {
        MailProbeBackend(tools: [], prompts: prompts, step: step)
    }

    func makeSession(
        instructions: String?, tools: [any Tool]
    ) -> any LanguageModelSessionBackend {
        MailProbeBackend(tools: tools, prompts: prompts, step: step)
    }

    func makeSession(transcript: Transcript) -> any LanguageModelSessionBackend {
        MailProbeBackend(tools: [], prompts: prompts, step: step)
    }

    func makeSession(
        transcript: Transcript, tools: [any Tool]
    ) -> any LanguageModelSessionBackend {
        MailProbeBackend(tools: tools, prompts: prompts, step: step)
    }
}

/// Makes a Router session over a ``MailProbeBackend`` that mounts `runCode`.
///
/// The `standard` model reference is fresh for each session: Router keeps a
/// loaded model in the process-wide `ModelPool.shared` by its reference, and a
/// shared reference would give this session the container of another test.
///
/// - Parameters:
///   - runCode: The `runCode` the session mounts.
///   - prompts: Where the backend records each prompt.
///   - step: What each submission does.
/// - Returns: The session.
/// - Throws: What resolving the stub profile throws.
func makeMailProbeSession(
    mounting runCode: MultiTool, prompts: MailProbePrompts, step: @escaping MailProbeStep
) async throws -> RoutedSession {
    let loader = StubModelLoader(container: MailProbeContainer(prompts: prompts, step: step))
    return try await makeStubSession(
        mounting: [runCode], loader: loader, standardModel: ModelRef(stringLiteral: "stub/mailprobe-\(ULID.generate())")
    ).session
}

/// What a ``MailProbeBackend`` could not do.
enum MailProbeFailure: Error, CustomStringConvertible {
    /// No mounted tool takes `RunCodeArguments`.
    case noRunCode

    /// The `runCode` output is not a pending envelope.
    case notAnEnvelope(String)

    var description: String {
        switch self {
        case .noRunCode:
            return "the session mounts no tool that takes RunCodeArguments"
        case .notAnEnvelope(let output):
            return "the runCode output is not a pending envelope: \(output)"
        }
    }
}

/// Decodes the envelope a mounted `runCode` call answered with.
///
/// - Parameter rendered: The call's output.
/// - Returns: The decoded envelope.
/// - Throws: ``MailProbeFailure/notAnEnvelope(_:)`` when the output is not an
///   envelope, and what `JSONDecoder` throws.
func mailProbeEnvelope(_ rendered: String) throws -> PendingRunEnvelope {
    guard PendingRunEnvelope.isRendered(text: rendered) else {
        throw MailProbeFailure.notAnEnvelope(rendered)
    }
    return try JSONDecoder().decode(PendingRunEnvelope.self, from: Data(rendered.utf8))
}
