import Foundation
import ScenarioGrading
import Testing

@testable import FoundationModelsMultitool

/// The offline checks of the shared `RESULT` line of a gated answer:
/// `gatedResultLine(of:elapsed:readings:replyPreviewCharacters:)` and the
/// field readings that the gated suites give to it.
///
/// Each check makes a `StreamedAnswer` by hand. No check loads a model. Thus
/// each check always runs, and a change to the order or to the text of a
/// field fails here before a live run prints a different line.
@Suite("Gated result line: the route, the readings of the scenario, then the start of the reply")
struct GatedResultLineTests {

    /// The snippet of the answer of each check. It calls one verb.
    private static let snippetArguments = #"{"code":"return await tools.git.diff({})"}"#

    /// The reply of the answer of each check.
    private static let reply = "The function area is now surface."

    /// How many characters of the reply each check shows.
    private static let replyPreviewCharacters = 12

    /// How long the answer of each check took, in seconds.
    private static let elapsed: TimeInterval = 2.5

    /// An answer with one `runCode` call, one failed call, a priming failure, and
    /// a reply.
    private static var answer: StreamedAnswer {
        var run = StreamedAnswer()
        run.answer = reply
        run.toolCallCount = 1
        run.calls = [
            NativeTranscript.StreamedCall(name: MultiTool.runCodePath, argumentsJSON: snippetArguments, output: nil)
        ]
        run.failedCalls = ["runCode: refused"]
        run.discoveryPrimingFailure = "busy"
        return run
    }

    @Test("the line holds the route, then each reading in order, then the start of the reply")
    func theLineHoldsTheRouteTheReadingsAndTheReply() {
        let line = gatedResultLine(
            of: Self.answer,
            elapsed: Self.elapsed,
            readings: ["first=1", "second=2"],
            replyPreviewCharacters: Self.replyPreviewCharacters)
        #expect(line == #"elapsed=2.5s toolCalls=1 calls=["runCode"] first=1 second=2 reply="The function""#)
    }

    @Test("a line with no reading holds the route, then the start of the reply")
    func aLineWithNoReadingHoldsTheRouteAndTheReply() {
        let line = gatedResultLine(
            of: Self.answer, elapsed: Self.elapsed, readings: [], replyPreviewCharacters: Self.replyPreviewCharacters)
        #expect(line == #"elapsed=2.5s toolCalls=1 calls=["runCode"] reply="The function""#)
    }

    @Test("the typed reading names each verb that the snippets called")
    func theTypedReadingNamesTheSnippetVerbs() {
        #expect(typedPathsReading(of: Self.answer) == #"typed=["git.diff"]"#)
    }

    @Test("the priming reading names why the priming did not run")
    func thePrimingReadingNamesTheFailure() {
        #expect(primingReading(of: Self.answer) == "priming=FAILED(busy)")
    }

    @Test("the failed calls reading names each failed call")
    func theFailedCallsReadingNamesEachFailedCall() {
        #expect(failedCallsReading(of: Self.answer) == #"failedCalls=["runCode: refused"]"#)
    }
}
