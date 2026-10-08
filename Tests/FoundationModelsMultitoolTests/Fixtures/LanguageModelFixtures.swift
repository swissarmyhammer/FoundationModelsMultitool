import FoundationModels
import FoundationModelsMetadataRegistry
import os

@testable import FoundationModelsMultitool

// MARK: - `ScriptedLanguageModel` — a zero-GPU FoundationModels model
//
// No test of this target touches a real model. The selection tier and the
// sample-snippet generator get a `ScriptedLanguageModel`: a FoundationModels
// `LanguageModel` that loads nothing and answers each generation call from a
// script. The code under test makes real `LanguageModelSession`s on it.

/// One generation call that a ``ScriptedLanguageModel`` answered.
struct ScriptedModelCall: Sendable, Equatable {
    /// The text of the instructions entry of the transcript of the call, or
    /// `nil` when the session has no instructions.
    let instructions: String?

    /// The text of each prompt entry of the transcript of the call, in order.
    /// A new session has one prompt entry. Each later turn of the same
    /// session adds one.
    let prompts: [String]

    /// The text of the newest prompt entry: the prompt of this call.
    var prompt: String? { prompts.last }
}

/// One answer in the script of a ``ScriptedLanguageModel``.
enum ScriptedAnswer: Sendable {
    /// Gives this text, for example a `Selection` as JSON.
    case text(String)

    /// Waits for the duration, and then gives the text.
    case delayed(String, by: Duration)

    /// Throws the error.
    case failure(any Error & Sendable)
}

/// The errors that a ``ScriptedLanguageModel`` throws for itself.
enum ScriptedLanguageModelError: Error, Equatable, CustomStringConvertible {
    /// The model received more calls than its script has answers — a test bug
    /// (an under-scripted fixture), never a condition the code under test
    /// should trigger on a correctly scripted fixture.
    case unscripted(answerCount: Int)

    var description: String {
        switch self {
        case .unscripted(let answerCount):
            return "ScriptedLanguageModel received more calls than its \(answerCount) scripted answer(s)."
        }
    }
}

/// The script that each copy of one ``ScriptedLanguageModel`` plays, and the
/// log of the calls that it answered.
///
/// A class, because the identity of the script is the cache key of the
/// executor, and because all copies of one model share one log. The mutable
/// state is under one lock, so the class is `Sendable`.
final class ScriptedLanguageModelScript: Sendable {
    /// The answer for a call, given the call and its 0-based index in call
    /// order.
    private let answerForCall: @Sendable (_ call: ScriptedModelCall, _ index: Int) -> ScriptedAnswer

    /// The calls that the model answered, in order, under one lock.
    private let recordedCalls = OSAllocatedUnfairLock<[ScriptedModelCall]>(initialState: [])

    /// Makes a script of fixed answers.
    ///
    /// - Parameter answers: The answers, in call order. A call after the last
    ///   answer throws ``ScriptedLanguageModelError/unscripted(answerCount:)``.
    init(answers: [ScriptedAnswer]) {
        self.answerForCall = { _, index in
            answers.indices.contains(index)
                ? answers[index] : .failure(ScriptedLanguageModelError.unscripted(answerCount: answers.count))
        }
    }

    /// Makes a script that computes the answer of each call from the call.
    ///
    /// - Parameter responder: Gives the answer for one call.
    init(answering responder: @escaping @Sendable (_ call: ScriptedModelCall) -> ScriptedAnswer) {
        self.answerForCall = { call, _ in responder(call) }
    }

    /// The calls that the model answered, in order.
    var calls: [ScriptedModelCall] { recordedCalls.withLock { $0 } }

    /// Adds `call` to the log and gives the answer for it.
    ///
    /// - Parameter call: The call that the model answers.
    /// - Returns: The text of the answer for this call.
    /// - Throws: The error of a `.failure` answer.
    fileprivate func answer(_ call: ScriptedModelCall) async throws -> String {
        let index = recordedCalls.withLock { calls -> Int in
            calls.append(call)
            return calls.count - 1
        }
        switch answerForCall(call, index) {
        case .text(let text):
            return text
        case .delayed(let text, let delay):
            try await Task.sleep(for: delay)
            return text
        case .failure(let error):
            throw error
        }
    }
}

/// A FoundationModels `LanguageModel` that loads nothing and answers each
/// generation call from a script, in order. It writes each call to the log of
/// the script first.
///
/// All copies of one model share one script, so a test keeps the model it
/// gave to the code under test and reads ``calls`` from it.
struct ScriptedLanguageModel: LanguageModel {
    /// The executor that plays the script.
    typealias Executor = ScriptedLanguageModelExecutor

    /// The script that the model plays.
    let script: ScriptedLanguageModelScript

    /// Makes a model that plays `answers`, in call order.
    ///
    /// - Parameter answers: The answers, in call order.
    init(answers: [ScriptedAnswer]) {
        self.script = ScriptedLanguageModelScript(answers: answers)
    }

    /// Makes a model that gives `texts`, in call order: the common case of a
    /// script with no failure and no delay.
    ///
    /// - Parameter texts: The text of each answer, in call order.
    init(_ texts: [String]) {
        self.init(answers: texts.map(ScriptedAnswer.text))
    }

    /// Makes a model that computes the answer of each call from the call, for
    /// a test that cannot know the count of calls before they come.
    ///
    /// - Parameter responder: Gives the answer for one call.
    init(answering responder: @escaping @Sendable (_ call: ScriptedModelCall) -> ScriptedAnswer) {
        self.script = ScriptedLanguageModelScript(answering: responder)
    }

    /// Guided generation, so a session can ask for a `Generable` type such as
    /// `Selection`.
    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration])
    }

    /// The cache key of the executor: the identity of the script.
    var executorConfiguration: ScriptedLanguageModelExecutor.Configuration {
        ScriptedLanguageModelExecutor.Configuration(script: ObjectIdentifier(script))
    }

    /// The calls that the model answered, in order.
    var calls: [ScriptedModelCall] { script.calls }
}

/// The executor of ``ScriptedLanguageModel``.
struct ScriptedLanguageModelExecutor: LanguageModelExecutor {
    /// The cache key that the SDK makes and reuses the executor by.
    struct Configuration: Sendable, Hashable {
        /// The identity of the script that the model plays.
        let script: ObjectIdentifier
    }

    /// The model that this executor runs for.
    typealias Model = ScriptedLanguageModel

    /// The token count of the one emitted fragment. The double meters
    /// nothing.
    private static let emittedTokenCount = 1

    /// Makes an executor. The configuration holds nothing that the executor
    /// reads: the script arrives with the model on each call.
    ///
    /// - Parameter configuration: The cache key.
    /// - Throws: Never. `throws` comes from the `LanguageModelExecutor`
    ///   requirement.
    init(configuration: Configuration) throws {}

    /// Writes the call to the log of the script, and emits the answer of the
    /// script.
    ///
    /// - Parameters:
    ///   - request: The generation request with the full transcript.
    ///   - model: The model with the script.
    ///   - channel: The channel that the answer goes into.
    /// - Throws: The error of the script for this call.
    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: ScriptedLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let call = ScriptedModelCall(
            instructions: Self.instructionsText(in: request.transcript),
            prompts: Self.promptTexts(in: request.transcript)
        )
        let text = try await model.script.answer(call)
        await channel.send(.response(action: .appendText(text, tokenCount: Self.emittedTokenCount)))
    }

    /// The text of the first instructions entry of `transcript`.
    ///
    /// - Parameter transcript: The transcript of a generation call.
    /// - Returns: The text of the entry, or `nil` when there is none.
    private static func instructionsText(in transcript: Transcript) -> String? {
        transcript.lazy.compactMap { entry -> String? in
            guard case .instructions(let instructions) = entry else { return nil }
            return text(of: instructions.segments)
        }.first
    }

    /// The text of each prompt entry of `transcript`, in order.
    ///
    /// - Parameter transcript: The transcript of a generation call.
    /// - Returns: The text of each prompt entry.
    private static func promptTexts(in transcript: Transcript) -> [String] {
        transcript.compactMap { entry in
            guard case .prompt(let prompt) = entry else { return nil }
            return text(of: prompt.segments)
        }
    }

    /// The text of the text segments of `segments`, joined.
    ///
    /// - Parameter segments: The segments of a transcript entry.
    /// - Returns: The joined text.
    private static func text(of segments: [Transcript.Segment]) -> String {
        segments.compactMap { segment in
            guard case .text(let text) = segment else { return nil }
            return text.content
        }.joined()
    }
}

// MARK: - `CallCounter` — a thread-safe call counter

/// A thread-safe call counter — used to assert a closure ran an exact number
/// of times without needing a bespoke lock-boxed fixture per test.
final class CallCounter: Sendable {
    /// This counter's current count.
    private let countBox = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// Creates a counter starting at `0`.
    init() {}

    /// Increments the count and returns its new value.
    ///
    /// - Returns: the count after incrementing.
    @discardableResult
    func increment() -> Int {
        countBox.withLock { count -> Int in
            count += 1
            return count
        }
    }

    /// This counter's current count.
    var count: Int { countBox.withLock { $0 } }
}

// MARK: - `TripCitiesTool` — a standalone fixture tool

/// The `Output` of `TripCitiesTool` — a fixed trip itinerary.
@Generable
struct TripCitiesOutput {
    var cities: [String]
}

/// A standalone, no-argument tool returning a fixed trip itinerary — reuses
/// `NoArguments` (`MultiToolExecutionFixtures.swift`), the established
/// zero-meaningful-argument fixture shape this test target already uses for
/// `CitiesTool`.
struct TripCitiesTool: Tool {
    let name = "getTrip"
    let description = "The cities on the user's current trip, in itinerary order."

    func call(arguments: NoArguments) async throws -> TripCitiesOutput {
        TripCitiesOutput(cities: ["ATX", "SFO"])
    }
}
